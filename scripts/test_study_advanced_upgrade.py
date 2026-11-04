#!/usr/bin/env python3
"""Owned study909 populated-P3 upgrade and exact blank migration-ledger proof."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
from study_advanced_test_support import ROOT, expand, sql, verify_owned

MIGRATION='20261104150000_study_advanced_analysis_v1.sql'
PREDECESSOR='20261103151409'
REVIEWED_CHANGED_ROUTINES=[
 'api.cmd_study_review_v1(jsonb)','api.qry_study_reporting_v1(jsonb)','api.qry_study_review_v1(jsonb)',
 'api.svc_study_artifact_read_resolve_v1(uuid)','api.svc_study_report_intent_consume_v1(uuid,jsonb)',
 'api.svc_study_report_intent_reconcile_v1(uuid,uuid,text)','api.svc_study_report_intent_resolve_v1(uuid)',
 'api.svc_study_review_intent_consume_v1(uuid,jsonb)','api.svc_study_review_intent_resolve_v1(uuid)',
 'api.svc_study_task_fail_v1(text,uuid,uuid,uuid,text,text)','api.svc_study_task_reconcile_v1(text,uuid,uuid,uuid,text,uuid)',
 'private.study_report_command(jsonb)','private.study_report_rights(uuid,jsonb,jsonb,uuid,text)',
 'private.study_reporting_artifact_authorize(uuid,jsonb,uuid,text)','private.study_reporting_list(jsonb)',
]


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--workdir',type=Path,required=True)
    p.add_argument('--report',type=Path,required=True)
    args=p.parse_args()
    assert os.environ.get('STUDY_ADVANCED_ALLOW_RESET')=='owned-study909'
    assert not args.report.exists()
    ownership=verify_owned(args.workdir)
    assert sql("select (select count(*) from auth.users)+(select count(*) from private.oauth_client_registry);")=='0','owner must dispose/reset synthetic fixture before this proof'
    assert sql("select count(*) from pg_stat_activity where datname='postgres' and state='active' and pid<>pg_backend_pid();")=='0'
    cli=os.environ.get('SUPABASE_CLI') or shutil.which('supabase')
    assert cli and subprocess.check_output([cli,'--version'],text=True,stderr=subprocess.DEVNULL).strip()=='2.117.0'
    source=ROOT/'supabase/migrations'
    migrations={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(source.glob('*.sql'))}
    assert MIGRATION in migrations
    candidate=sorted(migrations)[-1].split('_')[0]
    for f in source.glob('*.sql'):shutil.copy2(f,args.workdir/'supabase/migrations'/f.name)
    def reset(version=None):
        cmd=[cli,'db','reset','--local','--no-seed','--workdir',str(args.workdir)]
        if version:cmd+=['--version',version]
        result=subprocess.run(cmd,text=True,capture_output=True,timeout=240)
        log=args.report.with_name(args.report.stem+('-predecessor-reset.log' if version else '-blank-reset.log'))
        log.write_text(result.stdout+result.stderr);log.chmod(0o600)
        assert result.returncode==0,'owned reset failed; inspect private log '+str(log)
    reset(PREDECESSOR)
    fixture=expand(ROOT/'supabase/tests/20261103_study_review_finalization_sharing.sql').replace('select * from finish();','').rsplit('rollback;',1)[0]
    # Retain representative pre-P4 opaque intents so new default family fields
    # are checked as an additive metadata extension, without rewriting old keys.
    fixture+='''
insert into private.study_report_intents(id,study_id,actor_id,operation,request,report_id,grant_epoch,config_revision)
 values('90900000-0000-4000-8000-000000000401','89400000-0000-4000-8000-000000000010','89400000-0000-4000-8000-000000000001','report.create','{"syntheticUpgradeFixture":true}','90900000-0000-4000-8000-000000000499',1,1);
insert into private.study_artifact_read_intents(id,study_id,artifact_id,artifact_ref,actor_id)
 select '90900000-0000-4000-8000-000000000402',study_id,id,ref,'89400000-0000-4000-8000-000000000001' from private.study_artifacts where id='90400000-0000-4000-8000-000000000060';
'''
    before='''
create temp table study909_prior_data(schema_name text,name text,value jsonb,primary key(schema_name,name));
do $$declare t record;v jsonb;begin
 for t in select n.nspname schema_name,c.relname name from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname in('public','api','private','util','archive') and c.relkind in('r','p') and c.relname not in('api_capability_grants','worker_job_kinds') loop
  execute format('select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),''[]''::jsonb) from %I.%I t',t.schema_name,t.name) into v;
  insert into study909_prior_data values(t.schema_name,t.name,v);
 end loop;
end$$;
create temp table study909_prior_functions as select p.oid,pg_get_functiondef(p.oid) def,p.proacl,p.proowner,p.proconfig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('public','api','private','util','archive') and p.prokind='f';
create temp table study909_prior_manifest as select * from private.api_capability_grants;
create temp table study909_prior_job_kinds as select * from private.worker_job_kinds;
create temp table study909_prior_auth as select to_jsonb(u) value from auth.users u;
'''
    after="""
create temp table study909_upgraded_data(schema_name text,name text,value jsonb,primary key(schema_name,name));
do $$declare t record;v jsonb;projection text;begin
 for t in select schema_name,name from study909_prior_data loop
  projection:=case when t.schema_name='private' and t.name in ('study_report_intents','study_artifact_read_intents') then 'to_jsonb(t)-''family''' else 'to_jsonb(t)' end;
  execute format('select coalesce(jsonb_agg(%s order by (%s)::text),''[]''::jsonb) from %I.%I t',projection,projection,t.schema_name,t.name) into v;
  insert into study909_upgraded_data values(t.schema_name,t.name,v);
 end loop;
