#!/usr/bin/env python3
"""Rollback-only Database #807 display scope/summary performance comparison.

Requires the explicit task-owned local stack and an empty projection. Synthetic
read-scale fixtures do not qualify source writers or hosted latency. No remote
credentials, raw production rows or forced planner switches. Candidate calls use
the unchanged two-second summary budget; baseline diagnosis is bounded at 60s.
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'supabase/migrations/20261010110000_portal_display_projection.sql'
CANDIDATE=ROOT/'supabase/migrations/20261010132915_optimize_portal_display_scope_reads.sql'
CONTAINER='supabase_db_portal-display-807-1010'
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--container',required=True,choices=[CONTAINER])
p.add_argument('--report',required=True,type=Path)
p.add_argument('--samples',type=int,default=3,choices=range(1,6))
args=p.parse_args()
collector_bytes=Path(__file__).read_bytes()
if args.report.exists():p.error('Report path must be new')
owner=Path('/private/tmp/lca-portal-807-20261010/ownership.txt').read_text()
if 'tiangong-lca/database#807' not in owner:p.error('Explicit task ownership required')
context=json.loads(subprocess.check_output(['docker','context','inspect'],text=True))[0]
if not context['Endpoints']['docker']['Host'].startswith('unix://'):p.error('Only local Unix socket Docker is admitted')
def run(source):
 return subprocess.run(['docker','exec','-i',CONTAINER,'psql','-U','postgres','-d','postgres','-Atq','-v','ON_ERROR_STOP=1'],input=source,text=True,capture_output=True,timeout=600)
check=run('select inet_server_addr() is null; select count(*) from private.display_catalog_search_rows_v1;')
if check.returncode or check.stdout.strip().splitlines()!=['t','0']:p.error('Refusing non-local or nonempty database')
seed=(ROOT/'supabase/tests/20261010_portal_display_readers.sql').read_text().split('select is((select count(*)::integer from private.display_catalog_search_rows_v2)')[0]
seed+='''
create temp table saved_triggers as select tgrelid::regclass::text rel,tgname,tgenabled from pg_trigger where not tgisinternal and (tgrelid='private.dataset_display_settings'::regclass or tgrelid in(select c.oid from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='private' and c.relname like 'display_%' and c.relkind='r'));
do $$declare r record;begin for r in select distinct rel from saved_triggers loop execute format('alter table %s disable trigger user',r.rel);end loop;end$$;
create temp table models as select distinct on(dataset_kind) * from private.display_catalog_search_rows_v1 order by dataset_kind,id;
create temp table models_v2 as select * from private.display_catalog_search_rows_v2 limit 1;
'''
for kind,n,prefix in [('process',20000,'887a0000'),('flow',120000,'887b0000')]:
 seed+=f"""
