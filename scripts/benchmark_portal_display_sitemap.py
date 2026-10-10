#!/usr/bin/env python3
"""Rollback-only exact-response sitemap comparison on the owned #807 local stack.

Synthetic source rows and matching narrow projections test the actual predecessor
source scan and candidate read. No production rows, credentials or planner forcing.
The predecessor diagnostic budget is 60s; the candidate keeps its original 8s.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CONTAINER = 'supabase_db_portal-display-807-1010'
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--container', required=True, choices=[CONTAINER])
p.add_argument('--report', required=True, type=Path)
args = p.parse_args()
collector = Path(__file__).read_bytes()
assert not args.report.exists(), 'Report must be new'
assert 'tiangong-lca/database#807' in Path('/private/tmp/lca-portal-807-20261010/ownership.txt').read_text()
context = json.loads(subprocess.check_output(['docker', 'context', 'inspect'], text=True))[0]
assert context['Endpoints']['docker']['Host'].startswith('unix://'), 'Local Docker only'

def run(source):
    return subprocess.run(['docker', 'exec', '-i', CONTAINER, 'psql', '-U', 'postgres', '-d', 'postgres', '-Atq', '-v', 'ON_ERROR_STOP=1'], input=source, text=True, capture_output=True, timeout=600)

check = run('select inet_server_addr() is null; select count(*) from private.display_catalog_search_rows_v1;')
assert check.returncode == 0 and check.stdout.strip().splitlines() == ['t', '0'], 'Empty local fixture required'
original = (ROOT/'supabase/migrations/20261010110000_portal_display_projection.sql').read_text()
a = original.index('CREATE OR REPLACE FUNCTION "private"."display_api_sitemap_entries_v1"(')
b = original.index('create function api.portal_sitemap_entries_v2', a)
baseline = original[a:b]
candidate_path = ROOT/'supabase/migrations/20261010154811_optimize_portal_display_sitemap_page.sql'
candidate = '\n'.join(x for x in candidate_path.read_text().splitlines() if x not in ['begin;', 'commit;'])
seed = (ROOT/'supabase/tests/20261010_portal_display_readers.sql').read_text().split('select is((select count(*)::integer from private.display_catalog_search_rows_v2)')[0]
seed += '''
create temp table saved_triggers as select tgrelid::regclass::text rel,tgname,tgenabled from pg_trigger where not tgisinternal and (tgrelid in ('public.processes'::regclass,'public.flows'::regclass,'private.dataset_display_settings'::regclass) or tgrelid in(select c.oid from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='private' and c.relname like 'display_%' and c.relkind='r'));
do $$declare r record;begin for r in select distinct rel from saved_triggers loop execute format('alter table %s disable trigger user',r.rel);end loop;end$$;
create temp table source_models as select 'process' kind,json from public.processes where version='01.00.000' union all select 'flow',json from public.flows;
create temp table models as select distinct on(dataset_kind) * from private.display_catalog_search_rows_v1 order by dataset_kind,id;
'''
for kind, table, n, prefix in [('process', 'processes', 20000, '887a0000'), ('flow', 'flows', 120000, '887b0000')]:
    seed += f"""
