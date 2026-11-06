#!/usr/bin/env python3
"""Database #925: compare exact public responses on one owned rollback fixture.

Reuses only #864's deterministic projection fixture builder. Its environment and
collector are not adopted. No hosted DSN, query cap, planner hint or timeout
increase is accepted. Results are local warm samples, not hosted p95.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

import benchmark_portal_facets_navigation as fixture_source

ROOT = Path(__file__).resolve().parents[1]
WORK = Path('/tmp/portal-query-925-pg1711')
CONTAINER = 'supabase_db_portal-query-925-pg1711'
READERS = ('display_catalog_process_pattern_versions_v1', 'display_catalog_flow_pattern_versions_v1',
           'display_catalog_search_v3_impl')


def literal(value):
    return "'" + value.replace("'", "''") + "'"


def run(sql, **kwargs):
    return subprocess.run(['docker', 'exec', '-i', CONTAINER, 'psql', '-X',
                           '-U', 'supabase_admin', '-d', 'postgres', '-Atq',
                           '-v', 'ON_ERROR_STOP=1'], input=sql, text=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-ref', required=True)
    parser.add_argument('--process-datasets', type=int, default=9500)
    parser.add_argument('--flow-datasets', type=int, default=69000)
    parser.add_argument('--samples', type=int, default=3)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    if not (20 <= args.process_datasets <= 20000 and 40 <= args.flow_datasets <= 100000 and 2 <= args.samples <= 10):
        parser.error('bounded fixture and 2..10 samples required')
    if any(args.report.with_suffix(s).exists() for s in ('.json', '.sql', '.log', '.out')):
        parser.error('new evidence paths required')
    assert 'tiangong-lca/database#925' in (WORK/'OWNER.md').read_text()
    assert 'project_id = "portal-query-925-pg1711"' in (WORK/'supabase/config.toml').read_text()
    context = json.loads(subprocess.check_output(['docker', 'context', 'inspect'], text=True))[0]
    assert context['Endpoints']['docker']['Host'].startswith('unix://')
    target = json.loads(subprocess.check_output(['docker', 'inspect', '--format',
        '{{json .Config.Labels}}', CONTAINER], text=True))
    assert target.get('com.supabase.cli.project') == 'portal-query-925-pg1711'
    guard = 'select inet_server_addr() is null;show server_version;' + ''.join(
        f'select count(*) from {t};' for t in fixture_source.TABLES)
    server = run('show server_version;', capture_output=True, check=True).stdout.strip()
    assert server == '17.11'
    expected = ['t', server] + ['0'] * len(fixture_source.TABLES)
    assert run(guard, capture_output=True, check=True).stdout.splitlines() == expected
    base = subprocess.check_output(['git', 'rev-parse', args.base_ref+'^{commit}'], cwd=ROOT, text=True).strip()
    baseline = []
    candidate = []
    for name in READERS:
        path = f'supabase/workspace/schemas/private/functions/{name}/definition.sql'
        baseline.append(subprocess.check_output(['git', 'show', base+':'+path], cwd=ROOT, text=True))
        candidate.append(run(f"select pg_get_functiondef(oid) from pg_proc where pronamespace='private'::regnamespace and proname='{name}';",
                             capture_output=True, check=True).stdout + ';\n')
    variants = {'baseline': '\n'.join(baseline), 'candidate': '\n'.join(candidate)}
    sql = fixture_source.fixture(args.process_datasets, args.flow_datasets, 1024, 'cas-dense', True)
    sql = sql.replace("set application_name='portal864-serial';", "set application_name='portal925-benchmark';")
    sql = sql.replace('begin;\n', "begin;\ndo $$begin if not pg_try_advisory_xact_lock(925,1) then raise exception 'Another #925 qualification owns this database';end if;end$$;\n", 1)
    # Search's public card decorator requires exact source support. Populate
    # synthetic raw support while the fixture's source writers are suspended;
    # restore all original writers before sampling. This is reader-scale proof.
    source_rows = '\n'.join(
        f"insert into public.{table}(id,version,state_code,json) select id,version,state_code,pg_temp.payload('{kind}','CN','0111') from private.display_catalog_search_rows_v1 where dataset_kind='{kind}';"
        for kind, table in [('process','processes'),('flow','flows')])
    sql = sql.replace('do $$declare r record;begin for r in select * from original_triggers loop',
                      source_rows+'\ndo $$declare r record;begin for r in select * from original_triggers loop')
    sql += """
create temp table samples(variant text,label text,ordinal int,ms numeric,payload jsonb,error text);
grant select,insert on samples to anon;
create function pg_temp.measure(v text,l text,i int,q text) returns void language plpgsql as $$
declare t timestamptz:=clock_timestamp();p jsonb;e text;begin
 begin execute q into p;exception when query_canceled then e:=sqlstate;when others then e:=sqlstate;end;
 insert into samples values(v,l,i,extract(epoch from clock_timestamp()-t)*1000,p,e);
