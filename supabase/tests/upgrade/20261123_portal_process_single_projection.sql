-- psql on an empty, disposable database-engine-1004 predecessor. This script
-- commits synthetic versions and the actual migration to check deferred FKs.
\set ON_ERROR_STOP on
select :'HOST' = '127.0.0.1' and :'PORT' = '59422' and current_database()='postgres'
  and (select max(version) from supabase_migrations.schema_migrations)='20261120030000'
  and not exists (select from public.processes) and not exists (select from public.flows) as owned_prefix \gset
\if :owned_prefix
\else
  \echo 'Expected empty #1004 local precursor on loopback port 59422'
  \quit 3
\endif

create function pg_temp.check_that(ok boolean, test text) returns void language plpgsql as $$
begin
  if ok is not true then raise exception '%',test; end if;
  raise notice 'PASS %',test;
end $$;

begin;
-- Skip remote calls from unrelated derivative jobs. Restore their function
-- before committing. Keep all Portal source/child triggers enabled.
create temp table edge_stub as select pg_get_functiondef(
  'util.invoke_edge_function(text,jsonb,integer)'::regprocedure) as definition;
create or replace function util.invoke_edge_function(name text,body jsonb,timeout_milliseconds integer default 300000)
returns void language plpgsql security definer set search_path='' as $$begin return; end$$;
create function pg_temp.payload(kind text, route text, geo text) returns jsonb language sql as $$
  select jsonb_build_object(kind||'DataSet',jsonb_build_object(kind||'Information',jsonb_build_object(
    'dataSetInformation',jsonb_build_object('name',jsonb_build_object(
      'baseName','Catalog1004','treatmentStandardsRoutes',route,'mixAndLocationTypes','Mix','functionalUnitFlowProperties','Unit')),
    'geography',jsonb_build_object(case kind when 'flow' then 'locationOfSupply' else 'locationOfOperationSupplyOrProduction' end,
      jsonb_build_object('@location',geo))),
    'administrativeInformation',jsonb_build_object('publicationAndOwnership',jsonb_build_object(
      'common:licenseType','Free of charge for all users and uses'))))
$$;
insert into public.processes(id,version,state_code,json)
select '10040000-0000-4000-8000-000000000001',v,100,pg_temp.payload('process','Route1004','CN')
from unnest(array['01.00.000','02.00.000']) v;
insert into public.flows(id,version,state_code,json)
select '10040000-0000-4000-8000-000000000001',v,200,pg_temp.payload('flow','Flow1004','US')
from unnest(array['01.00.000','02.00.000']) v;
insert into public.processes(id,version,state_code,json) values
 ('10040000-0000-4000-8000-000000000002','01.00.000',0,pg_temp.payload('process','Draft1004','CN'));
do $$begin execute (select definition from edge_stub); end$$;
commit;

create temp view current_pages as select
  api.portal_search_processes_v2('Catalog1004','{}','name_asc',null,1) as process,
  api.portal_search_flows_v2('Catalog1004','{}','name_asc',null,1) as flow,
  api.portal_search_processes_v1('Route1004') as latest,
  api.portal_facets_v2('all','Catalog1004') as facets,
  api.portal_navigation_v1('all','','{}','geography','geo:cn') as nav,
  api.portal_sitemap_manifest_v1() as sitemap;
create temp table before_pages as table current_pages;
create temp view continued as select
  api.portal_search_processes_v2('Catalog1004','{}','name_asc',process->>'nextCursor',1) as process,
  api.portal_search_flows_v2('Catalog1004','{}','name_asc',flow->>'nextCursor',1) as flow from before_pages;
create temp table before_continued as table continued;
create temp view children as
  select dataset_kind,id,version,to_jsonb(f)-'flow_version'-'process_version' as facet
  from private.portal_catalog_facet_rows_v1 f;
create temp table before_children as table children;
create temp table before_members as table private.portal_navigation_membership_v1;
create temp table before_sitemap as table private.portal_sitemap_rows_v1;
create temp table before_flow as select * from private.portal_catalog_search_rows_v1 where dataset_kind='flow';
select pg_temp.check_that((select count(*)=2 from private.portal_catalog_search_rows_v1 where dataset_kind='process')
  and (select count(*)=2 from private.portal_catalog_search_rows_v2)
  and (select process->>'nextCursor' is not null and flow->>'nextCursor' is not null from before_pages),
  'populated predecessor has duplicate Process rows and usable Process and Flow cursors');

\ir ../../migrations/20261123034022_portal_process_single_search_projection.sql

select pg_temp.check_that(not exists (table current_pages except table before_pages)
  and not exists (table continued except table before_continued), 'complete RPC envelopes and pre-upgrade continuations agree');
select pg_temp.check_that(not exists (table before_children except table children)
  and not exists (table children except table before_children)
  and not exists (table before_members except table private.portal_navigation_membership_v1)
  and not exists (table private.portal_navigation_membership_v1 except table before_members)
  and not exists (table before_sitemap except table private.portal_sitemap_rows_v1)
  and not exists (table private.portal_sitemap_rows_v1 except table before_sitemap),
  'exact-version facets, navigation memberships and sitemap survive old-parent deletion');
select pg_temp.check_that(not exists (table private.portal_catalog_search_rows_v1 except table before_flow)
  and not exists (table before_flow except table private.portal_catalog_search_rows_v1)
  and not exists (select from private.portal_catalog_character_rows_v1 where dataset_kind='process'),
  'V1 retains byte-equivalent Flow records and zero Process parents or character children');

-- Each change commits through the real source writer.
update public.processes set state_code=200 where id='10040000-0000-4000-8000-000000000002';
select pg_temp.check_that((select count(*)=1 from private.portal_catalog_search_rows_v2 where id='10040000-0000-4000-8000-000000000002')
  and api.portal_search_processes_v2('Draft1004')#>>'{items,0,names,0,value}'='Catalog1004; Draft1004; Mix; Unit',
  'publication writes the composite card and makes it searchable');
begin;
create or replace function util.invoke_edge_function(name text,body jsonb,timeout_milliseconds integer default 300000)
returns void language plpgsql security definer set search_path='' as $$begin return; end$$;
update public.processes set json=pg_temp.payload('process','Changed1004','US')
where id='10040000-0000-4000-8000-000000000002';
do $$begin execute (select definition from edge_stub); end$$;
commit;
select pg_temp.check_that(jsonb_array_length(api.portal_search_processes_v2('Draft1004')->'items')=0
  and jsonb_array_length(api.portal_search_processes_v2('Changed1004','{"geography":"us"}')->'items')=1
  and (api.portal_navigation_v1('process','Changed1004','{}','geography','geo:us')#>>'{parent,count}')::int=1
  and exists (select from private.portal_sitemap_rows_v1 s join public.processes p on p.id=s.id and p.version::text=s.version
              where p.id='10040000-0000-4000-8000-000000000002' and p.modified_at=s.modified_at),
  'renamed and reclassified version reaches search, filter, sitemap and navigation');
update public.processes set state_code=0 where id='10040000-0000-4000-8000-000000000002';
select pg_temp.check_that(jsonb_array_length(api.portal_search_processes_v2('Changed1004')->'items')=0
  and not exists (select from private.portal_catalog_facet_rows_v1 where id='10040000-0000-4000-8000-000000000002')
  and not exists (select from private.portal_navigation_versions_v1 where id='10040000-0000-4000-8000-000000000002')
  and not exists (select from private.portal_sitemap_rows_v1 where id='10040000-0000-4000-8000-000000000002'),
  'withdrawal removes all searchable and navigable records at commit');
