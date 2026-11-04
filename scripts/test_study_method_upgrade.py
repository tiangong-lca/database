#!/usr/bin/env python3
"""Owned study912 populated-V5 upgrade and exact blank migration-ledger proof.

Resets only the verified task project under an explicit admission variable.
Preserves data, Auth, prior routine ACL/owner/settings and capability inventory.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
from study_method_test_support import ROOT,expand,sql,verify_owned

MIGRATION='20261104191012_study_method_assessment_v1.sql'
PREDECESSOR='20261104150000'
REVIEWED_CHANGED_ROUTINES=[
    'api.svc_study_artifact_read_resolve_v1(uuid)',
    'api.svc_study_task_fail_v1(text,uuid,uuid,uuid,text,text)',
    'api.svc_study_task_reconcile_v1(text,uuid,uuid,uuid,text,uuid)',
    'private.study_review_disclosure(uuid)',
]


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--workdir',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args()
    assert os.environ.get('STUDY_METHOD_ALLOW_RESET')=='owned-study912'
    assert not a.report.exists();ownership=verify_owned(a.workdir)
    assert sql("select(select count(*)from auth.users)+(select count(*)from private.oauth_client_registry);")=='0','dispose the owned synthetic namespace explicitly before upgrade proof'
    assert sql("select count(*)from pg_stat_activity where datname='postgres'and state='active'and pid<>pg_backend_pid();")=='0'
    cli=os.environ.get('SUPABASE_CLI')or shutil.which('supabase');assert cli and subprocess.check_output([cli,'--version'],text=True,stderr=subprocess.DEVNULL).strip()=='2.117.0'
    source=ROOT/'supabase/migrations';migrations={f.name:hashlib.sha256(f.read_bytes()).hexdigest()for f in sorted(source.glob('*.sql'))};assert sorted(migrations)[-1]==MIGRATION
    for f in source.glob('*.sql'):shutil.copy2(f,a.workdir/'supabase/migrations'/f.name)
    def reset(version=None):
        cmd=[cli,'db','reset','--local','--no-seed','--workdir',str(a.workdir)]
        if version:cmd+=['--version',version]
        result=subprocess.run(cmd,text=True,capture_output=True,timeout=300);log=a.report.with_name(a.report.stem+('-predecessor-reset.private.log'if version else'-blank-reset.private.log'));log.write_text(result.stdout+result.stderr);log.chmod(0o600);assert result.returncode==0,'owned reset failed; private log retained'
    reset(PREDECESSOR)
    fixture=expand(ROOT/'supabase/tests/20261104_study_advanced_analysis.sql').replace('select * from finish();','').rsplit('rollback;',1)[0]
    before='''
create temp table study912_prior_data(schema_name text,name text,value jsonb,primary key(schema_name,name));
do $$declare t record;v jsonb;begin
 for t in select n.nspname schema_name,c.relname name from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname in('public','api','private','util','archive')and c.relkind in('r','p')and c.relname not in('api_capability_grants','worker_job_kinds')loop
  execute format('select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text),''[]''::jsonb)from %I.%I t',t.schema_name,t.name)into v;
  insert into study912_prior_data values(t.schema_name,t.name,v);
 end loop;end$$;
create temp table study912_prior_functions as select p.oid,pg_get_functiondef(p.oid)def,p.proacl,p.proowner,p.proconfig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('public','api','private','util','archive')and p.prokind='f';
create temp table study912_prior_manifest as select *from private.api_capability_grants;
create temp table study912_prior_jobs as select *from private.worker_job_kinds;
create temp table study912_prior_auth as select to_jsonb(u)value from auth.users u;
'''
    after="""
create temp table study912_upgraded_data(schema_name text,name text,value jsonb,primary key(schema_name,name));
do $$declare t record;v jsonb;projection text;begin
 for t in select schema_name,name from study912_prior_data loop
  projection:=case when t.schema_name='private'and t.name='study_report_revisions'then 'to_jsonb(t)-''method_assessment_ids'''else 'to_jsonb(t)'end;
  execute format('select coalesce(jsonb_agg(%s order by(%s)::text),''[]''::jsonb)from %I.%I t',projection,projection,t.schema_name,t.name)into v;
  insert into study912_upgraded_data values(t.schema_name,t.name,v);
 end loop;end$$;
