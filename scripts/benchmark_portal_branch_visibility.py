#!/usr/bin/env python3
"""Compare complete navigation responses on the explicitly owned #925 rollback fixture."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import benchmark_portal_lexical_keys as bench


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-ref', required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--samples', type=int, default=3, choices=range(2, 6))
    args = parser.parse_args()
    assert 'tiangong-lca/database#925' in (bench.WORK/'OWNER.md').read_text()
    assert 'project_id = "portal-query-925-pg1711"' in (bench.WORK/'supabase/config.toml').read_text()
    context = json.loads(subprocess.check_output(['docker','context','inspect'],text=True))[0]
    assert context['Endpoints']['docker']['Host'].startswith('unix://')
    target = json.loads(subprocess.check_output(['docker','inspect','--format','{{json .Config.Labels}}',bench.CONTAINER],text=True))
    assert target['com.supabase.cli.project']=='portal-query-925-pg1711'
    guard='select inet_server_addr() is null;show server_version;'+''.join(f'select count(*) from {t};' for t in bench.fixture_source.TABLES)
    expected=['t','17.11']+['0']*len(bench.fixture_source.TABLES)
    assert bench.run(guard,capture_output=True,check=True).stdout.splitlines()==expected
    for suffix in ('.sql','.out','.log','.json'):
        assert not args.report.with_suffix(suffix).exists()
    base=subprocess.check_output(['git','rev-parse',args.base_ref+'^{commit}'],cwd=bench.ROOT,text=True).strip()
    path='supabase/workspace/schemas/private/functions/display_navigation_impl_v1/definition.sql'
    baseline=subprocess.check_output(['git','show',base+':'+path],cwd=bench.ROOT,text=True)
    candidate=bench.run("select pg_get_functiondef(oid)||';' from pg_proc where pronamespace='private'::regnamespace and proname='display_navigation_impl_v1' order by oid;",capture_output=True,check=True).stdout+';\n'
    variants={'baseline':baseline,'candidate':candidate}
    sql=bench.fixture_source.fixture(9500,69000,1024,'cas-dense',True)
    sql=sql.replace("set application_name='portal864-serial';","set application_name='portal935-branch-visibility';")
    sql=sql.replace('begin;\n',"begin;\ndo $$begin if not pg_try_advisory_xact_lock(925,1) then raise exception 'Another #925 qualification owns this database';end if;end$$;\n",1)
    sql+='''
create temp table samples(variant text,label text,ordinal int,ms numeric,payload jsonb,error text);
grant select,insert on samples to anon;
create function pg_temp.measure(v text,l text,i int,q text) returns void language plpgsql as $$
declare t timestamptz:=clock_timestamp();p jsonb;e text;begin
 begin execute q into p;exception when query_canceled then e:=sqlstate;when others then e:=sqlstate;end;
 insert into samples values(v,l,i,extract(epoch from clock_timestamp()-t)*1000,p,e);
end$$;
grant execute on function pg_temp.measure(text,text,int,text) to anon;
'''
    cases={}
    for scope in ('tiangong_lca','tiangong_lca,bafu,uslci,worldsteel'):
        brands='array['+','.join(bench.literal(b) for b in scope.split(','))+']'
        for kind in ('process','flow','all'):
            parents=[('classification',None),('classification','class:isic' if kind=='process' else 'class:cpc'),
                     ('classification','class:isic:0.0.0' if kind=='process' else 'class:cpc:1.6'),
                     ('geography',None),('geography','geo:cn')]
            for label,query in [('rare','bench'+('flow' if kind=='all' else kind)+' 00000001'),('broad','history864'),('absent','absent935'),('empty',''),('selective','bench'+('flow' if kind=='all' else kind)+' 00000')]:
                for dimension,parent in parents:
                    for filters in ('{}','{"geography":"CN"}'):
                        arguments=f"{brands},{bench.literal(kind)},{bench.literal(query)},{bench.literal(filters)}::jsonb,{bench.literal(dimension)},{'null' if parent is None else bench.literal(parent)},null,50"
                        key=':'.join([scope,kind,label,dimension,parent or 'root',filters])
                        cases[key]=f"select api.portal_navigation_branches_v1({arguments})"
    for ordinal in range(args.samples):
        for variant in (['baseline','candidate'] if ordinal%2==0 else ['candidate','baseline']):
            sql+='reset role;\n'+variants[variant]+bench.fixture_source.REFRESH+'set local role anon;\n'
            for label,q in cases.items():
                sql+=f"select pg_temp.measure('{variant}',{bench.literal(label)},{ordinal},{bench.literal(q)});\n"
    sql+='reset role;\n'+candidate+bench.fixture_source.REFRESH+'''
select jsonb_build_object(
 'timings',(select jsonb_agg(to_jsonb(t)) from (
   select variant,label,count(*) samples,max(ms) max_ms,percentile_disc(.95) within group(order by ms) p95_ms,
     count(*) filter(where error is not null) failures from samples group by variant,label order by variant,label) t),
 'parityFailures',(select count(*) from samples a join samples b using(label,ordinal)
   where a.variant='baseline' and b.variant='candidate' and (a.error is not null or b.error is not null or a.payload is distinct from b.payload)));
load 'auto_explain';
set local auto_explain.log_min_duration=0;
set local auto_explain.log_analyze=true;
set local auto_explain.log_timing=false;
set local auto_explain.log_buffers=true;
set local auto_explain.log_nested_statements=true;
set local auto_explain.log_format=json;
set local auto_explain.log_level=notice;
set local role anon;
select api.portal_navigation_branches_v1(array['tiangong_lca'],'flow','','{}','classification','class:cpc:1.6');
select api.portal_navigation_branches_v1(array['tiangong_lca'],'flow');
select api.portal_navigation_branches_v1(array['tiangong_lca'],'process','history864','{}','geography','geo:cn');
reset role;
set local auto_explain.log_min_duration=-1;
rollback;
'''
    args.report.with_suffix('.sql').write_text(sql)
    with args.report.with_suffix('.out').open('x') as out,args.report.with_suffix('.log').open('x') as log:
        result=bench.run(sql,stdout=out,stderr=log,timeout=3600)
    rows=[json.loads(s) for s in args.report.with_suffix('.out').read_text().splitlines() if s.startswith('{') and '"timings"' in s]
    report={'base':base,'processVersions':19000,'flowVersions':138000,'cases':len(cases),'samples':args.samples,
            'collectorSha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            'candidateSha256':hashlib.sha256(candidate.encode()).hexdigest(),
            'sqlSha256':hashlib.sha256(sql.encode()).hexdigest(),'psqlExitCode':result.returncode,
            'classification':'local synthetic rollback-only warm samples, not hosted latency'}
    if len(rows)==1: report.update(rows[0])
    timings={(r['variant'],r['label']):r['p95_ms'] for r in report.get('timings',[])}
    report['costRegressions']=[label for (v,label),ms in timings.items() if v=='candidate' and ms>max(50,timings['baseline',label]*1.5)]
    report['cleanupVerified']=bench.run(guard,capture_output=True,check=True).stdout.splitlines()==expected
    report['passed']=result.returncode==0 and len(rows)==1 and report['parityFailures']==0 and not report['costRegressions'] and report['cleanupVerified'] and all(r['p95_ms']<=2000 and r['failures']==0 for r in report.get('timings',[]) if r['variant']=='candidate')
    args.report.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k!='timings'}))
    return int(not report['passed'])


if __name__=='__main__':
    raise SystemExit(main())
