-- Database #864: real-writer Facets/Navigation all-version and scope regression.
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
create function pg_temp.facet_count(p_page jsonb,p_group text,p_value text)
returns bigint language sql immutable set search_path='' as $$
 select coalesce((select (v->>'count')::bigint from jsonb_array_elements(p_page->'groups') g
 cross join lateral jsonb_array_elements(g->'values') v
 where g->>'id'=p_group and v->>'value'=p_value),0)
$$;
create temp table responses(label text primary key,page jsonb);
grant execute on function pg_temp.facet_count(jsonb,text,text) to anon;
grant select,insert on responses to anon;
set local role anon;
insert into responses values
 ('lexical',api.portal_facets_v4(array['bafu','tiangong_lca'],'all',' Shared864 ')),
 ('empty',api.portal_facets_v4(array['bafu','tiangong_lca'],'all','')),
 ('scope',api.portal_facets_v4(array['tiangong_lca'],'all','shared864')),
 ('geo',api.portal_facets_v4(array['bafu','tiangong_lca'],'all','shared864','{"geography":"CN"}')),
 ('year',api.portal_facets_v4(array['bafu','tiangong_lca'],'all','shared864','{"referenceYearFrom":2024,"referenceYearTo":2024}')),
 ('cas',api.portal_facets_v4(array['bafu','tiangong_lca'],'all','50-00-0')),
 ('uuid',api.portal_facets_v4(array['bafu','tiangong_lca'],'all','86400000-0000-4000-8000-000000000101')),
 ('literal',api.portal_facets_v4(array['bafu','tiangong_lca'],'all','%_')),
 ('none',api.portal_facets_v4(array['worldsteel'],'all','shared864')),
 ('nav',api.portal_navigation_v2(array['bafu','tiangong_lca'],'process','shared864','{}','geography','geo:cn'));