select jsonb_build_object(
 'allPriorTableValuesPreserved',not exists(select 1 from study912_prior_data p full join study912_upgraded_data a using(schema_name,name)where p.value is distinct from a.value),
 'priorApplicationTables',(select count(*)from study912_prior_data),
 'allOldReportMethodSelectionsEmpty',(select bool_and(method_assessment_ids='[]'::jsonb)from private.study_report_revisions),
 'allPriorAuthValuesPreserved',(select coalesce(jsonb_agg(value order by value::text),'[]'::jsonb)from study912_prior_auth)=(select coalesce(jsonb_agg(to_jsonb(u)order by to_jsonb(u)::text),'[]'::jsonb)from auth.users u),
 'changedRoutineIdentities',(select jsonb_agg(format('%I.%I(%s)',n.nspname,p.proname,replace(pg_catalog.oidvectortypes(p.proargtypes),' ',''))order by n.nspname,p.proname)from study912_prior_functions b left join pg_proc p on p.oid=b.oid left join pg_namespace n on n.oid=p.pronamespace where p.oid is null or b.def<>pg_get_functiondef(p.oid)),
 'allPriorRoutineAclOwnerSettingsPreserved',not exists(select 1 from study912_prior_functions b left join pg_proc p on p.oid=b.oid where p.oid is null or b.proacl is distinct from p.proacl or b.proowner<>p.proowner or b.proconfig is distinct from p.proconfig),
 'oldManifestPreserved',not exists(select 1 from study912_prior_manifest b left join private.api_capability_grants a using(routine_identity)where to_jsonb(b)is distinct from to_jsonb(a)),
 'nineteenManifestEntriesAdded',(select count(*)from private.api_capability_grants)=(select count(*)+19 from study912_prior_manifest),
 'oldJobKindsPreserved',not exists(select 1 from study912_prior_jobs b left join private.worker_job_kinds a using(job_kind)where to_jsonb(b)is distinct from to_jsonb(a)),
 'oneExplicitMethodJobKindAdded',(select count(*)from private.worker_job_kinds)=(select count(*)+1 from study912_prior_jobs)and exists(select 1 from private.worker_job_kinds where job_kind='study.method_assessment'and payload_schema_version='study.method_assessment.request.v1'and worker_runtime='calculator'and worker_queue='solver'),
 'methodDefaultsOff',(select revision=1 and not execution_enabled and not report_enabled and max_evidence_refs is null and max_selected_factor_records is null and qualification_evidence_ref is null from private.study_method_config),
 'methodReviewDefaultsOff',(select revision=1 and not enabled and not export_enabled and export_profile is null and qualification_evidence_ref is null from private.study_method_review_config),
 'noPhantomMethodRows',(select count(*)=0 from private.study_method_assessments)and(select count(*)=0 from private.study_method_evidence)and(select count(*)=0 from private.study_method_evidence_intents)and(select count(*)=0 from private.study_report_method_assessments));
"""
    migration=(source/MIGRATION).read_text().replace('begin;','',1).rsplit('commit;',1)[0];out=sql(fixture+before+migration+after+'rollback;',timeout=120);assert'not ok'not in out,'populated V5 fixture failed';proof=next(json.loads(x)for x in out.splitlines()if x.startswith('{')and'allPriorTableValuesPreserved'in x);changed=proof.pop('changedRoutineIdentities');count=proof.pop('priorApplicationTables');assert sorted(changed)==sorted(REVIEWED_CHANGED_ROUTINES),(changed,REVIEWED_CHANGED_ROUTINES);assert all(x is True for x in proof.values()),proof
    reset();assert sql('select max(version)from supabase_migrations.schema_migrations;')==MIGRATION.split('_')[0];assert sql("select(select count(*)from auth.users)+(select count(*)from private.oauth_client_registry)+(select count(*)from private.study_method_assessments)+(select count(*)from private.study_method_evidence);")=='0'
    for expression in['not source_enabled and not compute_enabled and not disclosure_enabled from private.study_runtime_config','not analysis_enabled and not report_enabled and not export_enabled and export_profile is null from private.study_reporting_config','not enabled from private.study_review_config','not sensitivity_enabled and not uncertainty_enabled and not report_enabled from private.study_advanced_config','not enabled and not export_enabled and export_profile is null from private.study_advanced_review_config','not execution_enabled and not report_enabled and max_evidence_refs is null and max_selected_factor_records is null from private.study_method_config','not enabled and not export_enabled and export_profile is null from private.study_method_review_config']:
        assert sql('select '+expression+';')=='t',expression
    a.report.write_text(json.dumps({'schemaVersion':'lca.study-method-upgrade-receipt.v1','project':'study912','passed':True,'predecessor':PREDECESSOR,'candidateMigration':MIGRATION,'migrationSha256':migrations[MIGRATION],'populatedPriorTables':count,'reviewedChangedRoutines':changed,'checks':proof,'blankLedgerExact':True,'allPriorAndNewGatesDefaultOff':True,'ownershipSha256':hashlib.sha256((a.workdir/'ownership.json').read_bytes()).hexdigest(),'classification':'owned populated SQL upgrade and blank rebuild; no native,Storage-byte,scientific or hosted qualification','disposition':'owned project blank and retained for source/race/HTTP/generation qualification'},indent=2)+'\n');print(json.dumps({'passed':True,'priorTablesPreserved':count,'reviewedChangedRoutines':len(changed),'blankLedgerExact':True}))


if __name__=='__main__':main()
