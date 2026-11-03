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
MIGRATION = "20261102215839_study_task_admission_v1.sql"
PREDECESSOR = "20261102165824"


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
insert into private.studies(id,owner_id,title) values('89499999-0000-4000-8000-000000000004','89499999-0000-4000-8000-000000000001','Persisted predecessor Study');
insert into private.study_members values('89499999-0000-4000-8000-000000000004','89499999-0000-4000-8000-000000000001','owner');
create temp table study894_prior as select
 (select to_jsonb(s) from private.studies s where id='89499999-0000-4000-8000-000000000004') study,
 (select coalesce(jsonb_agg(to_jsonb(m) order by m.oid),'[]'::jsonb) from pg_auth_members m where m.roleid='api_internal_executor'::regrole and m.member='postgres'::regrole) executor_membership,
 has_schema_privilege('api_internal_executor','private','CREATE') executor_create,
 (select to_jsonb(c) from public.contacts c where id='89499999-0000-4000-8000-000000000002') contact,
 (select to_jsonb(j) from private.worker_jobs j where id='89499999-0000-4000-8000-000000000003') job,
 (select jsonb_object_agg(p.oid::text,jsonb_build_object('definition',pg_get_functiondef(p.oid),'acl',p.proacl::text,'owner',p.proowner,'schema',n.nspname,'name',p.proname,'settings',p.proconfig)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private','api','util') and p.prokind='f') functions,
 (select jsonb_object_agg(routine_identity,to_jsonb(g)) from private.api_capability_grants g) manifest;
commit;
"""
    verification = """
create temp table study895_expected_changes(name text primary key);
insert into study895_expected_changes values
 ('private.worker_enqueue_job'),('private.worker_read_job'),('private.worker_cancel_job'),('private.worker_retry_job'),
 ('private.worker_record_job_result'),('private.worker_list_jobs'),('private.worker_read_latest_job'),
 ('private.get_task_summary_v2_feed_unversioned'),('private.study_complete'),('private.study_guard_immutable'),
 ('private.study_read_worker_input'),('api.cmd_study_v1'),('api.qry_study_v1');
select jsonb_build_object(
'datasetPreserved',b.contact=(select to_jsonb(c) from public.contacts c where id='89499999-0000-4000-8000-000000000002'),
'legacyJobPreserved',b.job=(select to_jsonb(j) from private.worker_jobs j where id='89499999-0000-4000-8000-000000000003'),
'persistedStudyPreserved',b.study=(select to_jsonb(s) from private.studies s where id='89499999-0000-4000-8000-000000000004'),
'otherRoutinesPreserved',not exists(
 select 1 from jsonb_each(b.functions) x left join pg_proc p on p.oid=x.key::oid left join pg_namespace n on n.oid=p.pronamespace
 where not exists(select 1 from study895_expected_changes e where e.name=(x.value->>'schema')||'.'||(x.value->>'name'))
 and (p.oid is null or x.value<>jsonb_build_object('definition',pg_get_functiondef(p.oid),'acl',p.proacl::text,'owner',p.proowner,'schema',n.nspname,'name',p.proname,'settings',p.proconfig))),
'changedQueueAuthorityPreserved',not exists(
 select 1 from jsonb_each(b.functions) x left join pg_proc p on p.oid=x.key::oid left join pg_namespace n on n.oid=p.pronamespace
 where exists(select 1 from study895_expected_changes e where e.name=(x.value->>'schema')||'.'||(x.value->>'name')) and x.value->>'schema'='private'
 and (p.oid is null or (x.value-'definition')<>jsonb_build_object('acl',p.proacl::text,'owner',p.proowner,'schema',n.nspname,'name',p.proname,'settings',p.proconfig))),
'exactReviewedChangeInventory',(select array_agg(e.name order by e.name) from study895_expected_changes e)=(
 select array_agg((x.value->>'schema')||'.'||(x.value->>'name') order by (x.value->>'schema')||'.'||(x.value->>'name'))
 from jsonb_each(b.functions) x left join pg_proc p on p.oid=x.key::oid left join pg_namespace n on n.oid=p.pronamespace
 where p.oid is null or x.value<>jsonb_build_object('definition',pg_get_functiondef(p.oid),'acl',p.proacl::text,'owner',p.proowner,'schema',n.nspname,'name',p.proname,'settings',p.proconfig)),
'coreDelegationClosed',to_regprocedure('private.study_cmd_core_v1(jsonb)') is not null and to_regprocedure('private.study_qry_core_v1(jsonb)') is not null
 and not has_function_privilege('authenticated','private.study_cmd_core_v1(jsonb)','EXECUTE')
 and not has_function_privilege('service_role','private.study_qry_core_v1(jsonb)','EXECUTE')
 and has_function_privilege('authenticated','api.cmd_study_v1(jsonb)','EXECUTE') and has_function_privilege('authenticated','api.qry_study_v1(jsonb)','EXECUTE'),
'existingManifestPreserved',b.manifest=(select jsonb_object_agg(g.routine_identity,to_jsonb(g)) from private.api_capability_grants g where b.manifest ? g.routine_identity),
'executorMembershipPreserved',b.executor_membership=(select coalesce(jsonb_agg(to_jsonb(m) order by m.oid),'[]'::jsonb) from pg_auth_members m where m.roleid='api_internal_executor'::regrole and m.member='postgres'::regrole),
'executorCreatePreserved',b.executor_create=has_schema_privilege('api_internal_executor','private','CREATE'),
'noInventedStudy',(select count(*)=1 from private.studies),
'rolloutOff',(select not source_enabled and not compute_enabled and not disclosure_enabled and revision=1 from private.study_runtime_config where singleton)
 and not exists(select 1 from private.study_profiles where enabled)) from study894_prior b;
"""
    output = sql(fixture + migration.decode() + verification)
    receipt = json.loads(next(line for line in output.splitlines() if line.startswith("{")))
    assert receipt and all(value is True for value in receipt.values()), receipt
    reset()
    head = sql("select max(version) from supabase_migrations.schema_migrations;").strip()
    assert head == resolve_migration_head(repo / "supabase/migrations"), head
    assert sql("select count(*) from auth.users where id::text like '89499999-%';").strip() == "0"
    args.report.write_text(json.dumps({"schemaVersion": "lca.study-upgrade-receipt.v1", "project": "study894",
        "predecessor": PREDECESSOR, "candidate": head, "migrationSha256": hashlib.sha256(migration).hexdigest(),
        "selectedUpgradeMigration": MIGRATION,
        "reviewedChangedRoutines": 13,
        "preservation": receipt, "blankLedgerRebuild": True, "syntheticUpgradeFixtureRemovedByOwnedReset": True}, indent=2) + "\n")
    print("Study PG17 populated predecessor preserved; exact candidate blank migration-ledger rebuild passed.")


if __name__ == "__main__":
    main()