insert into public.{table}(id,version,state_code,modified_at,json) select ('{prefix}-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'01.00.000',0,'2026-10-10',m.json from generate_series(1,{n}) i cross join lateral (select json from source_models where kind='{kind}' limit 1) m;
insert into private.display_catalog_search_rows_v1 select '{kind}',r.id,r.version::text,r.state_code,r.modified_at,m.card,m.document,1,case when right(r.id::text,1) in ('0','1','2','3','4','5','6') then 'tiangong_lca' when right(r.id::text,1)='7' then 'bafu' when right(r.id::text,1)='8' then 'uslci' else 'worldsteel' end from public.{table} r cross join models m where m.dataset_kind='{kind}' and r.id::text like '{prefix}%';
"""
seed += '''
insert into private.dataset_display_settings(dataset_kind,dataset_id,dataset_version,is_visible,brand) select dataset_kind,id,version,true,brand from private.display_catalog_search_rows_v1 where id::text like '887%';
insert into private.display_catalog_facet_rows_v1(dataset_kind,id,version,state_code,modified_at,facet_access_level,facet_geography,facet_reference_year,facet_process_subtype,facet_source,facet_contract_version) select dataset_kind,id,version,state_code,modified_at,card->>'accessLevel',lower(btrim(card#>>'{geography,code}')),card->>'referenceYear',lower(btrim(card->>'processSubtype')),lower(btrim(card->>'source')),1 from private.display_catalog_search_rows_v1 where id::text like '887%';
insert into private.display_sitemap_rows_v1 select dataset_kind,id,version,modified_at,get_byte(decode(md5(dataset_kind||':'||id::text),'hex'),0)/4,1 from private.display_catalog_search_rows_v1 where id::text like '887%';
do $$declare r record;begin for r in select * from saved_triggers loop execute format('alter table %s %s trigger %I',r.rel,case r.tgenabled when 'D' then 'disable' when 'A' then 'enable always' when 'R' then 'enable replica' else 'enable' end,r.tgname);end loop;end$$;
analyze public.processes;analyze public.flows;analyze private.dataset_display_settings;analyze private.display_sitemap_rows_v1;
create temp table results(phase text,scope text,kind text,seconds numeric,value jsonb);
create function pg_temp.probe(phase text,scope text,kind text) returns void language plpgsql as $$declare started timestamptz;v jsonb;begin
 perform set_config('portal.display_brands',scope,true);perform set_config('portal.display_global',case when scope='global' then 'true' else 'false' end,true);perform set_config('portal.display_filter_brand','',true);
 started:=clock_timestamp();v:=private.display_api_sitemap_entries_v1(kind,null,1000);insert into results values(phase,scope,kind,extract(epoch from clock_timestamp()-started),v);
end$$;
grant all on results to portal_display_executor;
grant execute on function pg_temp.probe(text,text,text) to portal_display_executor;
'''
for phase, definition in [('baseline', baseline), ('candidate', candidate)]:
    seed += definition + "\nupdate private.portal_display_contract_manifest set identity=private.portal_display_contract_identity_v1();\n"
    seed += "set local statement_timeout='60s';\n" if phase == 'baseline' else "set local statement_timeout='8s';\n"
    seed += 'set local role portal_display_executor;\n'
    for scope in ['bafu', 'tiangong_lca', 'uslci', 'worldsteel', 'bafu,tiangong_lca,uslci,worldsteel', 'global']:
        for kind in ['process', 'flow', 'all']:
            seed += f"select pg_temp.probe('{phase}','{scope}','{kind}');\n"
    seed += "reset role;set local statement_timeout='60s';\n"
seed += "select jsonb_build_object('phase',phase,'scope',scope,'kind',kind,'seconds',seconds,'digest',md5(value::text)) from results;rollback;"
result = run(seed)
assert result.returncode == 0, result.stderr[-2500:]
rows = [json.loads(x) for x in result.stdout.splitlines() if x.startswith('{')]
assert len(rows) == 36
for scope in {r['scope'] for r in rows}:
    for kind in ['process', 'flow', 'all']:
        group = [r for r in rows if r['scope'] == scope and r['kind'] == kind]
        assert len({r['digest'] for r in group}) == 1, (scope, kind, 'response drift')
assert max(r['seconds'] for r in rows if r['phase'] == 'candidate') < 8
check = run('select count(*) from private.display_catalog_search_rows_v1;select private.portal_display_assert_contract_v1();')
assert check.returncode == 0 and check.stdout.strip() == '0'
assert Path(__file__).read_bytes() == collector
report = {'passed': True, 'synthetic_versions': 140000, 'collector_sha256': hashlib.sha256(collector).hexdigest(), 'migration_sha256': hashlib.sha256(candidate_path.read_bytes()).hexdigest(), 'samples_per_shape': 1, 'local_read_scale_only': True, 'rows': rows}
args.report.write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps({'passed': True, 'shapes': 18, 'candidate_max_seconds': max(r['seconds'] for r in rows if r['phase']=='candidate')}))
