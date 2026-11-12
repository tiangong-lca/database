#!/usr/bin/env python3
"""Prove late-commit and lease fencing against the owned #972 PG17 stack."""

import json
import os
import selectors
import subprocess
import time


CONTAINER = "supabase_db_portal-index-972"
PROJECT = "portal-index-972"
LEFT = "97200000-0000-4000-8000-000000000901"
RIGHT = "97200000-0000-4000-8000-000000000902"
UNSEEN = "97200000-0000-4000-8000-000000000903"
WARM = "97200000-0000-4000-8000-000000000904"
ONLY_UNAVAILABLE = "97200000-0000-4000-8000-000000000905"
CLAIM = """
set local request.jwt.claims = '{"role":"service_role"}';
set local role service_role;
select api.svc_portal_index_claim_v1(
  'indexnow','https://portal.example',array['tiangong_lca'],1
);
"""
PSQL = [
    "docker", "exec", "-i", CONTAINER, "psql", "-XqAt", "-U", "postgres",
    "-d", "postgres", "-v", "ON_ERROR_STOP=1",
]


def sql(statement):
    result = subprocess.run(
        PSQL, input="set statement_timeout='5s';" + statement, text=True,
        capture_output=True, timeout=15
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    return result.stdout.strip()


class Session:
    def __enter__(self):
        self.process = subprocess.Popen(
            PSQL, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
        )
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.run("set statement_timeout='5s';")
        return self

    def run(self, statement):
        marker = b"portal_index_ready"
        self.process.stdin.write(statement.encode() + b"\n\\echo " + marker + b"\n")
        self.process.stdin.flush()
        output = b""
        deadline = time.monotonic() + 10
        while marker not in output:
            if not self.selector.select(max(0, deadline - time.monotonic())):
                raise TimeoutError("SQL session did not reach its barrier")
            chunk = os.read(self.process.stdout.fileno(), 65536)
            if not chunk:
                raise RuntimeError(output.decode())
            output += chunk
        return output.split(marker, 1)[0].decode().strip()

    def __exit__(self, *_error):
        self.selector.close()
        self.process.stdin.close()
        self.process.wait(timeout=10)


def show(dataset_id):
    return f"""
    insert into private.dataset_display_settings(
      dataset_kind,dataset_id,dataset_version,is_visible,brand
    ) values ('flow','{dataset_id}','01.00.000',true,'tiangong_lca')
    on conflict (dataset_kind,dataset_id,dataset_version)
    do update set is_visible=true, brand=excluded.brand;
    """


def hide(dataset_id):
    return f"""
    update private.dataset_display_settings set is_visible=false
    where dataset_kind='flow' and dataset_id='{dataset_id}' and dataset_version='01.00.000';
    """


def settle(work):
    return f"""
    begin;
    set local request.jwt.claims = '{{"role":"service_role"}}';
    set local role service_role;
    select api.svc_portal_index_settle_v1(
      'indexnow','{int(work["eventId"])}','{work["leaseToken"]}',
      'retry','provider_timeout',15,'[]'
    );
    commit;
    """


def main():
    project = subprocess.check_output(
        ["docker", "inspect", "--format", '{{index .Config.Labels "com.supabase.cli.project"}}', CONTAINER],
        text=True, timeout=10,
    ).strip()
    if project != PROJECT:
        raise RuntimeError("the exact owned Supabase project is required")
    port = subprocess.check_output(
        ["docker", "port", CONTAINER, "5432/tcp"], text=True, timeout=10
    ).splitlines()
    if not port or any(not address.endswith(":57422") for address in port):
        raise RuntimeError("the exact owned Supabase database port is required")
    if sql("""
      select private.portal_display_mode_v1() || ':' || coalesce(origin,'unconfigured')
      from private.portal_index_config;
    """) != "legacy:unconfigured":
        raise RuntimeError("the owned database must be a blank migration replay")
    if sql(f"""
      select count(*) from public.flows
      where id in ('{LEFT}','{RIGHT}','{UNSEEN}','{WARM}','{ONLY_UNAVAILABLE}');
    """) != "0":
        raise RuntimeError("fixture identities must be unused")

    try:
        sql(f"""
          begin;
          set local session_replication_role = replica;
          insert into public.flows(id,version,state_code,json)
          values ('{LEFT}','01.00.000',0,'{{"flowDataSet":{{}}}}'),
                 ('{RIGHT}','01.00.000',0,'{{"flowDataSet":{{}}}}'),
                 ('{UNSEEN}','01.00.000',0,'{{"flowDataSet":{{}}}}'),
                 ('{WARM}','01.00.000',0,'{{"flowDataSet":{{}}}}'),
                 ('{ONLY_UNAVAILABLE}','01.00.000',0,'{{"flowDataSet":{{}}}}');
          set local session_replication_role = origin;
          -- Materialize shared navigation nodes before racing independent
          -- dataset writes. The outbox remains disabled during this setup.
          {show(WARM)}
          select private.portal_display_transition_v1('legacy','display');
          select private.portal_index_configure_v1(
            'https://portal.example',array['tiangong_lca'],true,true
          );
          commit;
        """)
        with Session() as slow, Session() as worker:
            slow.run("begin;" + show(LEFT))
            sql(show(RIGHT) + f"""
              update private.portal_index_outbox set available_at = '-infinity'
              where provider='indexnow' and dataset_id='{RIGHT}';
            """)
            first = json.loads(worker.run("begin;" + CLAIM))
            assert len(first) == 1 and first[0]["upserts"][0]["id"] == RIGHT

            slow.run("commit;")
            second = json.loads(sql("begin;" + CLAIM + "commit;"))
            assert len(second) == 1 and second[0]["upserts"][0]["id"] == LEFT
            assert int(second[0]["eventId"]) < int(first[0]["eventId"])
            worker.run("commit;")

        sql(f"""
          update private.portal_index_outbox
          set lease_expires_at=clock_timestamp()-interval '1 second',
              available_at=clock_timestamp()-interval '1 second'
          where event_id={int(first[0]["eventId"])};
        """)
        reclaimed = json.loads(sql("begin;" + CLAIM + "commit;"))
        assert len(reclaimed) == 1 and reclaimed[0]["eventId"] == first[0]["eventId"]
        assert reclaimed[0]["attempt"] == 2 and reclaimed[0]["leaseToken"] != first[0]["leaseToken"]
        assert sql(settle(first[0])) == "f"
        assert sql(settle(reclaimed[0])) == "t"
        assert sql(settle(reclaimed[0])) == "t"
        print("PASS: late lower event was leased, locked peer skipped, obsolete ACK rejected, current ACK replayed")

        # The unavailable interval spans several independently committed writes.
        sql(
            "begin;" + show(UNSEEN)
            + "select private.portal_display_transition_v1('display','unavailable');"
            + hide(UNSEEN) + "commit;"
        )
        sql(hide(LEFT))
        sql(show(ONLY_UNAVAILABLE))
        sql(hide(ONLY_UNAVAILABLE))
        sql(show(UNSEEN))
        assert sql(f"""
          select count(*) from private.portal_index_outbox
          where state='held' and dataset_id='{LEFT}';
        """) == "3"
        sql(
            "begin;select private.portal_display_transition_v1('unavailable','display');"
            + hide(UNSEEN) + "commit;"
        )
        assert sql(f"""
          select count(*) from private.portal_index_outbox
          where dataset_id in ('{UNSEEN}','{ONLY_UNAVAILABLE}');
        """) == "0"
        assert json.loads(sql("begin;" + CLAIM + "commit;")) == []
        assert json.loads(sql("select private.portal_index_reconcile_maintenance_v1(1);")) == {
            "released": 1, "complete": False,
        }
        assert json.loads(sql("select private.portal_index_reconcile_maintenance_v1(100);")) == {
            "released": 2, "complete": True,
        }
        withdrawals = json.loads(sql("begin;" + CLAIM.replace("'indexnow'", "'baidu_withdrawal'") + "commit;"))
        assert len(withdrawals) == 1 and withdrawals[0]["withdrawals"][0]["id"] == LEFT
        print("PASS: committed maintenance changes were held, never-public URL discarded, explicit reconciliation released the withdrawal")
    finally:
        sql("""
          select private.portal_display_transition_v1('unavailable','display')
          where private.portal_display_mode_v1()='unavailable';
        """)
        sql(f"""
          begin;
          select private.portal_index_reconcile_maintenance_v1(1000)
          where (select maintenance_gap from private.portal_index_config);
          select private.portal_index_configure_v1(
            'https://portal.example',array['tiangong_lca'],true,false
          ) where (select capture_enabled from private.portal_index_config);
          update private.portal_index_config set capture_enabled=false, origin=null, allowed_brands=null;
          delete from public.flows where id in ('{LEFT}','{RIGHT}','{UNSEEN}','{WARM}','{ONLY_UNAVAILABLE}');
          delete from private.portal_index_outbox
          where dataset_id in ('{LEFT}','{RIGHT}','{UNSEEN}','{WARM}','{ONLY_UNAVAILABLE}');
          update private.portal_display_rollout set mode='legacy';
          commit;
        """)


if __name__ == "__main__":
    main()
