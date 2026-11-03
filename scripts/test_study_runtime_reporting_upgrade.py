#!/usr/bin/env python3
"""Exact owned Study P2 populated predecessor upgrade and blank rebuild proof.

Requires STUDY_RUNTIME_UPGRADE_ALLOW_RESET=isolated and validates the retained
study894 project/ports/ownership, zero accounts/clients/jobs before first reset.
Only that explicitly reserved project is reset; no shared/hosted connection.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from prepare_study_runtime_project import settings
from resolve_migration_head import resolve_migration_head

ROOT = Path(__file__).resolve().parents[1]
CONTAINER = 'supabase_db_study894'
MIGRATIONS = ['20261103110001_study_analysis_reporting_v1.sql','20261103110002_study_report_producer_v1.sql']
PREDECESSOR = '20261103110000'


def sql(statement):
    result = subprocess.run(['docker','exec','-i',CONTAINER,'psql','-X','-qAt','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],input=statement,text=True,capture_output=True,timeout=60)
    if result.returncode:
        raise RuntimeError('owned upgrade SQL failed: '+result.stderr[-2000:])
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workdir',type=Path,required=True)
    parser.add_argument('--report',type=Path,required=True)
    parser.add_argument('--ownership-manifest',type=Path,required=True)
    args = parser.parse_args()
    assert os.environ.get('STUDY_RUNTIME_UPGRADE_ALLOW_RESET') == 'isolated'
    assert not args.report.exists()
    workdir = args.workdir.resolve()
    config = (workdir/'supabase/config.toml').read_text()
    assert workdir.name == 'study894' and settings(config) == ('study894',56422,17)
    assert not re.search(r'^\[remotes\.',config,re.M)
    ownership = json.loads(args.ownership_manifest.read_text())
    assert ownership['project'] == 'study894' and ownership['dbPort'] == 56422
    assert Path(ownership.get('destination', ownership.get('workdir', ''))).resolve() == workdir
    assert ownership.get('sharedProjectTouched', False) is False
    info = json.loads(subprocess.check_output(['docker','inspect',CONTAINER],text=True))[0]
    assert info['Config']['Labels']['com.supabase.cli.project'] == 'study894'
    assert {x['HostPort'] for x in info['HostConfig']['PortBindings']['5432/tcp']} == {'56422'}
    assert sql("select current_setting('server_version_num')::integer/10000;").strip() == '17'
    assert sql("select (select count(*) from auth.users)+(select count(*) from private.oauth_client_registry)+(select count(*) from private.worker_jobs where status in ('queued','running'));").strip() == '0'
    assert sql("select count(*) from pg_stat_activity where datname='postgres' and state='active' and pid<>pg_backend_pid();").strip() == '0'
    cli = os.environ.get('SUPABASE_CLI') or shutil.which('supabase')
    assert cli
    assert subprocess.check_output([cli,'--version'],text=True).strip() == '2.117.0'
    source_migrations = ROOT/'supabase/migrations'
    assert resolve_migration_head(source_migrations) == MIGRATIONS[-1].split('_')[0]
    migration_bytes=[(source_migrations/x).read_bytes() for x in MIGRATIONS]
    for path in source_migrations.glob('*.sql'):
        shutil.copy2(path,workdir/'supabase/migrations'/path.name)
    def reset(version=None):
        command=[cli,'db','reset','--local','--no-seed','--workdir',str(workdir)]
        if version:
            command += ['--version',version]
        result=subprocess.run(command,text=True,capture_output=True,timeout=240)
        log=args.report.with_name(args.report.stem+('-predecessor-reset.log' if version else '-blank-reset.log'))
        log.write_text(result.stdout+result.stderr)
        log.chmod(0o600)
        if result.returncode:
            raise RuntimeError('Owned reset failed; private log '+str(log))
    reset(PREDECESSOR)
    fixture=(ROOT/'supabase/tests/fixtures/study894_runtime_fixture.sql').read_text()
    setup='begin;'+fixture+"""