select is(pg_temp.facet_count(page,'kind','process'),2::bigint,'lexical Facets retain both historical Process versions') from responses where label='lexical';
select is(pg_temp.facet_count(page,'kind','flow'),1::bigint,'lexical Facets retain Flow with null year') from responses where label='lexical';
select is(pg_temp.facet_count(page,'brand','bafu'),2::bigint,'brand counts use exact per-version brands') from responses where label='lexical';
select is(pg_temp.facet_count(page,'brand','tiangong_lca'),1::bigint,'brand counts include historical scope') from responses where label='lexical';
select is((select page->'groups' from responses where label='empty'),(select page->'groups' from responses where label='lexical'),'empty and broad lexical groups are identical');
select is((select page->'groups' from responses where label='geo'),(select page->'groups' from responses where label='lexical'),'geography filter preserves the full selected set');
select is(pg_temp.facet_count(page,'kind','process'),1::bigint,'single-brand scope includes only its historical Process') from responses where label='scope';
select is(pg_temp.facet_count(page,'kind','flow'),0::bigint,'single-brand scope cannot leak Flow') from responses where label='scope';
select is(pg_temp.facet_count(page,'kind','process'),2::bigint,'year filter retains both qualifying Process versions') from responses where label='year';
select is(pg_temp.facet_count(page,'kind','flow'),0::bigint,'year filter excludes null Flow year') from responses where label='year';
select is(pg_temp.facet_count(page,'referenceYear','2024'),2::bigint,'year facet text and count remain canonical') from responses where label='lexical';
select is(pg_temp.facet_count(page,'kind','process'),2::bigint,'CAS-shaped all-kind query retains ordinary Process text matches') from responses where label='cas';
select is(pg_temp.facet_count(page,'kind','flow'),1::bigint,'CAS-shaped Flow path retains exact CAS matches') from responses where label='cas';
select is(pg_temp.facet_count(page,'kind','process'),2::bigint,'UUID retains every matching exact version') from responses where label='uuid';
select is(pg_temp.facet_count(page,'kind','flow'),0::bigint,'UUID does not broaden to another kind') from responses where label='uuid';
select is(pg_temp.facet_count(page,'kind','process'),1::bigint,'percent and underscore remain literal characters') from responses where label='literal';
select is(pg_temp.facet_count(page,'kind','process'),0::bigint,'empty deployment scope cannot expose Process facts') from responses where label='none';
select is(page->'totals','{"process":2,"flow":1}'::jsonb,'Process navigation totals retain both kinds') from responses where label='nav';
select is((page#>>'{parent,count}')::integer,2,'Process parent count excludes Flow but preserves history') from responses where label='nav';
select throws_ok($q$select * from private.display_catalog_facet_rows_v1$q$,'42501',null,'anonymous direct facet rows remain closed');
select throws_ok($q$select * from private.display_navigation_versions_v1$q$,'42501',null,'anonymous direct navigation rows remain closed');
reset role;
-- Demand-specific readers preserve complete legacy branches and exact version totals.
create function pg_temp.check_demand_reads() returns setof text language plpgsql as $$
declare scope text[]; k text; q text; d text; f jsonb; old_page jsonb; new_page jsonb; parent text;
begin
 foreach scope slice 1 in array array[array['tiangong_lca'],array['bafu'],array['worldsteel']] loop
  return next is(api.portal_catalog_totals_v1(scope)->'totals',
    api.portal_navigation_v2(scope,'all')->'totals','totals-only equals complete exact-version totals');
  foreach k in array array['process','flow','all'] loop
   foreach q in array array['','shared864','%_','50-00-0','absent935'] loop
    foreach d in array array['classification','geography'] loop
     foreach f in array array['{}'::jsonb,'{"geography":"CN"}'::jsonb,'{"brand":"bafu"}'::jsonb] loop
      parent:=case when d='geography' then 'geo:cn' else case when k='process' then 'class:isic' else 'class:cpc' end end;
      old_page:=api.portal_navigation_v2(scope,k,q,f,d,parent,null,1);
      new_page:=api.portal_navigation_branches_v1(scope,k,q,f,d,parent,null,1);
      return next is(new_page-'schemaVersion',old_page-'schemaVersion'-'totals','branch payload preserves nodes, parent, ancestors and cursor');
      return next ok(not new_page ? 'totals','branch DTO contains no discarded totals');
      if old_page->>'nextCursor' is not null then
       return next is(api.portal_navigation_branches_v1(scope,k,q,f,d,parent,old_page->>'nextCursor',1)-'schemaVersion',
         api.portal_navigation_v2(scope,k,q,f,d,parent,old_page->>'nextCursor',1)-'schemaVersion'-'totals',
         'predecessor cursor resumes the same branch');
      end if;
     end loop;
    end loop;
   end loop;
  end loop;
 end loop;
end;
$$;
create temp table prepared_totals(scope text,page jsonb);
grant select,insert on prepared_totals to anon;
grant execute on function pg_temp.check_demand_reads() to anon;
set local role anon;
select * from pg_temp.check_demand_reads();
select is(api.portal_catalog_totals_v1(array['bafu','tiangong_lca'])->'totals','{"process":2,"flow":1}'::jsonb,'totals count historical versions, not latest datasets');
select is(api.portal_catalog_totals_v1(array['tiangong_lca'])->'schemaVersion','"portal.public-catalog-totals.v1"'::jsonb,'totals schema is explicit');
select throws_ok($$select api.portal_catalog_totals_v1(array['unknown'])$$,'22023','invalid portal request','unknown deployment scope rejected');
select throws_ok($$select api.portal_navigation_branches_v1(array['tiangong_lca'],'all','','{}','classification','invalid-node')$$,'22023','invalid portal request','branch validation stays closed');
prepare portal935_totals(text[]) as insert into prepared_totals select $1[1],api.portal_catalog_totals_v1($1)->'totals';
execute portal935_totals(array['tiangong_lca']);
execute portal935_totals(array['bafu']);
deallocate portal935_totals;
select is((select page from prepared_totals where scope='tiangong_lca'),'{"process":1,"flow":0}'::jsonb,'prepared totals retain first deployment scope');
select is((select page from prepared_totals where scope='bafu'),'{"process":1,"flow":1}'::jsonb,'prepared totals do not reuse previous deployment visibility');
reset role;
select ok(not has_function_privilege('service_role','api.portal_catalog_totals_v1(text[])','EXECUTE'),'totals closed to service role');
select ok(not has_function_privilege('anon','private.display_navigation_impl_v1(text,text,jsonb,text,text,text,integer,text,boolean)','EXECUTE'),'shared navigation kernel remains private');
select is((select count(*) from private.api_capability_grants where routine_identity in (
 'api.portal_catalog_totals_v1(text[])','api.portal_navigation_branches_v1(text[], text, text, jsonb, text, text, text, integer)')
 and allow_anon and allow_authenticated and not allow_service_role),2::bigint,'both additive APIs have exact public capability admission');

-- Source and visibility writers must keep the new read path current.
update public.processes set json=pg_temp.portal_versions_process_payload('Changed864 name','01.00.000')
where id='86400000-0000-4000-8000-000000000101' and version='01.00.000';
set local role anon;
select is(pg_temp.facet_count(api.portal_facets_v4(array['bafu','tiangong_lca'],'all','shared864'),'kind','process'),1::bigint,'source update immediately removes old lexical match');
select is(pg_temp.facet_count(api.portal_facets_v4(array['tiangong_lca'],'all','changed864'),'kind','process'),1::bigint,'source update immediately adds new lexical match');
reset role;
update private.dataset_display_settings set is_visible=false
where dataset_kind='process' and dataset_id='86400000-0000-4000-8000-000000000101' and dataset_version='02.00.000';
set local role anon;
select is(pg_temp.facet_count(api.portal_facets_v4(array['bafu','tiangong_lca'],'all','shared864'),'kind','process'),0::bigint,'withdrawal immediately removes the remaining Process');
select is(api.portal_navigation_v2(array['bafu','tiangong_lca'],'all','shared864','{}','geography')->'totals','{"process":0,"flow":1}'::jsonb,'navigation observes the same withdrawal');
select is(api.portal_catalog_totals_v1(array['bafu','tiangong_lca'])->'totals','{"process":1,"flow":1}'::jsonb,'totals observe visibility withdrawal immediately');
select is(api.portal_navigation_branches_v1(array['bafu','tiangong_lca'],'process','shared864','{}','geography','geo:cn')#>'{parent,count}','0'::jsonb,'branch-only observes source updates and withdrawal');
reset role;
select * from finish();
rollback;
