#!/usr/bin/env python3
"""Rollback-only populated predecessor upgrade on the owned #818 local stack."""
import argparse
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CONTAINER = 'supabase_db_portal-no-license-818'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--container', required=True, choices=[CONTAINER])
parser.add_argument('--rows', type=int, default=1000, choices=[1000, 140000])
parser.add_argument('--report', required=True, type=Path)
args = parser.parse_args()
if args.report.exists():
    parser.error('Report must be a new file')
owner = Path('/private/tmp/lca-portal-818-20261011/OWNER.md').read_text()
if 'tiangong-lca/database#818' not in owner:
    parser.error('Explicit task ownership is required')
context = json.loads(subprocess.check_output(['docker', 'context', 'inspect'], text=True))[0]
if not context['Endpoints']['docker']['Host'].startswith('unix://'):
    parser.error('Only local Docker is admitted')

def run(sql):
    return subprocess.run(['docker', 'exec', '-i', CONTAINER, 'psql', '-U', 'postgres',
                           '-d', 'postgres', '-Atq', '-v', 'ON_ERROR_STOP=1'],
                          input=sql, text=True, capture_output=True, timeout=900)

check = run('select inet_server_addr() is null; select count(*) from private.display_catalog_search_rows_v1;')
if check.returncode or check.stdout.strip().splitlines() != ['t', '0']:
    parser.error('Refusing non-local or nonempty database')
original = (ROOT/'supabase/migrations/20261010110000_portal_display_projection.sql').read_text()
predecessor = ''
for name in ['display_capabilities_v1', 'display_support_capabilities_v1', 'display_api_list_process_exchanges_v1']:
    pattern = rf'CREATE OR REPLACE FUNCTION "private"\."{name}"[\s\S]*?(?=\nALTER FUNCTION)'
    predecessor += re.findall(pattern, original)[-1] + '\n'
