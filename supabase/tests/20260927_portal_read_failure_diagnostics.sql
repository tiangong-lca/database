-- Closed diagnostic categories must not change the public failure contract.
-- Fixtures, grants and injected helper failures are always rolled back.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public;
set local client_min_messages=log;
select no_plan();
grant portal_public_executor,api_internal_executor to postgres;

create function pg_temp.public_error(p_sql text) returns jsonb language plpgsql as $$
declare c text; m text; d text; h text;
begin
  execute p_sql;
  return null;
exception when others then
  get stacked diagnostics c=RETURNED_SQLSTATE,m=MESSAGE_TEXT,d=PG_EXCEPTION_DETAIL,h=PG_EXCEPTION_HINT;
  return jsonb_build_object('code',c,'message',m,'details',nullif(d,''),'hint',nullif(h,''));
end;
$$;
grant execute on function pg_temp.public_error(text) to anon;

set local role anon;
select is(pg_temp.public_error($q$select api.portal_navigation_v1('all','','{}','geography','class:isic',null,1)$q$),
  '{"code":"22023","message":"invalid portal request","details":null,"hint":null}'::jsonb,
  'parent rejection keeps exact public code/message and empty detail/hint');
select is(pg_temp.public_error($q$select api.portal_navigation_v1('all','','{"geographyNodeId":"geo:private-738-marker"}','geography',null,null,1)$q$),
  '{"code":"22023","message":"invalid portal request","details":null,"hint":null}'::jsonb,
  'missing hierarchy node does not expose its locator');
select is(pg_temp.public_error($q$select api.portal_navigation_v1('all','','{}','geography',null,'private-738-marker',1)$q$),
  '{"code":"22023","message":"invalid portal request","details":null,"hint":null}'::jsonb,
  'cursor rejection keeps the existing public error');
select is(pg_temp.public_error($q$select api.portal_navigation_v1('all','','{}','geography',null,null,501)$q$),
  '{"code":"22023","message":"invalid portal request","details":null,"hint":null}'::jsonb,
  'options rejection retains page bound');
select is(pg_temp.public_error($q$select api.portal_navigation_v1('all',E'private-738-marker\n','{}','geography',null,null,1)$q$),
  '{"code":"22023","message":"invalid portal request","details":null,"hint":null}'::jsonb,
  'invalid search text never enters the error response');
select is(pg_temp.public_error($q$select api.portal_get_dataset_v1('private-738-marker','73800000-0000-4000-8000-000000000001','01.00.000')$q$),
  '{"code":"22023","message":"invalid portal request","details":null,"hint":null}'::jsonb,
  'dataset validation remains public-only and generic');
select is(pg_temp.public_error($q$select api.portal_facets_v3('all','','{"private-738-marker":true}')$q$),
  '{"code":"22023","message":"invalid portal request","details":null,"hint":null}'::jsonb,
  'facets validation keeps exact external error');
reset role;

