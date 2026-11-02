#!/usr/bin/env python3
"""Exact task-owned PG17 predecessor upgrade and blank-ledger rebuild proof.

Requires STUDY_RUNTIME_UPGRADE_ALLOW_RESET=isolated and the verified study894
project/port. Refuses every shared/hosted target. Only that disposable project's
database is reset; its resource cleanup remains the caller's responsibility.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import re
from prepare_study_runtime_project import settings
from resolve_migration_head import resolve_migration_head

CONTAINER = "supabase_db_study894"
MIGRATION = "20261102165824_study_durable_runtime_v1.sql"
PREDECESSOR = "20261102091416"


def sql(statement):
    result = subprocess.run(["docker", "exec", "-i", CONTAINER, "psql", "-X", "-qAt",
        "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1"], input=statement,
        text=True, capture_output=True, timeout=45)
    if result.returncode:
        raise RuntimeError("isolated upgrade SQL failed: " + result.stderr[-2000:])
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workdir", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    assert os.environ.get("STUDY_RUNTIME_UPGRADE_ALLOW_RESET") == "isolated", "explicit isolated-reset attestation required"
    assert not args.report.exists(), "report must be new"
    workdir = args.workdir.resolve()
    config = (workdir / "supabase/config.toml").read_text()
    assert workdir.name == "study894" and settings(config) == ("study894",56422,17)
    assert not re.search(r'^\[remotes\.',config,re.M)
    info = json.loads(subprocess.check_output(["docker", "inspect", CONTAINER], text=True))[0]
    assert info["Config"]["Labels"].get("com.supabase.cli.project") == "study894"
    assert {x["HostPort"] for x in info["HostConfig"]["PortBindings"]["5432/tcp"]} == {"56422"}
    repo = Path(__file__).resolve().parents[1]
    migration = (repo / "supabase/migrations" / MIGRATION).read_bytes()
    target = workdir / "supabase/migrations" / MIGRATION
    target.write_bytes(migration)
    cli = ["supabase"] if shutil.which("supabase") else ["npx", "--yes", "supabase@2.117.0"]
    version = subprocess.run(cli + ["--version"], text=True, capture_output=True, check=True, timeout=30).stdout.strip()
    assert version == "2.117.0", "use repository-pinned Supabase2.117.0"

    def reset(version=None):
        command = cli + ["db", "reset", "--local", "--no-seed", "--workdir", str(workdir)]
        if version:
            command += ["--version", version]
        result = subprocess.run(command, text=True, capture_output=True, timeout=180)
        if result.returncode:
            raise RuntimeError("owned local reset failed; inspect the isolated project without widening its target")

    reset(PREDECESSOR)
    fixture = """
begin;
insert into auth.users(id,instance_id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('89499999-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','study894-upgrade@invalid.test','{}','{}',now(),now());
insert into private.users(id,raw_user_meta_data,contact) values('89499999-0000-4000-8000-000000000001','{}',null) on conflict(id) do nothing;
insert into public.contacts(id,version,state_code,user_id,json,json_ordered)
values('89499999-0000-4000-8000-000000000002','01.00.000',0,'89499999-0000-4000-8000-000000000001',
'{"contactDataSet":{"contactInformation":{"dataSetInformation":{"common:UUID":"89499999-0000-4000-8000-000000000002"}},"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.00.000"}}}}',
'{"contactDataSet":{"contactInformation":{"dataSetInformation":{"common:UUID":"89499999-0000-4000-8000-000000000002"}},"administrativeInformation":{"publicationAndOwnership":{"common:dataSetVersion":"01.00.000"}}}}');
insert into private.worker_jobs(id,job_kind,worker_queue,requested_by,status,payload_schema_version,payload_json)
values('89499999-0000-4000-8000-000000000003','lca.solve_one','solver','89499999-0000-4000-8000-000000000001','queued','study894.legacy-fixture.v1','{}');
create temp table study894_prior as select
 (select to_jsonb(c) from public.contacts c where id='89499999-0000-4000-8000-000000000002') contact,
 (select to_jsonb(j) from private.worker_jobs j where id='89499999-0000-4000-8000-000000000003') job,
 (select jsonb_object_agg(p.oid::text,jsonb_build_object('definition',pg_get_functiondef(p.oid),'acl',p.proacl::text,'owner',p.proowner)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private','api','util') and p.prokind='f') functions,
 (select jsonb_object_agg(routine_identity,to_jsonb(g)) from private.api_capability_grants g) manifest;
commit;
"""
    verification = """
select jsonb_build_object('datasetPreserved',b.contact=(select to_jsonb(c) from public.contacts c where id='89499999-0000-4000-8000-000000000002'),
'legacyJobPreserved',b.job=(select to_jsonb(j) from private.worker_jobs j where id='89499999-0000-4000-8000-000000000003'),
'existingRoutinesPreserved',b.functions=(select jsonb_object_agg(p.oid::text,jsonb_build_object('definition',pg_get_functiondef(p.oid),'acl',p.proacl::text,'owner',p.proowner)) from pg_proc p where b.functions ? p.oid::text),
'existingManifestPreserved',b.manifest=(select jsonb_object_agg(g.routine_identity,to_jsonb(g)) from private.api_capability_grants g where b.manifest ? g.routine_identity),
'noInventedStudy',not exists(select 1 from private.studies),
'noActivatedProfile',not exists(select 1 from private.study_profiles)) from study894_prior b;
"""
    output = sql(fixture + migration.decode() + verification)
    receipt = json.loads(next(line for line in output.splitlines() if line.startswith("{")))
    assert all(receipt.values()), receipt
    reset()
    head = sql("select max(version) from supabase_migrations.schema_migrations;").strip()
    assert head == resolve_migration_head(repo / "supabase/migrations"), head
    assert sql("select count(*) from auth.users where id::text like '89499999-%';").strip() == "0"
    args.report.write_text(json.dumps({"schemaVersion": "lca.study-upgrade-receipt.v1", "project": "study894",
        "predecessor": PREDECESSOR, "candidate": head, "migrationSha256": hashlib.sha256(migration).hexdigest(),
        "selectedUpgradeMigration": MIGRATION,
        "preservation": receipt, "blankLedgerRebuild": True, "syntheticUpgradeFixtureRemovedByOwnedReset": True}, indent=2) + "\n")
    print("Study PG17 populated predecessor preserved; exact candidate blank migration-ledger rebuild passed.")


if __name__ == "__main__":
    main()
