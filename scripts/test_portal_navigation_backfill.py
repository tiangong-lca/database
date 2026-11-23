#!/usr/bin/env python3
"""Replay populated navigation shards and deterministic races in an empty local DB.

Only an explicitly named local Docker Supabase container is accepted. Fixtures
live in existing public-safe projection parents; no raw datasets are modified.
An advisory barrier freezes the exact migration after its cursor read and before
its INSERT, allowing a second connection to withdraw or update that version.
All committed fixture rows and the temporary barrier trigger are removed.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess
import time

from benchmark_portal_summary_bounded import run

ROOT = Path(__file__).resolve().parents[1]
IDENTITY = "656de000-0000-4000-8000-000000000001"
LOCK = 65619131


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--container", required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"supabase_db_[a-z0-9-]+", args.container):
        parser.error("Explicit local Supabase container required")
    context = json.loads(subprocess.check_output(["docker", "context", "inspect"], text=True))[0]
    if not context["Endpoints"]["docker"]["Host"].startswith("unix://"):
        parser.error("Local Docker socket required")

    def sql(statement: str) -> str:
        result = run(args.container, statement)
        if result.returncode:
            raise RuntimeError(result.stderr)
        return result.stdout.strip()

    if sql("select inet_server_addr() is null; select count(*) from private.portal_catalog_search_current_v2;") != "t\n0":
        parser.error("Empty local public projection required")
    command = ["docker", "exec", "-i", args.container, "psql", "-U", "postgres", "-d", "postgres", "-Atq", "-v", "ON_ERROR_STOP=1"]
    source = (ROOT / "supabase/tests/20260919_portal_navigation_v1.sql").read_text()
    helper = re.search(r"create function pg_temp.nav_payload.*?\$\$;", source, re.S).group()

    def seed(identity: str, geography: str = "US") -> None:
        sql("begin; grant api_internal_executor to postgres;" + helper + f"""
        insert into private.portal_catalog_search_rows_v1
          (dataset_kind,id,version,state_code,modified_at,card,document,projection_contract_version)
        select 'flow','{identity}','01.00.000',100,now(),p->'card',p->>'document',1
        from (select private.catalog_portal_projection_payload_v1('flow',100,
          pg_temp.nav_payload('Backfill656','{geography}','[{{"@classId":"01"}}]',true)) p) t;
        delete from private.portal_navigation_versions_v1 where id='{identity}';
        revoke api_internal_executor from postgres; commit;
        """)

    backfills = sorted((ROOT / "supabase/migrations").glob("2026091913100*_portal_navigation_backfill.sql"))
    assert len(backfills) == 4
    results = {}
    lock_process = None
    migration = None
    try:
        # Exercise every UUID partition with pre-existing versions, then retry.
        for prefix in ["156de000", "656de000", "a56de000", "e56de000"]:
            seed(prefix + "-0000-4000-8000-000000000002")
        for attempt in range(2):
            for path in backfills:
                sql(path.read_text())
            assert sql("select count(*) from private.portal_navigation_versions_v1") == "4"
            assert sql("select count(*) from private.portal_navigation_membership_v1 where node_id='geo:us' and direct") == "4"
        results["populated_four_shards_and_replay"] = "passed"
        sql("delete from private.portal_catalog_search_rows_v1")
        sql(f"""
        create function private.navigation_backfill_test_barrier() returns trigger language plpgsql as $$
        begin
          if current_setting('application_name')='navigation-backfill-test' then
            perform pg_advisory_xact_lock({LOCK});
          end if;
          return new;
        end $$;
        create trigger navigation_backfill_test_barrier before insert on private.portal_navigation_versions_v1
          for each row execute function private.navigation_backfill_test_barrier();
        """)
        for action in ["withdraw", "update"]:
            seed(IDENTITY)
            lock_process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            lock_process.stdin.write(f"select pg_advisory_lock({LOCK}); select 'barrier-ready';\n")
            lock_process.stdin.flush()
            while lock_process.stdout.readline().strip() != "barrier-ready":
                if lock_process.poll() is not None:
                    raise RuntimeError("Barrier connection closed")
            migration = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            migration.stdin.write("set application_name='navigation-backfill-test';\n" + backfills[1].read_text())
            migration.stdin.close()
            for _ in range(100):
                if sql("select exists(select 1 from pg_stat_activity where application_name='navigation-backfill-test' and wait_event='advisory')") == "t":
                    break
                time.sleep(0.05)
            else:
                raise RuntimeError("Migration did not reach the deterministic barrier")
            if action == "withdraw":
                sql(f"delete from private.portal_catalog_search_rows_v1 where id='{IDENTITY}'")
            else:
                sql(f"update private.portal_catalog_search_rows_v1 set card=jsonb_set(card,'{{geography,code}}','\"CN\"') where id='{IDENTITY}'")
            lock_process.stdin.write(f"select pg_advisory_unlock({LOCK});\n\\q\n")
            lock_process.stdin.flush()
            lock_process.wait(timeout=15)
            lock_process = None
            migration.wait(timeout=20)
            if migration.returncode:
                raise RuntimeError(migration.stderr.read())
            migration = None
            if action == "withdraw":
                assert sql(f"select count(*) from private.portal_navigation_versions_v1 where id='{IDENTITY}'") == "0"
            else:
                assert sql(f"select geography_code from private.portal_navigation_versions_v1 where id='{IDENTITY}'") == "cn"
                assert sql(f"select count(*) from private.portal_navigation_membership_v1 where id='{IDENTITY}' and node_id='geo:cn' and direct") == "1"
            results[f"concurrent_{action}_wins"] = "passed"
            sql(f"delete from private.portal_catalog_search_rows_v1 where id='{IDENTITY}'")
    finally:
        for process in [lock_process, migration]:
            if process and process.poll() is None:
                process.kill()
                process.wait()
        sql("""
        select pg_terminate_backend(pid) from pg_stat_activity where application_name='navigation-backfill-test';
        drop trigger if exists navigation_backfill_test_barrier on private.portal_navigation_versions_v1;
        drop function if exists private.navigation_backfill_test_barrier();
        delete from private.portal_catalog_search_rows_v1 where id::text like '%56de000-%';
        """)
    assert sql("select count(*) from private.portal_catalog_search_current_v2") == "0"
    results["scope"] = "local populated projection-parent upgrade/replay and two-connection races; no hosted or raw-data mutations"
    args.report.write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