end$$;
grant execute on function pg_temp.measure(text,text,int,text) to anon;
"""
    cases = {}
    for scope in ('tiangong_lca', 'tiangong_lca,bafu,uslci,worldsteel'):
        brands = 'array['+','.join(literal(b) for b in scope.split(','))+']'
        for kind in ('process', 'flow'):
            for label, query in [('rare','bench'+kind+' 00000001'),('broad','history864'),('absent','absent925')]:
                for api in ('search','facets','navigation'):
                    if api == 'search':
                        q = f"select api.portal_search_{kind}es_v4({brands},{literal(query)})" if kind == 'process' else f"select api.portal_search_flows_v4({brands},{literal(query)})"
                    elif api == 'facets':
                        q = f"select api.portal_facets_v4({brands},{literal(kind)},{literal(query)})"
                    else:
                        q = f"select api.portal_navigation_v2({brands},{literal(kind)},{literal(query)},'{{}}','geography')"
                    cases[scope+':'+kind+':'+label+':'+api] = q
    for ordinal in range(args.samples):
        for variant in (('baseline','candidate') if ordinal%2 == 0 else ('candidate','baseline')):
            sql += '\nreset role;\n'+variants[variant]+fixture_source.REFRESH+'\nset local role anon;\n'
            for label, query in cases.items():
                sql += f"select pg_temp.measure({literal(variant)},{literal(label)},{ordinal},{literal(query)});\n"
    sql += '\nreset role;\n'+variants['candidate']+fixture_source.REFRESH
    sql += """
-- Bound natural nested-plan probes separately from latency samples.
load 'auto_explain';
set local auto_explain.log_min_duration=0;
set local auto_explain.log_analyze=true;
set local auto_explain.log_timing=false;
set local auto_explain.log_buffers=true;
set local auto_explain.log_nested_statements=true;
set local auto_explain.log_format=json;
set local auto_explain.log_level=notice;
set local role portal_display_executor;
set local portal.display_brands='tiangong_lca';
set local portal.display_global='false';
set local portal.display_filter_brand='';
select count(*) from private.display_catalog_scoped_pattern_keys_v1('flow','%benchflow 00000001%');
select count(*) from private.display_catalog_scoped_pattern_keys_v1('process','%benchprocess 00000001%');
reset role;
set local auto_explain.log_min_duration=-1;
"""
    sql += """
reset role;
select jsonb_build_object(
 'timings',(select jsonb_agg(to_jsonb(t)) from (
   select variant,label,count(*) samples,max(ms) max_ms,percentile_disc(.95) within group(order by ms) p95_ms,
     count(*) filter(where error is not null) failures from samples group by variant,label order by variant,label) t),
 'parityFailures',(select count(*) from samples a join samples b using(label,ordinal)
   where a.variant='baseline' and b.variant='candidate' and (a.error is not null or b.error is not null or a.payload is distinct from b.payload)),
 'responseErrors',(select coalesce(jsonb_agg(jsonb_build_object('variant',variant,'label',label,'code',error)),'[]') from samples where error is not null));
rollback;
"""
    args.report.with_suffix('.sql').write_text(sql)
    with args.report.with_suffix('.out').open('x') as out, args.report.with_suffix('.log').open('x') as log:
        result = run(sql, stdout=out, stderr=log, timeout=3600)
    rows = [json.loads(s) for s in args.report.with_suffix('.out').read_text().splitlines() if s.startswith('{')]
    plan_log = args.report.with_suffix('.log').read_text()
    assert len(plan_log.encode()) <= 4*1024*1024, 'bounded plan receipt exceeded'
    report = {'base':base, 'postgresVersion':server, 'processDatasets':args.process_datasets, 'flowDatasets':args.flow_datasets,
              'sourceSha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'fixtureSourceSha256':hashlib.sha256(Path(fixture_source.__file__).read_bytes()).hexdigest(),
              'sqlSha256':hashlib.sha256(sql.encode()).hexdigest(), 'psqlExitCode':result.returncode,
              'naturalLexicalIndexConditions': plan_log.count('"Index Cond": "(document ~~'),
              'classification':'local synthetic rollback reader samples, not hosted performance'}
    if len(rows) == 1:
        report.update(rows[0])
    report['cleanupVerified'] = run(guard,capture_output=True,check=True).stdout.splitlines() == expected
    report['passed'] = result.returncode == 0 and report.get('parityFailures') == 0 and report['cleanupVerified'] and all(
        r['p95_ms'] <= 2000 and r['failures'] == 0 for r in report.get('timings',[]) if r['variant']=='candidate')
    args.report.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k != 'timings'}))
    return int(not report['passed'])


if __name__ == '__main__':
    raise SystemExit(main())
