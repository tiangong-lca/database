#!/usr/bin/env python3
"""Compare real predecessor/candidate Portal readers on one rollback-only local fixture.

This uses no hosted URL, credentials, production data, optimizer hints or timeout
increase. The temporary derivation shortcut is for read-scale measurement only;
real writer maintenance and public boundaries are exercised by the SQL suites.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CANDIDATE = ROOT / 'supabase/migrations/20260926050042_portal_catalog_bounded_v3.sql'
SOURCES = {
    'portal_navigation_matched_versions_v1': '20260919140000_portal_navigation_rpc.sql',
    'catalog_portal_search_v3_impl': '20260919150000_portal_search_facets_v3.sql',
    'catalog_portal_facets_v3_impl': '20260919150000_portal_search_facets_v3.sql',
    'portal_navigation_impl_v1': '20260919140000_portal_navigation_rpc.sql',
}


def sql_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def definitions(candidate: bool, candidate_text: str) -> str:
    result = []
    for name, filename in SOURCES.items():
        text = candidate_text if candidate else (ROOT / 'supabase/migrations' / filename).read_text()
        pattern = rf'^create(?: or replace)? function\s+"?private"?\."?{name}"?\s*\(.*?\bAS\s+(\$[a-zA-Z_0-9]*\$).*?\1\s*;'
        found = re.search(pattern, text, re.I | re.M | re.S)
        if not found:
            raise ValueError(f'Missing reviewed definition: {name}')
        result.append(re.sub(r'^create(?: or replace)? function', 'create or replace function', found.group(), count=1, flags=re.I))
    return '\n'.join(result)


def run(container: str, sql: str, timeout: int = 1200) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ['docker', 'exec', '-i', container, 'psql', '-h', '/var/run/postgresql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-Atq'],
        input=sql, text=True, capture_output=True, timeout=timeout,
    )


def fixture(processes: int, flows: int, padding: int) -> str:
    sql = r'''
begin;
set local statement_timeout='10min';
set local work_mem='12MB';
grant portal_public_executor,api_internal_executor to postgres;
grant create on schema private to portal_public_executor;
create function pg_temp.payload(n text,g text,c text,f boolean) returns jsonb language sql immutable as $$
select jsonb_build_object(case when f then 'flowDataSet' else 'processDataSet' end,jsonb_build_object(
case when f then 'flowInformation' else 'processInformation' end,jsonb_build_object(
 'dataSetInformation',jsonb_build_object('name',jsonb_build_object('baseName',n),
 'classificationInformation',jsonb_build_object('common:classification',jsonb_build_object('common:class',jsonb_build_object('@classId',c)))),
 'time',jsonb_build_object('common:referenceYear','2024'),
 'geography',jsonb_build_object(case when f then 'locationOfSupply' else 'locationOfOperationSupplyOrProduction' end,jsonb_build_object('@location',g))),
 'administrativeInformation',jsonb_build_object('publicationAndOwnership',jsonb_build_object('common:licenseType','Free of charge for all users and uses'))))
$$;
create temp table original_triggers as select tgrelid::regclass::text as relation,tgname,tgenabled
from pg_trigger where not tgisinternal and tgrelid in (
 'public.processes'::regclass,'public.flows'::regclass,
 'private.portal_catalog_search_rows_v1'::regclass,'private.portal_catalog_search_rows_v2'::regclass,
 'private.portal_catalog_facet_rows_v1'::regclass);
alter table public.processes disable trigger user;
alter table public.flows disable trigger user;
alter table private.portal_catalog_search_rows_v1 disable trigger user;
alter table private.portal_catalog_search_rows_v2 disable trigger user;
alter table private.portal_catalog_facet_rows_v1 disable trigger user;
create temp table templates as select k,st,g,
 private.catalog_portal_projection_payload_v1(k,st,pg_temp.payload('Bench'||initcap(k),g,case when k='process' then '0111' else '17100' end,k='flow')) as old,
 case when k='process' then private.catalog_portal_projection_payload_cn1(k,st,pg_temp.payload('BenchProcess',g,'0111',false)) end as current
from unnest(array['process','flow']) k cross join unnest(array[100,200]) st cross join unnest(array['CN','CN-AH-HFE']) g;
'''
    for kind, count, prefix in [('process', processes, '723be000'), ('flow', flows, '723bf000')]:
        for revision in ([1, 2] if kind == 'process' else [1]):
            payload = 'current' if revision == 2 else 'old'
            sql += f'''
insert into private.portal_catalog_search_rows_v{revision}(dataset_kind,id,version,state_code,modified_at,card,document,projection_contract_version)
select '{kind}',('{prefix}-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'01.00.00'||v,
case when v=0 then 100 else 200 end,'2026-09-19'::timestamptz-i*interval '1 second'+v*interval '1 millisecond',
(t.{payload}->'card') || jsonb_build_object(
 'document','bench{kind} '||lpad(i::text,8,'0'),
 'names',jsonb_build_array(jsonb_build_object('language','en','value','Bench{kind.title()} '||lpad(i::text,8,'0'))),
 'summary',jsonb_build_array(jsonb_build_object('language','en','value',substr((select string_agg(md5(i::text||':'||s::text),'') from generate_series(1,{max(1, (padding + 31) // 32)}) s),1,{padding})))),
'bench{kind} '||lpad(i::text,8,'0'),{revision}
from generate_series(1,{count}) i cross join generate_series(0,1) v
join templates t on t.k='{kind}' and t.st=case when v=0 then 100 else 200 end and t.g=case when i%2=0 then 'CN-AH-HFE' else 'CN' end;
'''
        table = 'processes' if kind == 'process' else 'flows'
        sql += f'''
insert into public.{table}(id,version,json,state_code,modified_at)
select ('{prefix}-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'01.00.00'||v,
pg_temp.payload('Bench{kind.title()} '||lpad(i::text,8,'0'),case when i%2=0 then 'CN-AH-HFE' else 'CN' end,'{'0111' if kind == 'process' else '17100'}',{'false' if kind == 'process' else 'true'}),
case when v=0 then 100 else 200 end,'2026-09-19'::timestamptz-i*interval '1 second'+v*interval '1 millisecond'
from generate_series(1,{min(count,1000)}) i cross join generate_series(0,1) v;
'''
    sql += r'''
insert into private.portal_catalog_facet_rows_v1(dataset_kind,id,version,state_code,modified_at,facet_access_level,facet_geography,facet_reference_year,facet_process_subtype,facet_source,facet_contract_version)
select dataset_kind,id,version,state_code,modified_at,card->>'accessLevel',lower(btrim(card#>>'{geography,code}')),card->>'referenceYear',lower(btrim(card->>'processSubtype')),lower(btrim(card->>'source')),1 from private.portal_catalog_search_rows_v1;
insert into private.portal_navigation_versions_v1(dataset_kind,id,version,access_level,geography_code,classification_codes,reference_year,process_subtype,source)
select dataset_kind,id,version,card->>'accessLevel',lower(btrim(card#>>'{geography,code}')),
array(select distinct lower(btrim(c->>'code')) from jsonb_array_elements(card->'classifications') c),
(card->>'referenceYear')::integer,lower(btrim(card->>'processSubtype')),lower(btrim(card->>'source'))
from private.portal_catalog_search_current_v2;
with recursive placements as (
 select v.dataset_kind,v.id,v.version,n.node_id,n.parent_node_id,n.dimension,true as direct
 from private.portal_navigation_versions_v1 v join private.portal_navigation_node_v1 n on
  (n.dimension='geography' and n.node_id='geo:'||v.geography_code)
  or (n.dimension='classification' and n.taxonomy=case when v.dataset_kind='process' then 'isic' else 'cpc' end and lower(n.code)=any(v.classification_codes))
 union all
 select p.dataset_kind,p.id,p.version,n.node_id,n.parent_node_id,n.dimension,false
 from placements p join private.portal_navigation_node_v1 n on n.node_id=p.parent_node_id
) insert into private.portal_navigation_membership_v1(dataset_kind,id,version,node_id,dimension,direct)
select dataset_kind,id,version,node_id,dimension,bool_or(direct) from placements group by dataset_kind,id,version,node_id,dimension;
do $$ declare t record; begin for t in select * from original_triggers loop
 execute format('alter table %s %s trigger %I',t.relation,case t.tgenabled when 'D' then 'disable' when 'A' then 'enable always' when 'R' then 'enable replica' else 'enable' end,t.tgname);
end loop; end $$;
set constraints all immediate;
analyze private.portal_catalog_search_rows_v1;
analyze private.portal_catalog_search_rows_v2;
analyze private.portal_catalog_facet_rows_v1;
analyze private.portal_navigation_versions_v1;
analyze private.portal_navigation_membership_v1;
create temp table measurements(variant text,label text,ordinal integer,elapsed_ms numeric,payload jsonb,error text);
create temp table plans(variant text,label text,payload jsonb,error text);
grant select,insert on measurements,plans to portal_public_executor;
set local role portal_public_executor;
create function pg_temp.measure(v text,l text,i integer,s text) returns void language plpgsql as $$
declare started timestamptz:=clock_timestamp(); result jsonb;
begin
 begin execute s into result;
 insert into measurements values(v,l,i,extract(epoch from clock_timestamp()-started)*1000,result,null);
 exception when others then insert into measurements values(v,l,i,extract(epoch from clock_timestamp()-started)*1000,null,sqlstate); end;
end $$;
create function pg_temp.capture_plan(v text,l text,s text) returns void language plpgsql as $$
declare result jsonb; begin
 begin execute 'explain (analyze,buffers,timing off,format json) '||s into result;
 insert into plans values(v,l,result,null);
 exception when others then insert into plans values(v,l,null,sqlstate); end;
end $$;
set local statement_timeout='8s';
'''
    return sql


def cases() -> dict[str, str]:
    result = {}
    for kind in ('process', 'flow'):
        rpc = 'portal_search_processes_v3' if kind == 'process' else 'portal_search_flows_v3'
        for sort in ('relevance', 'modified_desc', 'name_asc'):
            result[f'{kind}_{sort}'] = f"select api.{rpc}('','{{}}','{sort}',null,20)"
        result[f'{kind}_geo'] = f"select api.{rpc}('','{{\"geographyNodeId\":\"geo:cn-ah\"}}')"
        result[f'{kind}_geo_direct'] = f"select api.{rpc}('','{{\"geographyNodeId\":\"geo:cn\",\"geographyScope\":\"direct\"}}')"
        result[f'{kind}_intersection'] = f"select api.{rpc}('','{{\"geographyNodeId\":\"geo:cn\",\"classificationNodeId\":\"class:{'isic' if kind == 'process' else 'cpc'}\"}}')"
        result[f'{kind}_no_match'] = f"select api.{rpc}('','{{\"source\":\"absent-723\"}}')"
        result[f'{kind}_uuid'] = f"select api.{rpc}('723b{'e' if kind == 'process' else 'f'}000-0000-4000-8000-000000000001','{{\"geographyNodeId\":\"geo:cn\"}}')"
    for kind in ('process', 'flow', 'all'):
        result[f'facets_{kind}'] = f"select api.portal_facets_v3('{kind}','','{{}}')"
        result[f'facets_{kind}_geo'] = f"select api.portal_facets_v3('{kind}','','{{\"geographyNodeId\":\"geo:cn-ah\"}}')"
    result['navigation_world'] = "select api.portal_navigation_v1('all','','{}','geography',null,null,500)"
    result['navigation_filtered'] = "select api.portal_navigation_v1('process','','{\"geographyNodeId\":\"geo:cn-ah\"}','classification','class:isic',null,100)"
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', required=True)
    parser.add_argument('--process-datasets', type=int, default=9000)
    parser.add_argument('--flow-datasets', type=int, default=55000)
    parser.add_argument('--card-padding', type=int, default=2048)
    parser.add_argument('--samples', type=int, default=3)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'supabase_db_database-engine-723-[a-z0-9-]+', args.container):
        parser.error('An explicitly isolated Database #723 container is required')
    if not (1 <= args.process_datasets <= 50000 and 1 <= args.flow_datasets <= 100000 and 1 <= args.samples <= 20 and 0 <= args.card_padding <= 8192):
        parser.error('Fixture/sample bounds exceeded')
    if args.report.exists():
        parser.error('Report must be a new file')
    context = json.loads(subprocess.check_output(['docker', 'context', 'inspect'], text=True))[0]
    if not context['Endpoints']['docker']['Host'].startswith('unix://'):
        parser.error('Only a local Docker socket is accepted')
    check = run(args.container, 'select inet_server_addr() is null; select count(*) from private.portal_catalog_search_rows_v1; select count(*) from private.portal_catalog_search_rows_v2;')
    if check.returncode or check.stdout.strip().splitlines() != ['t', '0', '0']:
        parser.error('Refusing a nonempty or non-local fixture database')
    candidate_text = CANDIDATE.read_text()
    candidate_sha256 = hashlib.sha256(candidate_text.encode()).hexdigest()
    guard = re.search(r'do \$portal_coverage\$.*?\$portal_coverage\$;', candidate_text, re.S)
    if not guard:
        raise ValueError('Missing migration cutover guard')
    statements = cases()
    sql = fixture(args.process_datasets, args.flow_datasets, args.card_padding)
    sql += r'''
reset role;
create temp table guard_checks(label text,state text);
grant select on guard_checks to portal_public_executor;
create function pg_temp.guard_state(mutation text,guard_sql text) returns text language plpgsql as $$
declare phase text:='mutation';
begin
 begin
  execute mutation;
  phase:='guard';
  execute guard_sql;
  raise exception using errcode='P7230',message='accepted fixture; roll back test mutation';
 exception when others then return phase||':'||sqlstate;
 end;
end $$;
'''
    mutations = {
        'complete': 'select 1',
        'missing_facet': "delete from private.portal_catalog_facet_rows_v1 where (dataset_kind,id,version) in (select dataset_kind,id,version from private.portal_catalog_facet_rows_v1 limit 1)",
        'missing_navigation': "delete from private.portal_navigation_versions_v1 where (dataset_kind,id,version) in (select dataset_kind,id,version from private.portal_navigation_versions_v1 limit 1)",
        'missing_process_projection': "delete from private.portal_catalog_search_rows_v2 where (dataset_kind,id,version) in (select dataset_kind,id,version from private.portal_catalog_search_rows_v2 limit 1)",
        'state_drift': "update private.portal_catalog_facet_rows_v1 set state_code=case state_code when 100 then 200 else 100 end where (dataset_kind,id,version) in (select dataset_kind,id,version from private.portal_catalog_facet_rows_v1 limit 1)",
        'timestamp_drift': "update private.portal_catalog_facet_rows_v1 set modified_at=modified_at+interval '1 second' where (dataset_kind,id,version) in (select dataset_kind,id,version from private.portal_catalog_facet_rows_v1 limit 1)",
    }
    for label, mutation in mutations.items():
        sql += f'insert into guard_checks values({sql_literal(label)},pg_temp.guard_state({sql_literal(mutation)},{sql_literal(guard.group())}));\n'
    sql += 'set local role portal_public_executor;\n'
    for variant in ('previous', 'candidate'):
        sql += definitions(variant == 'candidate', candidate_text) + '\n'
        for label, statement in statements.items():
            for i in range(args.samples):
                sql += f'select pg_temp.measure({sql_literal(variant)},{sql_literal(label)},{i},{sql_literal(statement)});\n'
        for kind in ('process', 'flow'):
            rpc = 'portal_search_processes_v3' if kind == 'process' else 'portal_search_flows_v3'
            for sort in ('relevance', 'modified_desc', 'name_asc'):
                statement = f"select api.{rpc}('','{{}}','{sort}',(select payload->>'nextCursor' from measurements where variant='previous' and label='{kind}_{sort}' and ordinal=0),20)"
                sql += f'select pg_temp.measure({sql_literal(variant)},{sql_literal(kind + "_" + sort + "_page2")},0,{sql_literal(statement)});\n'
        for label in ('process_geo', 'flow_geo', 'facets_all', 'facets_flow_geo', 'navigation_world'):
            sql += f'select pg_temp.capture_plan({sql_literal(variant)},{sql_literal(label)},{sql_literal(statements[label])});\n'
    sql += r'''
select jsonb_build_object('schemaVersion','portal.catalog-bounded-benchmark.v1',
 'guardChecks',(select jsonb_object_agg(label,state) from guard_checks),
 'samples',(select jsonb_agg(jsonb_build_object('variant',variant,'label',label,'ordinal',ordinal,'elapsedMs',elapsed_ms,'bytes',octet_length(payload::text),'sha256',encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex'),'error',error) order by label,variant,ordinal) from measurements),
 'equivalence',(select jsonb_agg(jsonb_build_object('label',p.label,'ordinal',p.ordinal,'comparable',p.error is null and c.error is null,'equal',p.payload=c.payload,'previousError',p.error,'candidateError',c.error) order by p.label,p.ordinal) from measurements p join measurements c using(label,ordinal) where p.variant='previous' and c.variant='candidate'),
 'plans',(select jsonb_agg(jsonb_build_object('variant',variant,'label',label,'plan',payload,'error',error) order by label,variant) from plans));
rollback;
'''
    result = run(args.container, sql)
    if result.returncode:
        print(result.stderr[-7000:], file=sys.stderr)
        return result.returncode
    records = [json.loads(line) for line in result.stdout.splitlines() if line.startswith('{')]
    if len(records) != 1:
        raise RuntimeError('Missing unique benchmark result')
    report = records[0]
    report['fixture'] = {'processVersions': 2 * args.process_datasets, 'flowVersions': 2 * args.flow_datasets, 'summaryPaddingBytes': args.card_padding, 'writerProof': 'separate real-writer SQL regression; direct public projections for read-scale only'}
    report['candidateSha256'] = candidate_sha256
    report['sqlSha256'] = hashlib.sha256(sql.encode()).hexdigest()
    report['sessionWorkMem'] = '12MB'
    report['scope'] = 'isolated local synthetic, rollback-only; function result and cursor equality, not production p95'
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    mismatches = [x for x in report['equivalence'] if x['comparable'] and not x['equal']]
    errors = [x for x in report['samples'] if x['variant'] == 'candidate' and x['error']]
    slow = [x for x in report['samples'] if x['variant'] == 'candidate' and x['elapsedMs'] > 2000]
    plan_errors = [x for x in report['plans'] if x['variant'] == 'candidate' and x['error']]
    expected_guards = {label: 'guard:P7230' if label == 'complete' else 'guard:55000' for label in mutations}
    guards_pass = report['guardChecks'] == expected_guards
    print(json.dumps({'report': str(args.report), 'samples': len(report['samples']), 'comparable': sum(x['comparable'] for x in report['equivalence']), 'mismatches': mismatches, 'candidateErrors': errors, 'overTwoSeconds': slow, 'planErrors': plan_errors, 'guardChecks': report['guardChecks']}, indent=2))
    return int(bool(mismatches or errors or slow or plan_errors or not guards_pass))


if __name__ == '__main__':
    raise SystemExit(main())
