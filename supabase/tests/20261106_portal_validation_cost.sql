-- Database #943: removing a duplicate call must retain every fail-closed guard.
-- Drift is injected into real dependencies, not into the Search implementation.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public;
select no_plan();
grant portal_public_executor,api_internal_executor,portal_display_executor to postgres;
update private.portal_display_rollout set mode='display' where singleton;

create function pg_temp.error943(q text) returns jsonb language plpgsql as $$
declare c text;m text;d text;h text;
begin execute q;return null;
exception when others then
 get stacked diagnostics c=RETURNED_SQLSTATE,m=MESSAGE_TEXT,d=PG_EXCEPTION_DETAIL,h=PG_EXCEPTION_HINT;
 return jsonb_build_object('code',c,'message',m,'details',nullif(d,''),'hint',nullif(h,''));
end$$;
grant execute on function pg_temp.error943(text) to anon;
create function pg_temp.refused943(label text) returns setof text language plpgsql as $$
declare kind text;
begin
 execute 'set local role anon';
 foreach kind in array array['processes','flows'] loop
  return next extensions.is(pg_temp.error943(format('select api.portal_search_%s_v4(array[''tiangong_lca''],'''',p_limit=>1)',kind)),
   '{"code":"P0001","message":"portal catalog unavailable","details":null,"hint":null}'::jsonb,
   kind||' refuses '||label||' before returning data');
 end loop;
 execute 'reset role';
end$$;

set local role anon;
select lives_ok($q$select api.portal_search_processes_v4(array['tiangong_lca'],'',p_limit=>1)$q$,
 'Process Search succeeds with the intact contract');
select lives_ok($q$select api.portal_search_flows_v4(array['tiangong_lca'],'',p_limit=>1)$q$,
 'Flow Search succeeds with the intact contract');
reset role;

create temp table originals943 as select p.oid,pg_get_functiondef(p.oid) definition
from pg_proc p where p.oid in ('private.portal_process_names_v1(jsonb)'::regprocedure,
 'private.sync_portal_navigation_row_v1()'::regprocedure,
 'private.display_navigation_scoped_filter_keys_v1(text,jsonb)'::regprocedure);
create function pg_temp.drift943(target regprocedure) returns void language plpgsql as $$
declare original text;changed text;
begin
 select definition into strict original from originals943 where oid=target;
 changed:=replace(original,'AS $function$','AS $function$'||E'\n-- 943 definition drift canary\n');
 if changed=original then raise exception 'Cannot inject exact function-body drift';end if;
 execute changed;
end$$;
create function pg_temp.restore943(target regprocedure) returns void language plpgsql as $$
begin execute (select definition from originals943 where oid=target);end$$;

select pg_temp.drift943('private.portal_process_names_v1(jsonb)');
select lives_ok('select private.portal_display_assert_contract_v1()',
 'outer display manifest alone does not cover the legacy name writer');
select * from pg_temp.refused943('catalog writer definition drift');
select pg_temp.restore943('private.portal_process_names_v1(jsonb)');

select pg_temp.drift943('private.sync_portal_navigation_row_v1()');
select lives_ok('select private.portal_display_assert_contract_v1()',
 'outer display manifest alone does not cover the legacy navigation writer');
select * from pg_temp.refused943('navigation writer definition drift');
select pg_temp.restore943('private.sync_portal_navigation_row_v1()');

-- The additional owner bridge is part of the same full manifest, never a
-- publicly callable bypass. Exercise real definition and grant drift.
select pg_temp.drift943('private.display_navigation_scoped_filter_keys_v1(text,jsonb)');
select * from pg_temp.refused943('filter-key bridge definition drift');
select pg_temp.restore943('private.display_navigation_scoped_filter_keys_v1(text,jsonb)');
grant execute on function private.display_navigation_scoped_filter_keys_v1(text,jsonb) to anon;
select * from pg_temp.refused943('filter-key bridge grant drift');
revoke execute on function private.display_navigation_scoped_filter_keys_v1(text,jsonb) from anon;
select ok(not has_function_privilege('anon','private.display_navigation_scoped_filter_keys_v1(text,jsonb)','EXECUTE'),
 'filter-key bridge is closed to anonymous direct calls');
select ok(not has_function_privilege('authenticated','private.display_navigation_scoped_filter_keys_v1(text,jsonb)','EXECUTE'),
 'filter-key bridge is closed to authenticated direct calls');
select ok(not has_function_privilege('service_role','private.display_navigation_scoped_filter_keys_v1(text,jsonb)','EXECUTE'),
 'filter-key bridge grants no service role access');
select ok(has_function_privilege('portal_display_executor','private.display_navigation_scoped_filter_keys_v1(text,jsonb)','EXECUTE'),
 'only the existing display executor receives bridge execution');
set local role anon;
select is(pg_temp.error943($q$select * from private.display_navigation_scoped_filter_keys_v1('all','{}')$q$)->>'code','42501',
 'anonymous SQL cannot invoke the owner bridge');
reset role;

alter table private.portal_catalog_search_rows_v1 no force row level security;
select * from pg_temp.refused943('projection FORCE RLS drift');
alter table private.portal_catalog_search_rows_v1 force row level security;

set local role anon;
select is(pg_temp.error943($q$select api.portal_search_flows_v4(array['tiangong_lca'],'',p_filters=>'[]')$q$),
 '{"code":"22023","message":"invalid portal request","details":null,"hint":null}'::jsonb,
 'input validation remains unchanged after guard consolidation');
select lives_ok($q$select api.portal_search_processes_v4(array['tiangong_lca'],'',p_limit=>1)$q$,
 'Process Search recovers after exact dependency restoration');
select lives_ok($q$select api.portal_search_flows_v4(array['tiangong_lca'],'',p_limit=>1)$q$,
 'Flow Search recovers after exact dependency restoration');
reset role;
select * from finish();
rollback;
