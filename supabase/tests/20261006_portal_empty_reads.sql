-- Database #783: real writers and anonymous empty-read/cursor boundaries.
-- Real projection-writer and anonymous API regression, always rolled back.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public;
select no_plan();
grant portal_public_executor,api_internal_executor to postgres;

create function pg_temp.nav_payload(p_name text,p_geo text,p_classes jsonb,p_flow boolean default false)
returns jsonb language sql immutable as $$
 select jsonb_build_object(case when p_flow then 'flowDataSet' else 'processDataSet' end,
   jsonb_build_object(case when p_flow then 'flowInformation' else 'processInformation' end,
     jsonb_build_object('dataSetInformation',jsonb_build_object(
       'name',jsonb_build_object('baseName',jsonb_build_object('@xml:lang','en','#text',p_name)),
       'classificationInformation',jsonb_build_object('common:classification',jsonb_build_object('common:class',p_classes))),
       'time',jsonb_build_object('common:referenceYear','2024'),
       'geography',jsonb_build_object(case when p_flow then 'locationOfSupply' else 'locationOfOperationSupplyOrProduction' end,
         jsonb_build_object('@location',p_geo))),
     'administrativeInformation',jsonb_build_object('publicationAndOwnership',jsonb_build_object(
       'common:licenseType','Free of charge for all users and uses'))))
$$;

do $$begin
 if exists(select 1 from private.portal_navigation_versions_v1)
 or exists(select 1 from private.portal_catalog_facet_rows_v1) then
  raise exception 'Database #783 focused proof requires an empty reset local fixture';
 end if;
end $$;

-- Suppress unrelated authoring, webhooks and jobs only in this rollback fixture.
-- Keep all existing public projection writers and ALL private child triggers.
alter table public.processes disable trigger user;
alter table public.processes enable trigger portal_catalog_projection_content_sync_v2;
alter table public.flows disable trigger user;
alter table public.flows enable trigger portal_catalog_projection_content_sync_v1;
insert into public.processes(id,version,json,state_code,modified_at) values
('78300000-0000-4000-8000-000000000001','01.00.000',pg_temp.nav_payload('NavAlpha783','CN-AH-HFE','[{"@classId":"A"},{"@classId":"01"},{"@classId":"01"}]'),100,'2026-09-19'),
('78300000-0000-4000-8000-000000000001','01.00.001',pg_temp.nav_payload('NavAlpha783','HF-AH-CN','[{"@classId":"A"},{"@classId":"01"}]'),200,'2026-09-19'),
('78300000-0000-4000-8000-000000000002','01.00.000',pg_temp.nav_payload('NavBeta783','CN-AH','[{"@classId":"A"}]'),100,'2026-09-19'),
('78300000-0000-4000-8000-000000000003','01.00.000',pg_temp.nav_payload('NavNation783','CN','[{"@classId":"A"}]'),100,'2026-09-19'),
('78300000-0000-4000-8000-000000000004','01.00.000',pg_temp.nav_payload('NavUnknown783','CN-AH-ZX','[{"@classId":"custom-783"}]'),100,'2026-09-19'),
('78300000-0000-4000-8000-000000000009','01.00.000',pg_temp.nav_payload('NavPrivate783','CN','[{"@classId":"A"}]'),20,'2026-09-19');
insert into public.flows(id,version,json,state_code,modified_at) values
('78300000-0000-4000-8000-000000000005','01.00.000',pg_temp.nav_payload('NavFlow783','US','[{"@classId":"0"},{"@classId":"01"}]',true),100,'2026-09-19');
set constraints all immediate;