-- This assertion is shared by summary, navigation and V3 facets. Its injected
-- body is not a mapping helper and is restored before the fixture rolls back.
create temp table diagnostic_original_assertion as
select pg_get_functiondef('private.assert_portal_catalog_projection_contract_cn1()'::regprocedure) as definition;
create function pg_temp.set_fault(p_code text,p_message text) returns void language plpgsql as $$
begin
  execute format('create or replace function private.assert_portal_catalog_projection_contract_cn1() returns void language plpgsql stable security definer set search_path='''' as $fault$ begin raise exception using errcode=%L,message=%L; end; $fault$',p_code,p_message);
end;
$$;

select pg_temp.set_fault('57014','canceling statement due to statement timeout');
select is(pg_temp.public_error('select api.portal_catalog_summary_v1()'),
  '{"code":"P0001","message":"portal catalog unavailable","details":null,"hint":null}'::jsonb,
  'summary cancellation keeps exact external contract');
select is(pg_temp.public_error($q$select api.portal_navigation_v1('all','','{}','geography',null,null,1)$q$),
  '{"code":"P0001","message":"portal catalog unavailable","details":null,"hint":null}'::jsonb,
  'navigation cancellation stays unavailable');
select is(pg_temp.public_error($q$select api.portal_facets_v3('all','','{}')$q$),
  '{"code":"P0001","message":"portal catalog unavailable","details":null,"hint":null}'::jsonb,
  'facets cancellation stays unavailable');
select pg_temp.set_fault('57014','canceling statement due to user request');
select is(pg_temp.public_error('select api.portal_catalog_summary_v1()'),
  '{"code":"P0001","message":"portal catalog unavailable","details":null,"hint":null}'::jsonb,
  'cancel request does not become a timeout claim or public detail');
select pg_temp.set_fault('57014','private-738-marker statement timeout');
select is(pg_temp.public_error('select api.portal_catalog_summary_v1()'),
  '{"code":"P0001","message":"portal catalog unavailable","details":null,"hint":null}'::jsonb,
  'nonstandard cancellation text remains private and unknown');
select pg_temp.set_fault('55000','private-738-marker');
select is(pg_temp.public_error('select api.portal_catalog_summary_v1()'),
  '{"code":"P0001","message":"portal catalog unavailable","details":null,"hint":null}'::jsonb,
  'contract drift remains unavailable without echoing its original message');
select pg_temp.set_fault('54000','private-738-marker');
select is(pg_temp.public_error('select api.portal_catalog_summary_v1()'),
  '{"code":"P0001","message":"portal catalog unavailable","details":null,"hint":null}'::jsonb,
  'response budget failure keeps the sanitized public error');
select pg_temp.set_fault('XX000','private-738-marker');
select is(pg_temp.public_error('select api.portal_catalog_summary_v1()'),
  '{"code":"P0001","message":"portal catalog unavailable","details":null,"hint":null}'::jsonb,
  'unrecognized internal failure does not disclose original data');
do $$begin execute (select definition from diagnostic_original_assertion); end$$;

create temp table diagnostic_original_dataset as
select pg_get_functiondef('private.portal_dataset_projection_v1(text,uuid,text)'::regprocedure) as definition;
create or replace function private.portal_dataset_projection_v1(p_kind text,p_id uuid,p_version text)
returns jsonb language plpgsql stable parallel restricted set search_path='' as $$
begin raise exception using errcode='57014',message='canceling statement due to user request'; end;
$$;
set local role anon;
select is(pg_temp.public_error($q$select api.portal_get_dataset_v1('process','73800000-0000-4000-8000-000000000001','01.00.000')$q$),
  '{"code":"P0001","message":"portal catalog unavailable","details":null,"hint":null}'::jsonb,
  'dataset cancellation also preserves the anonymous public failure contract');
reset role;
do $$begin execute (select definition from diagnostic_original_dataset); end$$;

select ok(not has_schema_privilege('anon','private','usage'),'no private diagnostic surface is exposed');
select ok(not has_function_privilege('anon','private.portal_navigation_v1(text,text,jsonb,text,text,text,integer)','execute'),
  'anonymous callers cannot call private validation directly');
-- Display Search uses the same closed diagnostic contract for both kinds.
-- Replace only its inner reader; manifest refresh admits the test definition.
-- Rollback restores the reader, manifest, rollout, memberships and all fixtures.
grant portal_display_executor to postgres;
update private.portal_display_rollout set mode='display' where singleton;
create temp table diagnostic_original_search as
select pg_get_functiondef('private.display_search_v3(text,text,jsonb,text,text,integer)'::regprocedure) as definition;
create function pg_temp.set_search_fault(p_code text,p_message text) returns void language plpgsql as $test$
begin
  execute format('create or replace function private.display_search_v3(p_kind text,p_query text,p_filters jsonb,p_sort text,p_cursor text,p_limit integer) returns jsonb language plpgsql stable parallel restricted set search_path='''' as $fault$ begin raise exception using errcode=%L,message=%L,detail=''private-935-detail'',hint=''private-935-hint''; end; $fault$',p_code,p_message);
  update private.portal_display_contract_manifest set identity=private.portal_display_contract_identity_v1() where singleton;
end;
$test$;
create function pg_temp.check_search_fault(p_code text,p_message text) returns setof text language plpgsql as $test$
declare k text; expected jsonb;
begin
  perform pg_temp.set_search_fault(p_code,p_message);
  expected:=jsonb_build_object('code',case when p_code='22023' then '22023' else 'P0001' end,
    'message',case when p_code='22023' then 'invalid portal request' else 'portal catalog unavailable' end,
    'details',null,'hint',null);
  execute 'set local role anon';
  foreach k in array array['processes','flows'] loop
    return next extensions.is(pg_temp.public_error(format('select api.portal_search_%s_v4(array[''tiangong_lca''],''private-935-query'',p_cursor=>''private-935-cursor'')',k)),expected,
      'display '||k||' '||p_code||' preserves public code/message and hides original message/detail/hint');
  end loop;
  execute 'reset role';
end;
$test$;
select * from pg_temp.check_search_fault('22023','private-935-message');
select * from pg_temp.check_search_fault('57014','canceling statement due to statement timeout');
select * from pg_temp.check_search_fault('57014','canceling statement due to user request');
select * from pg_temp.check_search_fault('57014','private-935-message statement timeout');
select * from pg_temp.check_search_fault('55000','private-935-message');
select * from pg_temp.check_search_fault('54000','private-935-message');
select * from pg_temp.check_search_fault('XX000','private-935-message');
do $$begin execute (select definition from diagnostic_original_search); end$$;
update private.portal_display_contract_manifest set identity=private.portal_display_contract_identity_v1() where singleton;
select private.portal_display_assert_contract_v1();

select * from finish();
rollback;
