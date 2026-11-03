#!/usr/bin/env python3
"""Owned study906 populated-P2 additive upgrade and exact blank-ledger proof."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
from study_review_test_support import ROOT, expand, sql, verify_owned

MIGRATION='20261103151409_study_review_finalization_sharing_v1.sql'
PREDECESSOR='20261103110002'


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--workdir',type=Path,required=True)
    p.add_argument('--report',type=Path,required=True)
    args=p.parse_args()
    assert os.environ.get('STUDY_REVIEW_ALLOW_RESET')=='owned-study906'
    assert not args.report.exists()
    ownership=verify_owned(args.workdir)
    assert sql("select (select count(*) from auth.users)+(select count(*) from private.oauth_client_registry);")=='0','owned fixture must be empty before reset'
    assert sql("select count(*) from pg_stat_activity where datname='postgres' and state='active' and pid<>pg_backend_pid();")=='0'
    cli=os.environ.get('SUPABASE_CLI') or shutil.which('supabase')
    assert cli and subprocess.check_output([cli,'--version'],text=True).strip()=='2.117.0'
    source=ROOT/'supabase/migrations'
    migrations={x.name:hashlib.sha256(x.read_bytes()).hexdigest() for x in sorted(source.glob('*.sql'))}
    assert MIGRATION in migrations
    candidate=sorted(migrations)[-1].split('_')[0]
    for f in source.glob('*.sql'):
        shutil.copy2(f,args.workdir/'supabase/migrations'/f.name)
    def reset(version=None):
        cmd=[cli,'db','reset','--local','--no-seed','--workdir',str(args.workdir)]
        if version:cmd+=['--version',version]
        r=subprocess.run(cmd,text=True,capture_output=True,timeout=240)
        log=args.report.with_name(args.report.stem+('-p2-reset.log' if version else '-blank-reset.log'))
        log.write_text(r.stdout+r.stderr);log.chmod(0o600)
        assert r.returncode==0,'owned reset failed; inspect private log '+str(log)
    reset(PREDECESSOR)
    fixture=expand(ROOT/'supabase/tests/fixtures/study906_review_fixture.sql').split('create function pg_temp.req(',1)[0]
    before="""
create temp table study906_prior_data(name text primary key,value jsonb);
do $$declare t record;v jsonb;begin
 for t in select tablename from pg_tables where schemaname='private' and(tablename like 'study_%' or tablename in('worker_jobs','oauth_client_registry','oauth_client_capability_grants')) loop
  execute format('select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),''[]''::jsonb) from private.%I t',t.tablename) into v;
  insert into study906_prior_data values(t.tablename,v);
 end loop;
end$$;
create temp table study906_prior_functions as select p.oid,pg_get_functiondef(p.oid) def,p.proacl,p.proowner,p.proconfig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('public','api','private','util','archive') and p.prokind='f';
create temp table study906_prior_manifest as select * from private.api_capability_grants;
"""
    after="""
create temp table study906_upgraded_data(name text primary key,value jsonb);
do $$declare t record;v jsonb;begin
 for t in select name from study906_prior_data loop
  execute format('select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),''[]''::jsonb) from private.%I t',t.name) into v;
  insert into study906_upgraded_data values(t.name,v);
 end loop;
end$$;
select jsonb_build_object(
 'allPopulatedP2RowsPreserved',not exists(select 1 from study906_prior_data p full join study906_upgraded_data a using(name) where p.value is distinct from a.value),
 'onlyReviewedLegacyListDefinitionChanged',(select array_agg(p.oid::regprocedure::text order by p.oid::regprocedure::text) from study906_prior_functions b left join pg_proc p on p.oid=b.oid where p.oid is null or b.def<>pg_get_functiondef(p.oid))=array['private.study_qry_core_v1(jsonb)'],
 'legacyListDeltaIsExactRoleFilter',(select pg_get_functiondef(b.oid)=replace(b.def,'where m.actor_id=actor and private.study_team_member(actor,s.team_id) and (after_id is null or s.id>after_id)','where m.actor_id=actor and m.role in (''owner'',''editor'',''viewer'') and private.study_team_member(actor,s.team_id) and (after_id is null or s.id>after_id)') from study906_prior_functions b where b.oid='private.study_qry_core_v1(jsonb)'::regprocedure),
 'allPriorRoutineAclOwnerAndSettingsUnchanged',not exists(select 1 from study906_prior_functions b left join pg_proc p on p.oid=b.oid where p.oid is null or b.proacl is distinct from p.proacl or b.proowner<>p.proowner or b.proconfig is distinct from p.proconfig),
 'existingManifestPreserved',not exists(select 1 from study906_prior_manifest b left join private.api_capability_grants a using(routine_identity) where to_jsonb(b) is distinct from to_jsonb(a)),
 'newRuntimeDefaultOff',(select not enabled and revision=1 from private.study_review_config),
 'noPhantomFinalizationOrShare',(select count(*)=0 from private.study_report_finalizations) and(select count(*)=0 from private.study_report_shares));
"""
    output=sql('begin;'+fixture+before+(source/MIGRATION).read_text().replace('begin;','',1).rsplit('commit;',1)[0]+after+'rollback;')
    proof=json.loads([x for x in output.splitlines() if x.startswith('{')][-1])
    assert all(x is True for x in proof.values()),proof
    reset()
    assert sql('select max(version) from supabase_migrations.schema_migrations;')==candidate
    assert sql("select (select count(*) from auth.users)+(select count(*) from private.oauth_client_registry)+(select count(*) from private.study_report_finalizations);")=='0'
    assert sql('select not source_enabled and not compute_enabled and not disclosure_enabled from private.study_runtime_config;')=='t'
    assert sql('select not analysis_enabled and not report_enabled and not export_enabled and export_profile is null from private.study_reporting_config;')=='t'
    assert sql('select not enabled from private.study_review_config;')=='t'
    assert migrations=={x.name:hashlib.sha256(x.read_bytes()).hexdigest() for x in source.glob('*.sql')}
    args.report.write_text(json.dumps({'schemaVersion':'lca.study-review-upgrade-receipt.v1','project':'study906','predecessor':PREDECESSOR,'candidate':candidate,
      'migrationHashes':migrations,'populatedP2Upgrade':proof,'blankMigrationLedgerRebuild':True,'allP1P2P3GatesDefaultOff':True,'accountsAndClientsEmpty':True,
      'resourceOwnership':ownership,'classification':'owned PG17 SQL proof; no hosted, actual-byte or UI qualification'},indent=2)+'\n')
    print('Study906 populated P2 upgrade preserved every prior row/authority/manifest; only the exact legacy-list role filter changed, with unchanged ACL/owner/settings. Blank ledger gates remain off.')


if __name__=='__main__':main()
