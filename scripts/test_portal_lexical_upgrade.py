#!/usr/bin/env python3
"""Rollback-only real-writer upgrade proof on the explicitly owned #925 stack."""
import argparse
import re
from pathlib import Path
import subprocess

import benchmark_portal_lexical_keys as bench


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-ref', required=True)
    parser.add_argument('--log', type=Path, required=True)
    args = parser.parse_args()
    assert 'tiangong-lca/database#925' in (bench.WORK/'OWNER.md').read_text()
    assert not args.log.exists()
    assert bench.run('show server_version;',capture_output=True,check=True).stdout.strip() == '17.11'
    fixture = (bench.ROOT/'supabase/tests/20261025_portal_facets_navigation.sql').read_text()
    sql = fixture[:fixture.index('create function pg_temp.facet_count')]
    sql = sql.replace('begin;\n', "begin;\nset application_name='portal925-upgrade';\ndo $$begin if not pg_try_advisory_xact_lock(925,1) then raise exception 'Another #925 qualification owns this database';end if;end$$;\n", 1)
    for name in bench.READERS:
        path = f'supabase/workspace/schemas/private/functions/{name}/definition.sql'
        sql += subprocess.check_output(['git','show',args.base_ref+':'+path],cwd=bench.ROOT,text=True)
    bridge_path='supabase/workspace/schemas/private/functions/display_catalog_scoped_pattern_keys_v1/definition.sql'
    has_bridge=subprocess.run(['git','cat-file','-e',args.base_ref+':'+bridge_path],cwd=bench.ROOT,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0
    if not has_bridge:
        sql += 'drop function private.display_catalog_scoped_pattern_keys_v1(text,text);\n'
    sql += """
update private.portal_display_contract_manifest set identity=private.portal_display_contract_identity_v1() where singleton;
select private.portal_display_assert_contract_v1();
create temp table original_metadata as select oid,proowner,proacl,proconfig,prosecdef,provolatile,proparallel
 from pg_proc where pronamespace='private'::regnamespace and proname in
 ('display_catalog_process_pattern_versions_v1','display_catalog_flow_pattern_versions_v1','display_catalog_search_v3_impl',
  'display_catalog_search_v2_impl','display_catalog_candidate_rows_v2','display_navigation_impl_v1',
  'display_api_search_processes_v3','display_api_search_flows_v3');
create temp table original_facts as select md5(jsonb_build_object(
 'settings',(select jsonb_agg(to_jsonb(s) order by dataset_kind,dataset_id,dataset_version) from private.dataset_display_settings s),
 'projections',(select jsonb_agg(to_jsonb(p) order by dataset_kind,id,version) from private.display_catalog_search_current_v2 p),
 'roles',(select jsonb_agg(to_jsonb(r) order by rolname) from pg_roles r),
 'policies',(select jsonb_agg(to_jsonb(p) order by oid) from pg_policy p),
 'triggers',(select jsonb_agg(to_jsonb(t) order by oid) from pg_trigger t)
 )::text) digest;
create temp table replies(label text primary key,query text,payload jsonb);
grant select,insert,update on replies to anon;
"""
    for scope in ('tiangong_lca','bafu','tiangong_lca,bafu','worldsteel'):
        brands='array['+','.join(bench.literal(b) for b in scope.split(','))+']'
        for kind in ('process','flow'):
            for query in ('','shared864','%_','50-00-0','s','absent925',
                          'shared864 50-00-0 current','portal-hybrid',
                          '86400000-0000-4000-8000-000000000101'):
                calls=[f"select api.portal_search_{'processes' if kind=='process' else 'flows'}_v4({brands},{bench.literal(query)},p_sort=>{bench.literal(sort)},p_limit=>1)"
                       for sort in ('relevance','name_asc','modified_desc')]
                calls += [f"select api.portal_facets_v4({brands},{bench.literal(kind)},{bench.literal(query)})",
                       f"select api.portal_navigation_v2({brands},{bench.literal(kind)},{bench.literal(query)},'{{}}','geography')"]
                calls += [f"select api.portal_navigation_v2({brands},{bench.literal(kind)},{bench.literal(query)},'{{}}','classification',{parent})"
                          for parent in ('null',bench.literal('class:isic' if kind=='process' else 'class:cpc'))]
                for i,call in enumerate(calls):
                    sql += f"insert into replies values({bench.literal(scope+':'+kind+':'+query+':'+str(i))},{bench.literal(call)},null);\n"
    sql += """
set local role anon;
do $$declare r record;p jsonb;begin for r in select * from replies loop execute r.query into p;update replies set payload=p where label=r.label;end loop;end$$;
do $$declare r record;q text;p jsonb;begin
 for r in select * from replies where query like 'select api.portal_search_%' and payload->>'nextCursor' is not null loop
   q:=replace(r.query,',p_limit=>1)',format(',p_cursor=>%L,p_limit=>1)',r.payload->>'nextCursor'));
   execute q into p;
   insert into replies values(r.label||':predecessor-page2',q,p);
 end loop;
end$$;
reset role;
"""
    migration='\n'.join((bench.ROOT/('supabase/migrations/'+name)).read_text().replace('\nbegin;\n','\n',1).removesuffix('commit;\n') for name in ('20261106110000_optimize_portal_scoped_lexical_keys.sql','20261106114708_bound_portal_candidate_key_reads.sql','20261106125654_bound_selective_portal_navigation_counts.sql','20261106142546_bound_empty_portal_pages_and_diagnose_search.sql'))
    sql += migration
    sql += """
select results_eq($$select oid,proowner,proacl,proconfig,prosecdef,provolatile,proparallel from pg_proc where oid in(select oid from original_metadata) order by oid$$,
 $$select * from original_metadata order by oid$$,'existing routine OIDs, owners, ACLs and configs survive upgrade');
select is((select md5(jsonb_build_object(
 'settings',(select jsonb_agg(to_jsonb(s) order by dataset_kind,dataset_id,dataset_version) from private.dataset_display_settings s),
 'projections',(select jsonb_agg(to_jsonb(p) order by dataset_kind,id,version) from private.display_catalog_search_current_v2 p),
 'roles',(select jsonb_agg(to_jsonb(r) order by rolname) from pg_roles r),
 'policies',(select jsonb_agg(to_jsonb(p) order by oid) from pg_policy p),
 'triggers',(select jsonb_agg(to_jsonb(t) order by oid) from pg_trigger t)
 )::text)),(select digest from original_facts),'source-derived projections/settings, roles, RLS and triggers are untouched');
set local role anon;
create function pg_temp.compare925() returns setof text language plpgsql as $$
declare r record;p jsonb;begin for r in select * from replies loop execute r.query into p;return next extensions.is(p,r.payload,'upgrade response parity: '||r.label);end loop;end$$;
select * from pg_temp.compare925();
reset role;
"""
    sql += migration
    sql += "select lives_ok($$select private.portal_display_assert_contract_v1()$$,'repeat migration preserves complete contract');select * from finish();rollback;"
    with args.log.open('x') as log:
        result=bench.run(sql,stdout=log,stderr=subprocess.STDOUT,timeout=180)
    output=args.log.read_text()
    count = len(re.findall(r'^ok \d+ - ', output, re.M))
    assert result.returncode==0 and 'not ok' not in output and count>=323 and f'1..{count}' in output, str(args.log)
    print(f'{count} upgrade assertions passed; transaction rolled back: '+str(args.log))


if __name__=='__main__':
    main()