fixture = (ROOT/'supabase/tests/20261010_portal_display_readers.sql').read_text().split('select is((select count(*)::integer from private.display_catalog_search_rows_v2)')[0]
fixture = fixture.replace('begin;', '', 1)
migration = (ROOT/'supabase/migrations/20261010171202_portal_display_without_license_gates.sql').read_text()
migration = re.sub(r'^(begin;|commit;)$', '', migration, flags=re.M)
sql = 'begin;\n' + predecessor + "update private.portal_display_contract_manifest set identity=private.portal_display_contract_identity_v1();\n" + fixture
sql += """
update public.processes set json=jsonb_set(json,'{processDataSet,administrativeInformation,publicationAndOwnership,common:licenseType}','"Other"')
where id='80700000-0000-4000-8000-000000000101' and version='01.00.000';
insert into public.processes(id,version,state_code,json)
select ('81800000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'01.00.000',0,
 jsonb_set(pg_temp.portal_versions_process_payload('Upgrade process '||i,'01.00.000'),
 '{processDataSet,administrativeInformation,publicationAndOwnership,common:licenseType}','"Other"')
from generate_series(1,1000) i;
insert into private.dataset_display_settings(dataset_kind,dataset_id,dataset_version,is_visible,brand)
select 'process',id,version,true,'tiangong_lca' from public.processes where id::text like '81800000%';
create temp table saved_sources as select id,version,to_jsonb(p) value from public.processes p;
create temp table saved_settings as select to_jsonb(s) value from private.dataset_display_settings s;
create temp table saved_cards as select 'v1' generation,dataset_kind,id,version,card-'capabilities'-'accessLevel' card,document,modified_at,brand,state_code from private.display_catalog_search_rows_v1
union all select 'v2',dataset_kind,id,version,card-'capabilities'-'accessLevel',document,modified_at,brand,state_code from private.display_catalog_search_rows_v2;
create temp table saved_children as
select 'character1' relation,to_jsonb(r) value from private.display_catalog_character_rows_v1 r
union all select 'character2',to_jsonb(r) from private.display_catalog_character_rows_v2 r
union all select 'membership',to_jsonb(r) from private.display_navigation_membership_v1 r
union all select 'sitemap',to_jsonb(r) from private.display_sitemap_rows_v1 r
union all select 'facet',to_jsonb(r)-'facet_access_level' from private.display_catalog_facet_rows_v1 r
union all select 'navigation',to_jsonb(r)-'access_level' from private.display_navigation_versions_v1 r;
create temp table saved_routines as select p.oid,pg_get_functiondef(p.oid) definition,p.proowner,p.proacl
from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('api','private') and p.proname not like 'display_%';
create temp table saved_acl as select p.oid,p.proowner,p.proacl from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname like 'display_%';
create temp table proof_time as select clock_timestamp() started;
do $$begin
 if (select count(*) from private.display_catalog_search_rows_v2 where card->>'accessLevel'='metadata_only')<>1001 then
  raise exception 'fixture did not reproduce restricted predecessor cards'; end if;
end$$;
"""
# An error after function replacement must not leak partial policy changes.
fault = migration.split('-- Policy-only rewrite')[0]
sql += "savepoint failed_upgrade;\n\\set ON_ERROR_STOP off\n" + fault
sql += "do $$begin raise exception 'injected upgrade failure';end$$;\nrollback to failed_upgrade;\n\\set ON_ERROR_STOP on\n"
sql += "do $$begin if private.display_capabilities_v1('process',0,'{}')->>'exchangesVisible' <> 'false' then raise exception 'failed upgrade leaked policy';end if;end$$;\nselect private.portal_display_assert_contract_v1();\n"
sql += migration
sql += """
create temp table proof_duration as select extract(epoch from clock_timestamp()-started) seconds from proof_time;
do $$begin
 if exists((select id,version,to_jsonb(p) from public.processes p except select * from saved_sources)
 union all (select * from saved_sources except select id,version,to_jsonb(p) from public.processes p)) then raise exception 'source mutation'; end if;
 if exists((select to_jsonb(s) from private.dataset_display_settings s except select * from saved_settings)
 union all (select * from saved_settings except select to_jsonb(s) from private.dataset_display_settings s)) then raise exception 'setting mutation'; end if;
 if exists(with current_children as (
select 'character1' relation,to_jsonb(r) value from private.display_catalog_character_rows_v1 r
union all select 'character2',to_jsonb(r) from private.display_catalog_character_rows_v2 r
union all select 'membership',to_jsonb(r) from private.display_navigation_membership_v1 r
union all select 'sitemap',to_jsonb(r) from private.display_sitemap_rows_v1 r
union all select 'facet',to_jsonb(r)-'facet_access_level' from private.display_catalog_facet_rows_v1 r
union all select 'navigation',to_jsonb(r)-'access_level' from private.display_navigation_versions_v1 r)
(select * from current_children except select * from saved_children) union all (select * from saved_children except select * from current_children)) then raise exception 'non-policy child drift'; end if;
 if exists(select 1 from saved_routines s join pg_proc p using(oid) where s.definition is distinct from pg_get_functiondef(p.oid) or s.proowner<>p.proowner or s.proacl is distinct from p.proacl) then raise exception 'legacy or API routine mutation'; end if;
 if exists(select 1 from saved_acl s join pg_proc p using(oid) where s.proowner<>p.proowner or s.proacl is distinct from p.proacl) then raise exception 'display ACL mutation'; end if;
 if exists(with current_cards as (
 select 'v1' generation,dataset_kind,id,version,card-'capabilities'-'accessLevel' card,document,modified_at,brand,state_code from private.display_catalog_search_rows_v1
 union all select 'v2',dataset_kind,id,version,card-'capabilities'-'accessLevel',document,modified_at,brand,state_code from private.display_catalog_search_rows_v2)
 (select * from current_cards except select * from saved_cards) union all (select * from saved_cards except select * from current_cards)) then raise exception 'non-policy card drift'; end if;
end$$;
update private.portal_display_rollout set mode='display';
set local role anon;
select is(api.portal_search_processes_v4(array['tiangong_lca'],'80700000-0000-4000-8000-000000000101')#>>'{items,0,capabilities,exchangesVisible}','true','populated upgrade serves new stored capability');
select is(jsonb_array_length(api.portal_search_processes_v4(array['tiangong_lca'],'','{"accessLevel":"metadata_only"}')->'items'),0,'old license facet cannot retain restricted subset');
reset role;
create temp table retry_cards as select to_jsonb(r) value from private.display_catalog_search_rows_v1 r;
"""
sql += migration
sql += """
do $$begin
 if exists((select to_jsonb(r) from private.display_catalog_search_rows_v1 r except select * from retry_cards)
 union all (select * from retry_cards except select to_jsonb(r) from private.display_catalog_search_rows_v1 r)) then raise exception 'retry changes stored cards'; end if;
end$$;
select jsonb_build_object('status','passed','process_rows',1003,'flow_rows',1,'first_upgrade_seconds',seconds,
 'unchanged_source_settings',true,'unchanged_non_policy_cards',true,'unchanged_non_policy_children',true,'unchanged_legacy_and_acl',true,'retry_idempotent',true,'injected_failure_rollback',true) from proof_duration;
rollback;
"""
# Capacity fixtures clone a consistent exact-key template; no legacy/source writer
# throughput claim. Replica mode avoids per-row FK preparation overhead; the cloned
# navigation closure is checked set-wise. Every trigger is restored before migration.
if args.rows > 1000:
    start = sql.index('insert into public.processes(id,version,state_code,json)\nselect')
    end = sql.index('create temp table saved_sources as', start)
    tables = ['display_catalog_search_rows_v1', 'display_catalog_search_rows_v2',
              'display_catalog_facet_rows_v1', 'display_catalog_character_rows_v1',
              'display_catalog_character_rows_v2', 'display_navigation_versions_v1',
              'display_navigation_membership_v1', 'display_sitemap_rows_v1']
    prep = "set constraints all immediate;\nset local session_replication_role=replica;\nalter table public.processes disable trigger portal_display_source_sync;\n"
    prep += "alter table private.dataset_display_settings disable trigger portal_display_projection_sync;\n"
    for table in tables:
        prep += f"alter table private.{table} disable trigger user;\n"
    prep += """
insert into public.processes(id,version,state_code,json)
select ('81800000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'01.00.000',0,p.json
from generate_series(1,140000) i cross join public.processes p
where p.id='80700000-0000-4000-8000-000000000101' and p.version='01.00.000';
insert into private.dataset_display_settings(dataset_kind,dataset_id,dataset_version,is_visible,brand)
select 'process',id,version,true,'tiangong_lca' from public.processes where id::text like '81800000%';
"""
    for table in tables:
        prep += f"""
do $seed$ declare columns_sql text; select_sql text; begin
 select string_agg(format('%I',attname),',' order by attnum),string_agg(format('x.%I',attname),',' order by attnum)
 into columns_sql,select_sql from pg_attribute
 where attrelid='private.{table}'::regclass and attnum>0 and not attisdropped and attgenerated='';
 execute format($query$insert into private.{table} (%s) select %s
 from private.{table} t cross join public.processes p
 cross join lateral jsonb_populate_record(null::private.{table},to_jsonb(t)||jsonb_build_object('id',p.id)) x
 where t.dataset_kind='process' and t.id='80700000-0000-4000-8000-000000000101' and t.version='01.00.000'
 and p.id::text like '81800000%%'$query$,columns_sql,select_sql);
end $seed$;
"""
    for table in tables:
        prep += f"alter table private.{table} enable trigger user;\n"
    prep += "alter table public.processes enable trigger portal_display_source_sync;\n"
    prep += "alter table private.dataset_display_settings enable trigger portal_display_projection_sync;\n"
    prep += "set local session_replication_role=origin;\n"
    for table in tables:
        prep += f"analyze private.{table};\n"
    prep += "analyze public.processes;\nanalyze private.dataset_display_settings;\n"
    prep += """
do $$ begin
 if exists(select 1 from private.display_navigation_membership_v1 m
 left join private.display_navigation_versions_v1 v using(dataset_kind,id,version)
 left join private.portal_navigation_node_v1 n using(node_id)
 where v.id is null or n.node_id is null) then raise exception 'capacity fixture has orphan navigation'; end if;
end $$;
"""
    sql = sql[:start] + prep + sql[end:]
sql = sql.replace('generate_series(1,1000)', f'generate_series(1,{args.rows})').replace('<>1001', f'<>{args.rows+1}').replace("'process_rows',1003", f"'process_rows',{args.rows+3}")
result = run(sql)
if result.returncode or re.search(r'\bnot ok\b', result.stdout):
    raise RuntimeError((result.stdout+result.stderr)[-5000:])
rows = [json.loads(line) for line in result.stdout.splitlines() if line.startswith('{')]
if len(rows) != 1:
    raise RuntimeError('Missing upgrade receipt')
check = run('select count(*) from private.display_catalog_search_rows_v1; select private.portal_display_assert_contract_v1();')
if check.returncode or check.stdout.strip() != '0':
    raise RuntimeError('Rollback or candidate manifest failed')
rows[0]['rollback_verified'] = True
args.report.write_text(json.dumps(rows[0], indent=2)+'\n')
print(json.dumps(rows[0]))