end$$;
select jsonb_build_object(
 'allPriorApplicationTableValuesPreserved',not exists(select 1 from study909_prior_data p full join study909_upgraded_data a using(schema_name,name) where p.value is distinct from a.value),
 'applicationTableCount',(select count(*) from study909_prior_data),
 'oldOpaqueIntentsDefaultToLegacy',(select bool_and(family='legacy') from private.study_report_intents) and(select bool_and(family='legacy') from private.study_artifact_read_intents),
 'allAuthFixtureValuesPreserved',(select coalesce(jsonb_agg(value order by value::text),'[]'::jsonb) from study909_prior_auth)=(select coalesce(jsonb_agg(to_jsonb(u) order by to_jsonb(u)::text),'[]'::jsonb) from auth.users u),
 'changedRoutineIdentities',(select jsonb_agg(format('%I.%I(%s)',n.nspname,p.proname,replace(pg_catalog.oidvectortypes(p.proargtypes),' ','')) order by n.nspname,p.proname) from study909_prior_functions b left join pg_proc p on p.oid=b.oid left join pg_namespace n on n.oid=p.pronamespace where p.oid is null or b.def<>pg_get_functiondef(p.oid)),
 'allPriorRoutineAclOwnerAndSettingsUnchanged',not exists(select 1 from study909_prior_functions b left join pg_proc p on p.oid=b.oid where p.oid is null or b.proacl is distinct from p.proacl or b.proowner<>p.proowner or b.proconfig is distinct from p.proconfig),
 'existingManifestPreserved',not exists(select 1 from study909_prior_manifest b left join private.api_capability_grants a using(routine_identity) where to_jsonb(b) is distinct from to_jsonb(a)),
 'manifestAdditionsAreExactlySeventeen',(select count(*) from private.api_capability_grants)=(select count(*)+17 from study909_prior_manifest),
 'existingJobKindsPreserved',not exists(select 1 from study909_prior_job_kinds b left join private.worker_job_kinds a using(job_kind) where to_jsonb(b) is distinct from to_jsonb(a)),
 'onlyAdvancedJobKindAdded',(select count(*) from private.worker_job_kinds)=(select count(*)+1 from study909_prior_job_kinds) and exists(select 1 from private.worker_job_kinds where job_kind='study.analysis_advanced' and payload_schema_version='study.analysis_advanced.request.v1'),
 'newAnalysisGatesDefaultOff',(select revision=1 and not sensitivity_enabled and not uncertainty_enabled and not report_enabled and max_parameters is null and max_samples is null from private.study_advanced_config),
 'newReviewGateDefaultOff',(select revision=1 and not enabled and not export_enabled and export_profile is null from private.study_advanced_review_config),
 'noPhantomAdvancedRecords',(select count(*)=0 from private.study_advanced_analyses) and(select count(*)=0 from private.study_report_advanced_analyses) and(select count(*)=0 from private.study_advanced_parameter_intents));
"""
    migration_sql=(source/MIGRATION).read_text().replace('begin;','',1).rsplit('commit;',1)[0]
    output=sql(fixture+before+migration_sql+after+'rollback;')
    assert 'not ok' not in output,'predecessor P3 seed failed'
    proof=json.loads([line for line in output.splitlines() if line.startswith('{')][-1])
    changed=proof.pop('changedRoutineIdentities');table_count=proof.pop('applicationTableCount')
    assert sorted(changed)==sorted(REVIEWED_CHANGED_ROUTINES),(changed,REVIEWED_CHANGED_ROUTINES)
    assert all(v is True for v in proof.values()),proof
    reset()
    assert sql('select max(version) from supabase_migrations.schema_migrations;')==candidate
    assert sql("select (select count(*) from auth.users)+(select count(*) from private.oauth_client_registry)+(select count(*) from private.study_advanced_analyses);")=='0'
    for expression in [
        'not source_enabled and not compute_enabled and not disclosure_enabled from private.study_runtime_config',
        'not analysis_enabled and not report_enabled and not export_enabled and export_profile is null from private.study_reporting_config',
        'not enabled from private.study_review_config',
        'not sensitivity_enabled and not uncertainty_enabled and not report_enabled and max_parameters is null and max_samples is null from private.study_advanced_config',
        'not enabled and not export_enabled and export_profile is null from private.study_advanced_review_config',
    ]:assert sql('select '+expression+';')=='t'
    assert migrations=={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in source.glob('*.sql')}
    args.report.write_text(json.dumps({'schemaVersion':'lca.study-advanced-upgrade-receipt.v1','project':'study909','predecessor':PREDECESSOR,'candidate':candidate,
        'migrationHashes':migrations,'populatedP3Upgrade':proof,'populatedApplicationTableCount':table_count,'reviewedChangedRoutineIdentities':changed,'blankMigrationLedgerRebuild':True,
        'allP1P2P3P4GatesDefaultOff':True,'accountsAndClientsEmpty':True,'resourceOwnership':ownership,'classification':'owned PG17 SQL proof; no hosted, actual bytes or UI qualification'},indent=2)+'\n')
    print(f'Study909 populated P3 upgrade preserved {table_count} tables; exact fifteen routine changes, ACLs/owners/settings and prior authority preserved. Blank ledger gates off.')


if __name__=='__main__':
    main()