select pg_temp.study894_claim(null,null,true);
select api.svc_study_model_preparation_complete_v1('89400000-0000-4000-8000-000000000021','89400000-0000-4000-8000-000000000031','89400000-0000-4000-8000-000000000041',pg_temp.study894_complete(),'upgrade904-base');
insert into private.worker_jobs(id,job_kind,worker_queue,requested_by,status,payload_schema_version,payload_json)
values('90499999-0000-4000-8000-000000000003','lca.solve_one','solver','89400000-0000-4000-8000-000000000001','queued','study904.legacy-fixture.v1','{}');
insert into private.oauth_client_registry(client_id,client_kind,enabled) values('study904-upgrade-client','manual',true);
insert into private.oauth_client_capability_grants(client_id,capability_id) values('study904-upgrade-client','STUDY-READ-01');
create temp table study904_prior as select
 (select jsonb_object_agg(t.name,t.rows) from (
  select 'studies' name,jsonb_agg(to_jsonb(s) order by id) rows from private.studies s
  union all select 'members',jsonb_agg(to_jsonb(s) order by study_id,actor_id) from private.study_members s
  union all select 'artifacts',jsonb_agg(to_jsonb(s) order by id) from private.study_artifacts s
  union all select 'preparations',jsonb_agg(to_jsonb(s) order by id) from private.study_model_preparations s
  union all select 'snapshots',jsonb_agg(to_jsonb(s) order by id) from private.study_source_snapshots s
  union all select 'jobs',jsonb_agg(to_jsonb(s) order by id) from private.worker_jobs s
 )t) data,
 (select jsonb_object_agg(p.oid::text,jsonb_build_object('definition',pg_get_functiondef(p.oid),'acl',p.proacl::text,'owner',p.proowner,'schema',n.nspname,'name',p.proname,'settings',p.proconfig)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private','api','util') and p.prokind='f') functions,
 (select jsonb_object_agg(routine_identity,to_jsonb(g)) from private.api_capability_grants g) manifest,
 (select jsonb_agg(to_jsonb(g) order by client_id,capability_id) from private.oauth_client_capability_grants g) clients,
 (select jsonb_agg(to_jsonb(m) order by m.oid) from pg_auth_members m) role_memberships,
 (select jsonb_object_agg(rolname,to_jsonb(rolconfig)) from pg_roles where rolname in ('postgres','anon','authenticated','service_role','api_internal_executor')) role_configuration,
 (select to_jsonb(c) from private.study_runtime_config c where singleton) runtime;
commit;
"""
    verify="""
select jsonb_build_object(
'populatedStudySourceArtifactAndJobRowsPreserved',b.data=(select jsonb_object_agg(t.name,t.rows) from (
 select 'studies' name,jsonb_agg(to_jsonb(s) order by id) rows from private.studies s
 union all select 'members',jsonb_agg(to_jsonb(s) order by study_id,actor_id) from private.study_members s
 union all select 'artifacts',jsonb_agg(to_jsonb(s) order by id) from private.study_artifacts s
 union all select 'preparations',jsonb_agg(to_jsonb(s) order by id) from private.study_model_preparations s
 union all select 'snapshots',jsonb_agg(to_jsonb(s) order by id) from private.study_source_snapshots s
 union all select 'jobs',jsonb_agg(to_jsonb(s) order by id) from private.worker_jobs s)t),
'onlyThreeReviewedServiceRoutinesChanged',(select array_agg((x.value->>'schema')||'.'||(x.value->>'name') order by (x.value->>'schema')||'.'||(x.value->>'name')) from jsonb_each(b.functions)x left join pg_proc p on p.oid=x.key::oid left join pg_namespace n on n.oid=p.pronamespace where p.oid is null or x.value<>jsonb_build_object('definition',pg_get_functiondef(p.oid),'acl',p.proacl::text,'owner',p.proowner,'schema',n.nspname,'name',p.proname,'settings',p.proconfig))=array['api.svc_study_artifact_read_resolve_v1','api.svc_study_task_fail_v1','api.svc_study_task_reconcile_v1'],
'changedRoutineAuthorityPreserved',not exists(select 1 from jsonb_each(b.functions)x left join pg_proc p on p.oid=x.key::oid left join pg_namespace n on n.oid=p.pronamespace where p.proname in ('svc_study_artifact_read_resolve_v1','svc_study_task_fail_v1','svc_study_task_reconcile_v1') and (x.value-'definition')<>jsonb_build_object('acl',p.proacl::text,'owner',p.proowner,'schema',n.nspname,'name',p.proname,'settings',p.proconfig)),
'existingApiManifestPreserved',b.manifest=(select jsonb_object_agg(g.routine_identity,to_jsonb(g)) from private.api_capability_grants g where b.manifest ? g.routine_identity),
'existingClientGrantsUnchanged',b.clients=(select jsonb_agg(to_jsonb(g) order by client_id,capability_id) from private.oauth_client_capability_grants g),
'existingRoleMembershipsUnchanged',b.role_memberships=(select jsonb_agg(to_jsonb(m) order by m.oid) from pg_auth_members m),
'existingRoleTimeoutConfigurationUnchanged',b.role_configuration=(select jsonb_object_agg(rolname,to_jsonb(rolconfig)) from pg_roles where rolname in ('postgres','anon','authenticated','service_role','api_internal_executor')),
'P1RuntimeConfigurationUnchanged',b.runtime=(select to_jsonb(c) from private.study_runtime_config c where singleton),
'allP2ProducerGatesOff',(select not analysis_enabled and not report_enabled and not export_enabled and export_profile is null and revision=1 from private.study_reporting_config where singleton),
'noPhantomAnalysesOrReports',(select count(*)=0 from private.study_analyses) and (select count(*)=0 from private.study_report_revisions) and (select count(*)=0 from private.study_report_exports)) from study904_prior b;
"""
    assert all((source_migrations/name).read_bytes()==data for name,data in zip(MIGRATIONS,migration_bytes)), 'source changed during proof; rerun with stable candidate'
    output=sql(setup+'\n'.join(x.decode() for x in migration_bytes)+verify)
    receipt=json.loads([x for x in output.splitlines() if x.startswith('{')][-1])
    assert receipt and all(x is True for x in receipt.values()),receipt
    assert all((source_migrations/name).read_bytes()==data and (workdir/'supabase/migrations'/name).read_bytes()==data for name,data in zip(MIGRATIONS,migration_bytes)), 'candidate copy/source changed during proof'
    reset()
    head=sql('select max(version) from supabase_migrations.schema_migrations;').strip()
    assert head == resolve_migration_head(source_migrations)
    assert sql("select (select count(*) from auth.users)+(select count(*) from private.oauth_client_registry)+(select count(*) from private.study_analyses)+(select count(*) from private.study_report_revisions);").strip() == '0'
    assert sql('select not source_enabled and not compute_enabled and not disclosure_enabled from private.study_runtime_config where singleton;').strip() == 't'
    assert sql('select not analysis_enabled and not report_enabled and not export_enabled and export_profile is null from private.study_reporting_config where singleton;').strip() == 't'
    args.report.write_text(json.dumps({'schemaVersion':'lca.study-reporting-upgrade-receipt.v1','project':'study894','predecessor':PREDECESSOR,'candidate':head,'migrationHashes':{x:hashlib.sha256(y).hexdigest() for x,y in zip(MIGRATIONS,migration_bytes)},'populatedUpgrade':receipt,'blankLedgerRebuild':True,'allProducerGatesDefaultOff':True,'blankAccountsAndClients':True,'classification':'isolated PG17 SQL/schema upgrade proof; no hosted/runtime/byte qualification'},indent=2)+'\n')
    print('Study P2 populated predecessor upgrade and exact blank migration ledger passed; all producer gates remain off.')

if __name__ == '__main__':
    main()
