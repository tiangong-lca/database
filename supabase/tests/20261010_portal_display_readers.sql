-- Rollback-only proof on a uniquely named isolated local Database #807 stack.
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
 ('80700000-0000-4000-8000-000000000101','01.00.000',0,pg_temp.portal_versions_process_payload('Visible draft process','01.00.000')),
 ('80700000-0000-4000-8000-000000000101','02.00.000',200,pg_temp.portal_versions_process_payload('Other brand process','02.00.000')),
 ('80700000-0000-4000-8000-000000000102','01.00.000',100,pg_temp.portal_versions_process_payload('Hidden approved process','01.00.000'));
insert into public.flows(id,version,state_code,json) values
 ('80700000-0000-4000-8000-000000000103','01.00.000',0,pg_temp.portal_versions_flow_payload('Visible flow','01.00.000'));
insert into private.dataset_display_settings(dataset_kind,dataset_id,dataset_version,is_visible,brand) values
 ('process','80700000-0000-4000-8000-000000000101','01.00.000',true,'tiangong_lca'),
 ('process','80700000-0000-4000-8000-000000000101','02.00.000',true,'bafu'),
 ('flow','80700000-0000-4000-8000-000000000103','01.00.000',true,'bafu');
select is((select count(*)::integer from private.display_catalog_search_rows_v2),2,'display projection contains two explicit Process versions');
select is((select state_code from private.display_catalog_search_rows_v2 where version='01.00.000'),0,'projection preserves real draft state');
set local role anon;
select throws_ok($$select api.portal_search_processes_v4(array['tiangong_lca'],'')$$,'P0001','portal catalog unavailable','legacy phase closes new readers');
reset role;
update private.portal_display_rollout set mode='display';
set local role anon;
select is(api.portal_get_dataset_v2(array['tiangong_lca'],'process','80700000-0000-4000-8000-000000000101','01.00.000')#>>'{brand,code}','tiangong_lca','state zero visible exact detail');
select is(api.portal_get_dataset_v2(array['tiangong_lca'],'process','80700000-0000-4000-8000-000000000101','02.00.000'),null::jsonb,'other brand exact detail unavailable');
select is(api.portal_get_dataset_v2(array['tiangong_lca'],'process','80700000-0000-4000-8000-000000000102','01.00.000'),null::jsonb,'unlisted state 100 detail unavailable');
select is(api.portal_search_processes_v4(array['tiangong_lca'],'')#>>'{items,0,key,version}','01.00.000','scope applies before latest version');
select is(jsonb_array_length(api.portal_search_processes_v4(array['tiangong_lca'],'','{"brand":"bafu"}') -> 'items'),0,'out-of-scope filter yields empty set');
select is(api.portal_list_versions_v2(array['tiangong_lca'],'process','80700000-0000-4000-8000-000000000101')#>>'{items,0,brand,code}','tiangong_lca','version brand');
select is(api.portal_search_flows_v4(array['bafu'],'')#>>'{items,0,brand,code}','bafu','draft Flow search');
select lives_ok($$select api.portal_catalog_summary_v2(array['tiangong_lca'])$$,'scoped summary');
select lives_ok($$select api.portal_facets_v4(array['tiangong_lca'],'process','')$$,'scoped facets');
select lives_ok($$select api.portal_navigation_v2(array['tiangong_lca'],'process','','{}','classification')$$,'scoped navigation');
reset role;

set local role anon;
select lives_ok($q$select api.portal_hybrid_search_v3(array['tiangong_lca'],'process',array['process'],'['||'1,'||repeat('0,',1022)||'0]','{}',20)$q$,'Hybrid V3 uses scoped candidates');
select is(api.portal_hybrid_search_v3(array['tiangong_lca'],'process',array['process'],'['||'1,'||repeat('0,',1022)||'0]','{}',20)#>>'{items,0,brand,code}','tiangong_lca','Hybrid V3 decorates exact brand');
select is(jsonb_array_length(api.portal_hybrid_search_v3(array['tiangong_lca'],'process',array['process'],'['||'1,'||repeat('0,',1022)||'0]','{"brand":"bafu"}',20)->'items'),0,'Hybrid brand filter cannot widen S');
select isnt(api.portal_hybrid_search_v3(array['tiangong_lca'],'process',array['process'],'['||'1,'||repeat('0,',1022)||'0]','{}',20)->>'queryFingerprint',api.portal_hybrid_search_v3(array['bafu','tiangong_lca'],'process',array['process'],'['||'1,'||repeat('0,',1022)||'0]','{}',20)->>'queryFingerprint','Hybrid fingerprint binds scope before ranking');
reset role;
create temporary table display_cursor_probe(value jsonb);
grant select,insert on display_cursor_probe to anon;
set local role anon;
insert into display_cursor_probe select api.portal_sitemap_manifest_v2(array['tiangong_lca']);
select lives_ok(format('select api.portal_sitemap_shard_v2(array[''tiangong_lca''],%L)',(select value#>>'{shards,0,shardCursor}' from display_cursor_probe)),'sitemap shard accepts its own scope');
select throws_ok(format('select api.portal_sitemap_shard_v2(array[''bafu''],%L)',(select value#>>'{shards,0,shardCursor}' from display_cursor_probe)),'22023','invalid portal request','sitemap cursor cannot cross deployment scope');
reset role;

-- Exact support chains remain readable across brands; standalone eligibility is scoped.
create or replace function pg_temp.portal_localized(p_text text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.jsonb_build_array(
    pg_catalog.jsonb_build_object(
      '@xml:lang', 'en',
      '#text', p_text
    )
  );
$$;

create or replace function pg_temp.portal_publication_and_ownership(
  p_version text,
  p_license_type text,
  p_access_restrictions text,
  p_exclusive_access boolean
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.jsonb_strip_nulls(
    pg_catalog.jsonb_build_object(
      'common:dataSetVersion', p_version,
      'common:licenseType', p_license_type,
      'common:dateOfLastRevision', '2026-08-25T10:00:00',
      'common:referenceToUnchangedRepublication', pg_catalog.jsonb_build_object(
        '@type', 'source data set',
        '@refObjectId', '52700000-0000-4000-8000-000000000903',
        '@version', '01.00.000',
        '@uri', 's3://portal-private-bucket/databases/catalog.json',
        'common:shortDescription', pg_temp.portal_localized('Portal Fixture Database')
      ),
      'common:referenceToOwnershipOfDataSet', pg_catalog.jsonb_build_object(
        '@type', 'contact data set',
        '@refObjectId', '52700000-0000-4000-8000-000000000902',
        '@version', '01.00.000',
        '@uri', 's3://portal-private-bucket/contacts/provider.json',
        'common:shortDescription', pg_temp.portal_localized('Portal Provider')
      ),
      'common:accessRestrictions',
        case
          when p_access_restrictions is null then null
          else pg_temp.portal_localized(p_access_restrictions)
        end,
      'common:referenceToEntitiesWithExclusiveAccess',
        case
          when p_exclusive_access then pg_catalog.jsonb_build_object(
            '@refObjectId', '52700000-0000-4000-8000-000000000901',
            '@uri', 's3://portal-private-bucket/exclusive-contact.json'
          )
          else null
        end
    )
  );
$$;

create or replace function pg_temp.portal_process_payload(
  p_name text,
  p_version text,
  p_flow_id uuid,
  p_flow_version text,
  p_mean_amount text,
  p_resulting_amount text,
  p_license_type text,
  p_access_restrictions text,
  p_exclusive_access boolean
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
          'UUID of process data set', p_flow_id::text,
          'name', pg_catalog.jsonb_build_object(
            'baseName', pg_temp.portal_localized(p_name)
          ),
          'common:generalComment', pg_temp.portal_localized(
            p_name || ' public general comment'
          ),
          'classificationInformation', pg_catalog.jsonb_build_object(
            'common:classification', pg_catalog.jsonb_build_array(
              pg_catalog.jsonb_build_object(
                '@classes', 's3://portal-private-bucket/classes.xml',
                'common:class', pg_catalog.jsonb_build_object(
                  '@level', '0',
                  '@classId', 'PORTAL-FIXTURE',
                  '#text', 'Portal fixture class'
                )
              )
            )
          )
        ),
        'quantitativeReference', pg_catalog.jsonb_build_object(
          'referenceToReferenceFlow', '1',
          'functionalUnitOrOther', pg_temp.portal_localized(
            'one kilogram of portal fixture product'
          )
        ),
        'time', pg_catalog.jsonb_build_object('common:referenceYear', '2024'),
        'geography', pg_catalog.jsonb_build_object(
          'locationOfOperationSupplyOrProduction',
          pg_catalog.jsonb_build_object(
            '@location', 'CN',
            'descriptionOfRestrictions', pg_temp.portal_localized('China')
          )
        ),
        'technology', pg_catalog.jsonb_build_object(
          'technologyDescriptionAndIncludedProcesses',
          pg_temp.portal_localized('Portal fixture technology')
        )
      ),
      'exchanges', pg_catalog.jsonb_build_object(
        'exchange', pg_catalog.jsonb_build_array(
          pg_catalog.jsonb_strip_nulls(
            pg_catalog.jsonb_build_object(
              '@dataSetInternalID', '1',
              'exchangeDirection', 'Output',
              'meanAmount', p_mean_amount,
              'resultingAmount', p_resulting_amount,
              'referenceToFlowDataSet', pg_catalog.jsonb_build_object(
                '@type', 'flow data set',
                '@refObjectId', p_flow_id::text,
                '@version', p_flow_version,
                '@uri', 's3://portal-private-bucket/flows/' || p_flow_id::text,
                'common:shortDescription', pg_temp.portal_localized(p_name || ' flow')
              )
            )
          )
        )
      ),
      'modellingAndValidation', pg_catalog.jsonb_build_object(
        'LCIMethodAndAllocation', pg_catalog.jsonb_build_object(
          'typeOfDataSet', 'Unit process, single operation'
        ),
        'dataSourcesTreatmentAndRepresentativeness', pg_catalog.jsonb_build_object(
          'referenceToDataSource', pg_catalog.jsonb_build_object(
            '@type', 'source data set',
            '@refObjectId', '52700000-0000-4000-8000-000000000904',
            '@version', '01.00.000',
            '@uri', 's3://portal-private-bucket/sources/process-source.json',
            'common:shortDescription', pg_temp.portal_localized('Portal Fixture Source')
          )
        ),
        'validation', pg_catalog.jsonb_build_object(
          'review', pg_catalog.jsonb_build_array(
            pg_catalog.jsonb_build_object(
              '@type', 'Independent external review'
            )
          )
        )
      ),
      'administrativeInformation', pg_catalog.jsonb_build_object(
        'publicationAndOwnership',
        pg_temp.portal_publication_and_ownership(
          p_version,
          p_license_type,
          p_access_restrictions,
          p_exclusive_access
        ) || pg_catalog.jsonb_build_object(
          'common:permanentDataSetURI',
          'https://storage.example.test/private/portal-bucket/processes/' || p_name
        )
      ),
      'privateLocator', 'portal-private-bucket/processes/' || p_name
    )
  );
$$;

create or replace function pg_temp.portal_flow_payload(
  p_name text,
  p_version text,
  p_flowproperty_id uuid,
  p_flowproperty_version text,
  p_license_type text,
  p_access_restrictions text,
  p_cas_number text default '50-00-0'
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
            'baseName', pg_temp.portal_localized(p_name)
          ),
          'common:generalComment', pg_temp.portal_localized(
            p_name || ' public general comment'
          ),
          'CASNumber', p_cas_number
        ),
        'quantitativeReference', pg_catalog.jsonb_build_object(
          'referenceToReferenceFlowProperty', '1'
        ),
        'typeOfDataSet', 'Product flow'
      ),
      'flowProperties', pg_catalog.jsonb_build_object(
        'flowProperty', pg_catalog.jsonb_build_array(
          pg_catalog.jsonb_build_object(
            '@dataSetInternalID', '1',
            'meanValue', '1.0000',
            'referenceToFlowPropertyDataSet', pg_catalog.jsonb_build_object(
              '@type', 'flow property data set',
              '@refObjectId', p_flowproperty_id::text,
              '@version', p_flowproperty_version,
              '@uri', 's3://portal-private-bucket/flow-properties/' || p_flowproperty_id::text,
              'common:shortDescription', pg_temp.portal_localized(p_name || ' property')
            )
          )
        )
      ),
      'modellingAndValidation', pg_catalog.jsonb_build_object(
        'LCIMethod', pg_catalog.jsonb_build_object(
          'typeOfDataSet', 'Product flow'
        ),
        'dataSourcesTreatmentAndRepresentativeness', pg_catalog.jsonb_build_object(
          'referenceToDataSource', pg_catalog.jsonb_build_object(
            '@type', 'source data set',
            '@refObjectId', '52700000-0000-4000-8000-000000000904',
            '@version', '01.00.000',
            '@uri', 's3://portal-private-bucket/sources/flow-source.json',
            'common:shortDescription', pg_temp.portal_localized('Portal Fixture Source')
          )
        )
      ),
      'administrativeInformation', pg_catalog.jsonb_build_object(
        'publicationAndOwnership',
        pg_temp.portal_publication_and_ownership(
          p_version,
          p_license_type,
          p_access_restrictions,
          false
        )
      ),
      'objectLocator', 'portal-private-bucket/flows/' || p_name
    )
  );
$$;

create or replace function pg_temp.portal_mixed_process_payload(
  p_name text,
  p_version text,
  p_valid_flow_id uuid,
  p_invalid_flow_id uuid
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  with base as (
    select pg_temp.portal_process_payload(
      p_name,
      p_version,
      p_valid_flow_id,
      '01.00.000',
      '5.0000',
      null,
      'Free of charge for all users and uses',
      null,
      false
    ) as payload
  )
  select pg_catalog.jsonb_set(
    base.payload,
    '{processDataSet,exchanges,exchange}',
    (base.payload #> '{processDataSet,exchanges,exchange}')
      || pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          '@dataSetInternalID', '2',
          'exchangeDirection', 'Input',
          'meanAmount', '6.0000',
          'referenceToFlowDataSet', pg_catalog.jsonb_build_object(
            '@type', 'flow data set',
            '@refObjectId', p_invalid_flow_id::text,
            '@version', '01.00.000',
            '@uri', 's3://portal-private-bucket/flows/' || p_invalid_flow_id::text,
            'common:shortDescription',
              pg_temp.portal_localized('state 200 support must remain hidden')
          )
        )
      ),
    false
  )
  from base;
$$;

create or replace function pg_temp.portal_incomplete_reference_process_payload(
  p_name text,
  p_version text,
  p_flow_id uuid
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  with base as (
    select pg_temp.portal_process_payload(
      p_name,
      p_version,
      p_flow_id,
      '01.00.000',
      'not-a-decimal',
      null,
      'Free of charge for all users and uses',
      null,
      false
    ) as payload
  )
  select pg_catalog.jsonb_set(
    base.payload,
    '{processDataSet,exchanges,exchange}',
    (base.payload #> '{processDataSet,exchanges,exchange}')
      || pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          '@dataSetInternalID', '2',
          'exchangeDirection', 'Input',
          'meanAmount', '8.0000',
          'referenceToFlowDataSet', pg_catalog.jsonb_build_object(
            '@type', 'flow data set',
            '@refObjectId', p_flow_id::text,
            '@version', '01.00.000',
            '@uri', 's3://portal-private-bucket/flows/' || p_flow_id::text,
            'common:shortDescription',
              pg_temp.portal_localized('otherwise valid non-reference Exchange')
          )
        )
      ),
    false
  )
  from base;
$$;

create or replace function pg_temp.portal_duplicate_internal_process_payload(
  p_name text,
  p_version text,
  p_flow_id uuid
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  with base as (
    select pg_temp.portal_process_payload(
      p_name,
      p_version,
      p_flow_id,
      '01.00.000',
      '9.0000',
      null,
      'Free of charge for all users and uses',
      null,
      false
    ) as payload
  )
  select pg_catalog.jsonb_set(
    base.payload,
    '{processDataSet,exchanges,exchange}',
    (base.payload #> '{processDataSet,exchanges,exchange}')
      || pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          '@dataSetInternalID', '1',
          'exchangeDirection', 'Input',
          'meanAmount', '10.0000',
          'referenceToFlowDataSet', pg_catalog.jsonb_build_object(
            '@type', 'flow data set',
            '@refObjectId', p_flow_id::text,
            '@version', '01.00.000',
            '@uri', 's3://portal-private-bucket/flows/' || p_flow_id::text,
            'common:shortDescription',
              pg_temp.portal_localized('duplicate internal id must be hidden')
          )
        )
      ),
    false
  )
  from base;
$$;

create or replace function pg_temp.portal_flowproperty_payload(
  p_name text,
  p_version text,
  p_unitgroup_id uuid,
  p_unitgroup_version text,
  p_license_type text
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'flowPropertyDataSet', pg_catalog.jsonb_build_object(
      'flowPropertiesInformation', pg_catalog.jsonb_build_object(
        'dataSetInformation', pg_catalog.jsonb_build_object(
          'common:name', pg_temp.portal_localized(p_name)
        ),
        'quantitativeReference', pg_catalog.jsonb_build_object(
          'referenceToReferenceUnitGroup', pg_catalog.jsonb_build_object(
            '@type', 'unit group data set',
            '@refObjectId', p_unitgroup_id::text,
            '@version', p_unitgroup_version,
            '@uri', 's3://portal-private-bucket/unit-groups/' || p_unitgroup_id::text,
            'common:shortDescription', pg_temp.portal_localized(p_name || ' unit group')
          )
        )
      ),
      'administrativeInformation', pg_catalog.jsonb_build_object(
        'publicationAndOwnership',
        pg_temp.portal_publication_and_ownership(
          p_version,
          p_license_type,
          'none',
          false
        )
      )
    )
  );
$$;

create or replace function pg_temp.portal_unitgroup_payload(
  p_name text,
  p_version text,
  p_license_type text
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'unitGroupDataSet', pg_catalog.jsonb_build_object(
      'unitGroupInformation', pg_catalog.jsonb_build_object(
        'dataSetInformation', pg_catalog.jsonb_build_object(
          'common:name', pg_temp.portal_localized(p_name)
        ),
        'quantitativeReference', pg_catalog.jsonb_build_object(
          'referenceToReferenceUnit', '1'
        )
      ),
      'units', pg_catalog.jsonb_build_object(
        'unit', pg_catalog.jsonb_build_array(
          pg_catalog.jsonb_build_object(
            '@dataSetInternalID', '1',
            'name', 'kg',
            'meanValue', '1.0000'
          )
        )
      ),
      'administrativeInformation', pg_catalog.jsonb_build_object(
        'publicationAndOwnership',
        pg_temp.portal_publication_and_ownership(
          p_version,
          p_license_type,
          'none',
          false
        )
      )
    )
  );
$$;


insert into public.unitgroups(id,version,state_code,json) values ('80700000-0000-4000-8000-000000000104','01.00.000',0,
 pg_temp.portal_unitgroup_payload('Display kilogram','01.00.000','Free of charge for all users and uses'));
insert into public.flowproperties(id,version,state_code,json) values ('80700000-0000-4000-8000-000000000105','01.00.000',20,
 pg_temp.portal_flowproperty_payload('Display mass','01.00.000','80700000-0000-4000-8000-000000000104','01.00.000','Free of charge for all users and uses'));
update public.flows set state_code=0 where id='80700000-0000-4000-8000-000000000103';
update public.flows set json=pg_temp.portal_flow_payload('Cross brand flow','01.00.000','80700000-0000-4000-8000-000000000105','01.00.000','Free of charge for all users and uses','none') where id='80700000-0000-4000-8000-000000000103';
update public.processes set json=pg_temp.portal_process_payload('Visible draft process','01.00.000','80700000-0000-4000-8000-000000000103','01.00.000','2',null,'Free of charge for all users and uses','none',false) where id='80700000-0000-4000-8000-000000000101' and version='01.00.000';
insert into private.dataset_display_settings(dataset_kind,dataset_id,dataset_version,is_visible,brand) values
 ('unitgroup','80700000-0000-4000-8000-000000000104','01.00.000',true,null),
 ('flowproperty','80700000-0000-4000-8000-000000000105','01.00.000',true,'uslci');
set local role anon;
select is(api.portal_get_dataset_v2(array['tiangong_lca'],'process','80700000-0000-4000-8000-000000000101','01.00.000')#>>'{metadata,functionalUnit,amount}','2','draft numeric functional unit follows visible cross-brand/null support');
select is(jsonb_array_length(api.portal_list_process_exchanges_v2(array['tiangong_lca'],'80700000-0000-4000-8000-000000000101','01.00.000')->'rows'),1,'draft exchanges retain globally visible dependencies');
select is(api.portal_flow_link_eligibility_v1(array['tiangong_lca'],'[{"id":"80700000-0000-4000-8000-000000000103","version":"01.00.000"}]')#>>'{0,linkable}','false','cross-brand support has no standalone link');
select is(api.portal_flow_link_eligibility_v1(array['bafu','tiangong_lca'],'[{"id":"80700000-0000-4000-8000-000000000103","version":"01.00.000"}]')#>>'{0,linkable}','true','in-scope Flow is linkable');
select is(api.portal_get_dataset_v1('process','80700000-0000-4000-8000-000000000101','01.00.000')->>'schemaVersion','portal.public-dataset.v1','old detail keeps its DTO in display mode');
select is(api.portal_get_dataset_v1('process','80700000-0000-4000-8000-000000000102','01.00.000'),null::jsonb,'old URL cannot bypass display settings');
select is(api.portal_get_dataset_v1('flow','80700000-0000-4000-8000-000000000103','01.00.000')->'brand',null::jsonb,'old unscoped API does not change shape');
select lives_ok($q$select api.portal_sitemap_manifest_v2(array['tiangong_lca'])$q$,'scoped sitemap manifest');
select is(jsonb_array_length(api.portal_sitemap_entries_v2(array['tiangong_lca'],'process',null,50)->'items'),1,'sitemap excludes outside-scope Flow and later Process version');
select isnt(api.portal_search_processes_v4(array['tiangong_lca'],'')->>'queryFingerprint',api.portal_search_processes_v4(array['bafu','tiangong_lca'],'')->>'queryFingerprint','query fingerprint binds canonical deployment scope');
select throws_ok($q$select api.portal_search_processes_v4(array[]::text[],'')$q$,'22023','invalid portal brand scope','empty scope has no fallback');
select throws_ok($q$select api.portal_search_processes_v4(array['*'],'')$q$,'22023','invalid portal brand scope','wildcard scope rejected');
select throws_ok($q$select count(*) from private.dataset_display_settings$q$,'42501',null,'anonymous settings remain private');
select throws_ok($q$select private.portal_display_transition_v1('display','unavailable')$q$,'42501',null,'anonymous callers cannot activate or switch modes');
reset role;
update private.dataset_display_settings set is_visible=false where dataset_kind='unitgroup';
set local role anon;
select is(api.portal_get_dataset_v2(array['tiangong_lca'],'process','80700000-0000-4000-8000-000000000101','01.00.000')#>'{metadata,functionalUnit,amount}','null'::jsonb,'hidden dependency removes numeric functional unit immediately');
select is(jsonb_array_length(api.portal_list_process_exchanges_v2(array['tiangong_lca'],'80700000-0000-4000-8000-000000000101','01.00.000')->'rows'),0,'hidden dependency removes exchanges');
reset role;
update private.dataset_display_settings set is_visible=true where dataset_kind='unitgroup';
update public.flows set json=jsonb_set(json,'{flowDataSet,administrativeInformation,publicationAndOwnership,common:licenseType}','"Other"') where id='80700000-0000-4000-8000-000000000103';
set local role anon;
select is(jsonb_array_length(api.portal_list_process_exchanges_v2(array['tiangong_lca'],'80700000-0000-4000-8000-000000000101','01.00.000')->'rows'),0,'dependency license still gates numeric exchange');
reset role;
update private.dataset_display_settings set brand='worldsteel' where dataset_kind='process' and dataset_version='01.00.000';
set local role anon;
select is(api.portal_get_dataset_v2(array['tiangong_lca'],'process','80700000-0000-4000-8000-000000000101','01.00.000'),null::jsonb,'brand change immediately removes old scope');
select is(api.portal_get_dataset_v2(array['worldsteel'],'process','80700000-0000-4000-8000-000000000101','01.00.000')#>>'{brand,name}','World steel','brand change updates projection and DTO');
reset role;
select lives_ok($q$select private.portal_display_transition_v1('display','unavailable')$q$,'operator can disable all Portal readers');
set local role anon;
select throws_ok($q$select api.portal_get_dataset_v1('process','80700000-0000-4000-8000-000000000101','01.00.000')$q$,'P0001','portal catalog unavailable','old reader fails closed in unavailable mode');
select throws_ok($q$select api.portal_search_processes_v4(array['worldsteel'],'')$q$,'P0001','portal catalog unavailable','new reader fails closed in unavailable mode');
reset role;
select throws_ok($q$select private.portal_display_transition_v1('unavailable','legacy')$q$,'55000','invalid display rollout transition','cutover cannot restore legacy state bypass');
select lives_ok($q$select private.portal_display_transition_v1('unavailable','display')$q$,'complete projection passes readiness');
alter table public.flows disable trigger portal_display_source_sync;
set local role anon;
select throws_ok($q$select api.portal_search_processes_v4(array['worldsteel'],'')$q$,'P0001','portal catalog unavailable','writer drift is refused by independent display manifest');
reset role;
alter table public.flows enable trigger portal_display_source_sync;


-- Summary examples retain checksum and uniqueness semantics after grouping.
insert into public.flows(id,version,state_code,json) values
 ('80700000-0000-4000-8000-000000000110','01.00.000',0,pg_temp.portal_versions_flow_payload('Duplicate CAS','01.00.000')),
 ('80700000-0000-4000-8000-000000000111','01.00.000',0,jsonb_set(pg_temp.portal_versions_flow_payload('Unique CAS','01.00.000'),'{flowDataSet,flowInformation,dataSetInformation,CASNumber}','"64-17-5"')),
 ('80700000-0000-4000-8000-000000000112','01.00.000',0,jsonb_set(pg_temp.portal_versions_flow_payload('Invalid CAS','01.00.000'),'{flowDataSet,flowInformation,dataSetInformation,CASNumber}','"12-34-5"'));
insert into private.dataset_display_settings(dataset_kind,dataset_id,dataset_version,is_visible,brand)
select 'flow',id,version,true,'bafu' from public.flows where id in
 ('80700000-0000-4000-8000-000000000110','80700000-0000-4000-8000-000000000111','80700000-0000-4000-8000-000000000112');
set local role anon;
select is((select x->>'query' from jsonb_array_elements(api.portal_catalog_summary_v2(array['bafu'])->'examples') x where x->>'queryKind'='cas'),'64-17-5','summary skips invalid checksums and duplicate visible CAS values');
reset role;
update private.dataset_display_settings set brand='uslci' where dataset_id='80700000-0000-4000-8000-000000000110';
set local role anon;
select is((select x->>'query' from jsonb_array_elements(api.portal_catalog_summary_v2(array['bafu'])->'examples') x where x->>'queryKind'='cas'),'50-00-0','out-of-scope duplicate does not disqualify a scoped CAS example');
reset role;

-- The set-based scope bridge remains private and reads live exact settings.
set local role anon;
select throws_ok($q$select * from private.display_request_visible_settings_v1$q$,'42501',null,'anonymous callers cannot read the private scope bridge');
reset role;
select ok(not has_table_privilege('authenticated','private.display_request_visible_settings_v1','select'),'authenticated cannot read scope bridge');
select ok(not has_table_privilege('service_role','private.display_request_visible_settings_v1','select'),'service role cannot read scope bridge');
select ok(not has_table_privilege('portal_display_executor','private.dataset_display_settings','select'),'display executor does not gain raw settings access');
select ok(not has_table_privilege('portal_display_executor','private.display_request_visible_settings_v1','update'),'display executor cannot write the bridge');
create temporary table scope_keys as select dataset_kind,dataset_id,dataset_version from private.dataset_display_settings;
grant select on scope_keys to portal_display_executor;
set local role portal_display_executor;
select set_config('portal.display_brands','worldsteel,tiangong_lca',true),set_config('portal.display_global','false',true),set_config('portal.display_filter_brand','',true);
select is((select count(*) from scope_keys k where private.portal_display_request_visible_v1(k.dataset_kind,k.dataset_id,k.dataset_version::text)),(select count(*) from private.display_request_visible_settings_v1),'bridge matches exact scoped predicate');
select set_config('portal.display_global','true',true);
select is((select count(*) from scope_keys k where private.portal_display_request_visible_v1(k.dataset_kind,k.dataset_id,k.dataset_version::text)),(select count(*) from private.display_request_visible_settings_v1),'global bridge includes visible null-brand support like original predicate');
select set_config('portal.display_filter_brand','uslci',true);
select is((select count(*) from scope_keys k where private.portal_display_request_visible_v1(k.dataset_kind,k.dataset_id,k.dataset_version::text)),(select count(*) from private.display_request_visible_settings_v1),'brand filter still narrows global bridge');
reset role;
-- Preserve a stale projection deliberately: authorization must still recheck
-- settings, rather than trusting copied brand or projection existence.
alter table private.dataset_display_settings disable trigger user;
update private.dataset_display_settings set is_visible=false where dataset_kind='process' and dataset_version='01.00.000';
alter table private.dataset_display_settings enable trigger user;
set local role anon;
select is(jsonb_array_length(api.portal_search_processes_v4(array['worldsteel'],'')->'items'),0,'stale projection cannot expose an exact key hidden in settings');
select is(api.portal_catalog_summary_v2(array['worldsteel'])#>>'{counts,process}','0','summary excludes hidden stale projections');
reset role;
alter view private.display_request_visible_settings_v1 set (security_barrier=false);
select throws_ok($q$select private.portal_display_assert_contract_v1()$q$,'P0001','portal catalog unavailable','scope view option drift fails closed');
alter view private.display_request_visible_settings_v1 set (security_barrier=true);
select lives_ok($q$select private.portal_display_assert_contract_v1()$q$,'restored barrier restores exact contract');

select * from finish();
rollback;