create temp table empty_read_results(label text primary key,payload jsonb);
grant select,insert on empty_read_results to anon;
set local role anon;
insert into empty_read_results values
 ('navigation-all',api.portal_navigation_v1('all','','{}','geography',null,null,100)),
 ('navigation-process',api.portal_navigation_v1('process','','{}','classification','class:isic',null,100)),
 ('navigation-flow',api.portal_navigation_v1('flow','','{}','classification','class:cpc',null,100)),
 ('navigation-normalized',api.portal_navigation_v1('process','  ',null,'classification','class:isic',null,100)),
 ('navigation-filtered',api.portal_navigation_v1('all','','{"geographyNodeId":"geo:cn-ah"}','geography','geo:cn-ah',null,100)),
 ('navigation-zero',api.portal_navigation_v1('all','absent-783','{}','geography','geo:cn',null,100)),
 ('facets-all',api.portal_facets_v3('all','','{}')),
 ('facets-process',api.portal_facets_v3('process','','{}')),
 ('facets-flow',api.portal_facets_v3('flow','','{}')),
 ('facets-v2',api.portal_facets_v2('all','','{}'));
insert into empty_read_results select 'navigation-page2',api.portal_navigation_v1('all','','{}','geography',null,payload->>'nextCursor',100) from empty_read_results where label='navigation-all';
reset role;
select is((select count(distinct payload->'totals') from empty_read_results where label in('navigation-all','navigation-process','navigation-flow')),1::bigint,'empty totals preserve both kinds independently of the selected branch');
select is((select payload->'totals' from empty_read_results where label='navigation-all'),'{"process":5,"flow":1}'::jsonb,'empty totals count historical public versions and exclude private versions');
select is((select payload from empty_read_results where label='navigation-normalized'),(select payload from empty_read_results where label='navigation-process'),'whitespace query and null filters retain canonical empty behavior');
select is((select payload->'totals' from empty_read_results where label='navigation-filtered'),'{"process":4,"flow":0}'::jsonb,'nonempty filters retain matched-version totals');
select is((select payload->'totals' from empty_read_results where label='navigation-zero'),'{"process":0,"flow":0}'::jsonb,'lexical no-match retains zero totals');
select is((select count(distinct n->>'nodeId') from empty_read_results cross join lateral jsonb_array_elements(payload->'nodes') n where label in('navigation-all','navigation-page2')),200::bigint,'empty navigation cursor retains the complete next page without overlap');
select is((select payload->'groups' from empty_read_results where label='facets-v2'),(select payload->'groups' from empty_read_results where label='facets-all'),'V2 and V3 empty facets retain the same groups');
select is((select sum((v->>'count')::bigint)::bigint from empty_read_results cross join lateral jsonb_array_elements(payload->'groups') g cross join lateral jsonb_array_elements(g->'values') v where label='facets-all' and g->>'id'='kind'),6::bigint,'empty facets count the same complete public version universe');
select is((select (v->>'count')::integer from empty_read_results cross join lateral jsonb_array_elements(payload->'groups') g cross join lateral jsonb_array_elements(g->'values') v where label='facets-process' and g->>'id'='kind' and v->>'value'='process'),5,'Process facets retain historical versions');
select is((select (v->>'count')::integer from empty_read_results cross join lateral jsonb_array_elements(payload->'groups') g cross join lateral jsonb_array_elements(g->'values') v where label='facets-flow' and g->>'id'='kind' and v->>'value'='flow'),1,'Flow facets retain their kind filter');
select ok((select bool_and(c.relrowsecurity and c.relforcerowsecurity) from pg_class c where c.oid in('private.portal_navigation_versions_v1'::regclass,'private.portal_catalog_facet_rows_v1'::regclass)),'both direct readers remain forced-RLS relations');
select ok((select bool_and(r.rolname='portal_public_executor' and not r.rolbypassrls and not r.rolcanlogin and p.prosecdef and p.proconfig @> array['search_path=""','row_security=on','statement_timeout=8s','work_mem=32MB','plan_cache_mode=force_custom_plan']) from pg_proc p join pg_roles r on r.oid=p.proowner where p.oid in('private.portal_navigation_impl_v1(text,text,jsonb,text,text,text,integer,text)'::regprocedure,'private.catalog_portal_facets_empty_v2_impl(text,text)'::regprocedure)),'reader owners and bounded function settings remain unchanged');
select ok(not has_function_privilege('anon','private.portal_navigation_impl_v1(text,text,jsonb,text,text,text,integer,text)','execute') and not has_function_privilege('authenticated','private.catalog_portal_facets_empty_v2_impl(text,text)','execute'),'private implementations remain externally closed');
select * from finish();
rollback;