insert into private.display_catalog_search_rows_v1 select '{kind}',('{prefix}-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'01.00.000',0,'2026-10-10',m.card,m.document,1,case when i%10<7 then 'tiangong_lca' when i%10=7 then 'bafu' when i%10=8 then 'uslci' else 'worldsteel' end from generate_series(1,{n}) i cross join models m where m.dataset_kind='{kind}';
"""
seed+='''
insert into private.display_catalog_search_rows_v2 select r.dataset_kind,r.id,r.version,r.state_code,r.modified_at,m.card,m.document,2,r.brand from private.display_catalog_search_rows_v1 r cross join models_v2 m where r.dataset_kind='process' and r.id::text like '887a%';
insert into private.dataset_display_settings(dataset_kind,dataset_id,dataset_version,is_visible,brand) select dataset_kind,id,version,true,brand from private.display_catalog_search_rows_v1 where id::text like '887%';
insert into private.display_catalog_facet_rows_v1(dataset_kind,id,version,state_code,modified_at,facet_access_level,facet_geography,facet_reference_year,facet_process_subtype,facet_source,facet_contract_version) select dataset_kind,id,version,state_code,modified_at,card->>'accessLevel',lower(btrim(card#>>'{geography,code}')),card->>'referenceYear',lower(btrim(card->>'processSubtype')),lower(btrim(card->>'source')),1 from private.display_catalog_search_rows_v1 where id::text like '887%';
do $$declare r record;begin for r in select * from saved_triggers loop execute format('alter table %s %s trigger %I',r.rel,case r.tgenabled when 'D' then 'disable' when 'A' then 'enable always' when 'R' then 'enable replica' else 'enable' end,r.tgname);end loop;end$$;
analyze private.dataset_display_settings; analyze private.display_catalog_search_rows_v1; analyze private.display_catalog_search_rows_v2; analyze private.display_catalog_facet_rows_v1;
set local statement_timeout='60s';
create temp table results(phase text,scope text,probe text,seconds numeric,value jsonb);
create function pg_temp.probe(phase text,scope text,probe text,q text) returns void language plpgsql as $$declare started timestamptz;v jsonb;begin
 perform set_config('portal.display_brands',scope,true);perform set_config('portal.display_global','false',true);perform set_config('portal.display_filter_brand','',true);
 started:=clock_timestamp();execute q into v;insert into results values(phase,scope,probe,extract(epoch from clock_timestamp()-started),v);
end$$;
grant all on results to portal_display_executor;
grant execute on function pg_temp.probe(text,text,text,text) to portal_display_executor;
'''

original=BASE.read_text()
a=original.index('CREATE OR REPLACE FUNCTION "private"."display_api_catalog_summary_v1"()')
b=original.index('create function api.portal_catalog_summary_v2',a)
baseline=original[a:b]
for table in ['display_catalog_search_rows_v1','display_catalog_search_rows_v2','display_catalog_facet_rows_v1','display_catalog_character_rows_v1','display_catalog_character_rows_v2','display_navigation_versions_v1','display_navigation_membership_v1','display_sitemap_rows_v1']:
 baseline+=f'alter policy display_scope on private.{table} using (private.portal_display_request_visible_v1(dataset_kind,id,version));\n'
baseline+='update private.portal_display_contract_manifest set identity=private.portal_display_contract_identity_v1();\n'
candidate='\n'.join(line for line in CANDIDATE.read_text().splitlines() if line not in ['begin;','commit;']).replace('create view private.display_request_visible_settings_v1','create or replace view private.display_request_visible_settings_v1')
# Alternate both directions on the identical fixture, including real RLS principals.
for sample in range(args.samples):
 for phase in (['baseline','candidate'] if sample%2==0 else ['candidate','baseline']):
  seed+=baseline if phase=='baseline' else candidate
  seed+="set local statement_timeout='60s';\n" if phase=='baseline' else "set local statement_timeout='2s';\n"
  seed+='set local role portal_display_executor;\n'
  for scope in ['bafu','tiangong_lca','uslci','worldsteel','bafu,tiangong_lca,uslci,worldsteel']:
   for probe,q in [('facet_count','select to_jsonb(count(*)) from private.display_catalog_facet_rows_v1'),('summary','select private.display_api_catalog_summary_v1()')]:
    seed+=f"select pg_temp.probe('{phase}','{scope}','{probe}','{q}');\n"
  seed+='reset role;set local statement_timeout=\'60s\';\n'
seed+="select jsonb_build_object('phase',phase,'scope',scope,'probe',probe,'seconds',seconds,'digest',md5(value::text)) from results;rollback;"
result=run(seed)
if result.returncode:
 raise RuntimeError(result.stderr[-3000:])
rows=[json.loads(line) for line in result.stdout.splitlines() if line.startswith('{')]
assert len(rows)==args.samples*2*5*2
for scope in {r['scope'] for r in rows}:
 for probe in ['facet_count','summary']:
  group=[r for r in rows if r['scope']==scope and r['probe']==probe]
  assert len({r['digest'] for r in group})==1,(scope,probe,'response drift')
  assert max(r['seconds'] for r in group if r['phase']=='candidate')<2,(scope,probe,'budget')
check=run('select count(*) from private.display_catalog_search_rows_v1; select private.portal_display_assert_contract_v1();')
assert check.returncode==0 and check.stdout.strip()=='0','Rollback cleanup or contract failed'
assert Path(__file__).read_bytes()==collector_bytes,'Collector changed during qualification'
report={'passed':True,'fixture_versions':140000,'samples':args.samples,'rows':rows,'candidate_sha256':hashlib.sha256(CANDIDATE.read_bytes()).hexdigest(),'collector_sha256':hashlib.sha256(collector_bytes).hexdigest(),'baseline_sha256':hashlib.sha256(BASE.read_bytes()).hexdigest(),'cleanup':'empty projection; contract passes'}
args.report.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'passed':True,'samples':args.samples,'candidate_max_s':max(r['seconds'] for r in rows if r['phase']=='candidate'),'report':str(args.report)}))
