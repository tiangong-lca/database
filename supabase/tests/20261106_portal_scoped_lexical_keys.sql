-- Database #925: closed lexical bridge scope, ACL, and integrity regression.
-- Real-writer constructors retained from the #864 public fixture.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions,public,auth;
select extensions.no_plan();

create or replace function pg_temp.portal_versions_localized(p_text text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.jsonb_build_array(
    pg_catalog.jsonb_build_object('@xml:lang', 'en', '#text', p_text)
  )
$$;

create or replace function pg_temp.portal_versions_publication(
  p_version text,
  p_license text
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'common:dataSetVersion', p_version,
    'common:licenseType', p_license,
    'common:referenceToOwnershipOfDataSet', pg_catalog.jsonb_build_object(
      '@type', 'contact data set',
      '@refObjectId', '52900000-0000-4000-8000-000000000900',
      '@version', '01.00.000',
      '@uri', 's3://portal-private/provider.json',
      'common:shortDescription', pg_temp.portal_versions_localized('Portal Provider')
    )
  )
$$;

create or replace function pg_temp.portal_versions_process_payload(
  p_name text,
  p_version text
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'processDataSet', pg_catalog.jsonb_build_object(
      'processInformation', pg_catalog.jsonb_build_object(
        'dataSetInformation', pg_catalog.jsonb_build_object(
          'name', pg_catalog.jsonb_build_object(
            'baseName', pg_temp.portal_versions_localized(p_name)
          ),
          'common:generalComment', pg_temp.portal_versions_localized(p_name || ' summary'),
          'classificationInformation', pg_catalog.jsonb_build_object(
            'common:classification', pg_catalog.jsonb_build_array(
              pg_catalog.jsonb_build_object(
                'common:class', pg_catalog.jsonb_build_object(
                  '@level', '0', '@classId', 'PORTAL-HYBRID', '#text', 'Hybrid fixture'
                )
              )
            )
          )
        ),
        'time', pg_catalog.jsonb_build_object('common:referenceYear', '2024'),
        'geography', pg_catalog.jsonb_build_object(
          'locationOfOperationSupplyOrProduction', pg_catalog.jsonb_build_object(
            '@location', 'CN',
            'descriptionOfRestrictions', pg_temp.portal_versions_localized('China')
          )
        ),
        'technology', pg_catalog.jsonb_build_object(
          'technologyDescriptionAndIncludedProcesses',
          pg_temp.portal_versions_localized('Hybrid fixture technology')
        )
      ),
      'modellingAndValidation', pg_catalog.jsonb_build_object(
        'LCIMethodAndAllocation', pg_catalog.jsonb_build_object(
          'typeOfDataSet', 'Unit process, single operation'
        )
      ),
      'administrativeInformation', pg_catalog.jsonb_build_object(
        'publicationAndOwnership', pg_temp.portal_versions_publication(
          p_version, 'Free of charge for all users and uses'
        )
      ),
      'privateLocator', 's3://portal-private/process/' || p_name
    )
  )
$$;

create or replace function pg_temp.portal_versions_flow_payload(
  p_name text,
  p_version text
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'flowDataSet', pg_catalog.jsonb_build_object(
      'flowInformation', pg_catalog.jsonb_build_object(
        'dataSetInformation', pg_catalog.jsonb_build_object(
          'name', pg_catalog.jsonb_build_object(
            'baseName', pg_temp.portal_versions_localized(p_name)
          ),
          'common:generalComment', pg_temp.portal_versions_localized(p_name || ' summary'),
          'classificationInformation', pg_catalog.jsonb_build_object(
            'common:classification', pg_catalog.jsonb_build_array(
              pg_catalog.jsonb_build_object(
                'common:class', pg_catalog.jsonb_build_object(
                  '@level', '0', '@classId', 'PORTAL-HYBRID', '#text', 'Hybrid fixture'
                )
              )
            )
          ),
          'CASNumber', '50-00-0'
        ),
        'geography', pg_catalog.jsonb_build_object(
          'locationOfSupply', pg_catalog.jsonb_build_object(
            '@location', 'CN',
            'descriptionOfRestrictions', pg_temp.portal_versions_localized('China')
          )
        )
      ),
      'modellingAndValidation', pg_catalog.jsonb_build_object(
        'LCIMethod', pg_catalog.jsonb_build_object('typeOfDataSet', 'Product flow')
      ),
      'administrativeInformation', pg_catalog.jsonb_build_object(
        'publicationAndOwnership', pg_temp.portal_versions_publication(
          p_version, 'Free of charge for all users and uses'
        )
      ),
      'objectLocator', 's3://portal-private/flow/' || p_name
    )
  )
$$;


create or replace function util.invoke_edge_function(name text,body jsonb,timeout_milliseconds integer default 300000)
returns void language plpgsql security definer set search_path='' as $$begin return; end$$;
insert into public.processes(id,version,state_code,json) values
 ('86400000-0000-4000-8000-000000000101','01.00.000',0,pg_temp.portal_versions_process_payload('Shared864 50-00-0 %_ history','01.00.000')),
 ('86400000-0000-4000-8000-000000000101','02.00.000',200,pg_temp.portal_versions_process_payload('Shared864 50-00-0 current','02.00.000')),
 ('86400000-0000-4000-8000-000000000102','01.00.000',100,pg_temp.portal_versions_process_payload('Shared864 hidden','01.00.000'));
insert into public.flows(id,version,state_code,json) values
 ('86400000-0000-4000-8000-000000000103','01.00.000',0,pg_temp.portal_versions_flow_payload('Shared864 flow','01.00.000'));
insert into private.dataset_display_settings(dataset_kind,dataset_id,dataset_version,is_visible,brand) values
 ('process','86400000-0000-4000-8000-000000000101','01.00.000',true,'tiangong_lca'),
 ('process','86400000-0000-4000-8000-000000000101','02.00.000',true,'bafu'),
 ('flow','86400000-0000-4000-8000-000000000103','01.00.000',true,'bafu');

update private.portal_display_rollout set mode='display';
select ok(not has_function_privilege(r,
  'private.display_catalog_scoped_pattern_keys_v1(text,text)','EXECUTE'),
  r || ' cannot execute the owner key bridge')
from unnest(array['anon','authenticated','service_role','api_internal_executor','portal_public_executor']) r;
select ok(has_function_privilege('portal_display_executor',
  'private.display_catalog_scoped_pattern_keys_v1(text,text)','EXECUTE'),
  'only the constrained Portal reader receives bridge access');
select is((select proowner::regrole::text from pg_proc
  where oid='private.display_catalog_scoped_pattern_keys_v1(text,text)'::regprocedure),
  'postgres','closed bridge has its declared owner');
select ok((select prosecdef and not proleakproof and provolatile='s'
  and proconfig @> array['search_path=""','statement_timeout=20s','plan_cache_mode=force_custom_plan','row_security=on']
  from pg_proc where oid='private.display_catalog_scoped_pattern_keys_v1(text,text)'::regprocedure),
  'bridge pins execution settings and does not claim leakproof');
select ok(bool_and(c.relrowsecurity and c.relforcerowsecurity),
  'projection RLS remains forced') from pg_class c where c.oid in
  ('private.display_catalog_search_rows_v1'::regclass,'private.display_catalog_search_rows_v2'::regclass);

set local role portal_display_executor;
set local portal.display_brands='tiangong_lca';
set local portal.display_global='false';
set local portal.display_filter_brand='';
select results_eq(
  $$select * from private.display_catalog_scoped_pattern_keys_v1('process','%shared864%') order by id,version$$,
  $$select id,version from private.display_catalog_search_rows_v2 where dataset_kind='process' and document like '%shared864%' order by id,version$$,
  'owner bridge agrees with exact RLS including historical scope');
select is((select count(*) from private.display_catalog_scoped_pattern_keys_v1('flow','%shared864%')),0::bigint,
  'a matching Flow in another brand is excluded');
prepare scoped925(text,text) as select * from private.display_catalog_scoped_pattern_keys_v1($1,$2) order by id,version;
set local portal.display_brands='bafu';
select results_eq($$execute scoped925('process','%shared864%')$$,
  $$select '86400000-0000-4000-8000-000000000101'::uuid,'02.00.000'::text$$,
  'same prepared reader observes a changed brand');
set local portal.display_brands='tiangong_lca,bafu';
select is((select count(*) from private.display_catalog_scoped_pattern_keys_v1('process','%shared864%')),2::bigint,
  'combined deployment retains all matching versions before latest/count');
set local portal.display_filter_brand='bafu';
select is((select count(*) from private.display_catalog_scoped_pattern_keys_v1('process','%shared864%')),1::bigint,
  'narrowing brand filter remains authoritative');
set local portal.display_brands='tiangong_lca';
select is((select count(*) from private.display_catalog_scoped_pattern_keys_v1('process','%shared864%')),0::bigint,
  'brand filter cannot broaden deployment');
set local portal.display_filter_brand='';
set local portal.display_brands='';
select is((select count(*) from private.display_catalog_scoped_pattern_keys_v1('process','%shared864%')),0::bigint,
  'empty scope fails closed');
set local portal.display_global='true';
select is((select count(*) from private.display_catalog_scoped_pattern_keys_v1('process','%shared864%')),2::bigint,
  'legacy global support retains exact visible versions');
select results_eq(
  $$select * from private.display_catalog_scoped_pattern_keys_v1('process','%\%\_%') order by id,version$$,
  $$select id,version from private.display_catalog_search_rows_v2 where document like '%\%\_%' escape E'\\' order by id,version$$,
  'escaped percent/underscore keep literal LIKE semantics');
select is((select count(*) from private.display_catalog_scoped_pattern_keys_v1('process',null)),0::bigint,
  'null pattern does not match');
select throws_ok($$select * from private.display_catalog_scoped_pattern_keys_v1('process; select 1','%')$$,
  '22023','invalid portal request','kind is a closed allowlist');
select results_eq(
  $$select * from private.display_catalog_process_pattern_versions_v1('%s%') order by id,version$$,
  $$select * from private.display_catalog_process_single_character_versions_v1('s') order by id,version$$,
  'existing one-character dispatch stays identical');
reset role;

-- Hide settings while retaining stale projection rows deliberately: the bridge
-- must consult authoritative settings rather than trust cached brand/card data.
alter table private.dataset_display_settings disable trigger user;
update private.dataset_display_settings set is_visible=false where dataset_kind='process'
 and dataset_id='86400000-0000-4000-8000-000000000101' and dataset_version='02.00.000';
alter table private.dataset_display_settings enable trigger user;
set local role portal_display_executor;
select is((select count(*) from private.display_catalog_scoped_pattern_keys_v1('process','%shared864%')),1::bigint,
  'stale visible-looking projection cannot outlive withdrawal');
reset role;
-- Current identity guard includes the helper definition and its ACL.
grant execute on function private.display_catalog_scoped_pattern_keys_v1(text,text) to anon;
select throws_ok($$select private.portal_display_assert_contract_v1()$$,'P0001','portal catalog unavailable',
  'bridge grant drift fails the public contract closed');
revoke execute on function private.display_catalog_scoped_pattern_keys_v1(text,text) from anon;
select lives_ok($$select private.portal_display_assert_contract_v1()$$,'restored ACL restores contract identity');
deallocate scoped925;
select * from finish();
rollback;
