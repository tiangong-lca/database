-- Public writer/cursor regression for the query-free narrow catalog readers.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public;
select no_plan();
grant portal_public_executor,api_internal_executor to postgres;

create function pg_temp.catalog_payload(n text,g text,classes jsonb,year text,f boolean default false)
returns jsonb language sql immutable as $$
select jsonb_build_object(case when f then 'flowDataSet' else 'processDataSet' end,
 jsonb_build_object(case when f then 'flowInformation' else 'processInformation' end,
  jsonb_build_object('dataSetInformation',jsonb_build_object(
    'name',jsonb_build_object('baseName',jsonb_build_object('@xml:lang','en','#text',n)),
    'classificationInformation',jsonb_build_object('common:classification',jsonb_build_object('common:class',classes))),
    'time',jsonb_build_object('common:referenceYear',year),
    'geography',jsonb_build_object(case when f then 'locationOfSupply' else 'locationOfOperationSupplyOrProduction' end,jsonb_build_object('@location',g))),
  'administrativeInformation',jsonb_build_object('publicationAndOwnership',jsonb_build_object('common:licenseType','Free of charge for all users and uses'))))
$$;
create function pg_temp.facet_count(payload jsonb,group_id text,facet_value text)
returns bigint language sql immutable as $$
select (v->>'count')::bigint from jsonb_array_elements(payload->'groups') g,
lateral jsonb_array_elements(g->'values') v where g->>'id'=group_id and v->>'value'=facet_value
$$;

-- Unrelated authoring/webhook jobs are suppressed only in this rollback fixture.
-- Both Process writers, the Flow writer, and all private children remain active.
alter table public.processes disable trigger user;
alter table public.processes enable trigger portal_catalog_projection_content_sync_v1;
alter table public.processes enable trigger portal_catalog_projection_content_sync_v2;
alter table public.flows disable trigger user;
alter table public.flows enable trigger portal_catalog_projection_content_sync_v1;
insert into public.processes(id,version,json,state_code,modified_at) values
('723c0000-0000-4000-8000-000000000001','01.00.000',pg_temp.catalog_payload('Zulu','CN-AH-HFE','[{"@classId":"A"},{"@classId":"01"}]','2018'),100,'2020-01-01'),
('723c0000-0000-4000-8000-000000000001','01.00.001',pg_temp.catalog_payload('Alpha','HF-AH-CN','[{"@classId":"A"},{"@classId":"01"}]','2024'),200,'2023-01-01'),
('723c0000-0000-4000-8000-000000000002','01.00.000',pg_temp.catalog_payload('Beta','CN-AH','[{"@classId":"A"}]','2022'),100,'2022-01-01'),
('723c0000-0000-4000-8000-000000000003','01.00.000',pg_temp.catalog_payload('Gamma','US','[{"@classId":"A"}]','2020'),100,'2024-01-01'),
('723c0000-0000-4000-8000-000000000004','01.00.000',pg_temp.catalog_payload('Omega','CN','[{"@classId":"A"}]','2021'),100,'2021-01-01'),
('723c0000-0000-4000-8000-000000000005','01.00.000',pg_temp.catalog_payload('Alpha','CN','[{"@classId":"A"}]','2019'),100,'2019-01-01'),
('723c0000-0000-4000-8000-000000000009','01.00.000',pg_temp.catalog_payload('Private','CN','[{"@classId":"A"}]','2026'),20,'2026-01-01');
insert into public.flows(id,version,json,state_code,modified_at) values
('723c0000-0000-4000-8000-000000000006','01.00.000',pg_temp.catalog_payload('FlowZ','CN','[{"@classId":"0"},{"@classId":"01"}]','2018',true),100,'2020-01-01'),
('723c0000-0000-4000-8000-000000000006','01.00.001',pg_temp.catalog_payload('FlowA','CN','[{"@classId":"0"},{"@classId":"01"}]','2024',true),200,'2023-01-01'),
('723c0000-0000-4000-8000-000000000007','01.00.000',pg_temp.catalog_payload('FlowB','US','[{"@classId":"0"}]','2021',true),100,'2021-01-01');
set constraints all immediate;
select is((select count(*) from private.portal_navigation_versions_v1 where id::text like '723c0000-%'),9::bigint,'real writers retain every public exact version and exclude private state');
select ok((select bool_and(f.modified_at=p.modified_at) from private.portal_catalog_facet_rows_v1 f join private.portal_catalog_search_rows_v2 p using(dataset_kind,id,version) where p.id::text like '723c0000-%'),'facet and composite Process timestamps agree after real writer insertion');

create temp table bounded_results(label text primary key,payload jsonb);
grant select,insert on bounded_results to anon;
set local role anon;
insert into bounded_results values
('cn',api.portal_search_processes_v3('','{"geographyNodeId":"geo:cn"}')),
('direct',api.portal_search_processes_v3('','{"geographyNodeId":"geo:cn-ah","geographyScope":"direct"}')),
('intersection',api.portal_search_processes_v3('','{"geographyNodeId":"geo:cn","classificationNodeId":"class:isic:0","classificationScope":"direct"}')),
('legacy_geo',api.portal_search_processes_v3('','{"geography":" CN-AH-HFE "}')),
('years',api.portal_search_processes_v3('','{"geographyNodeId":"geo:cn","referenceYearFrom":2020,"referenceYearTo":2022}')),
('name1',api.portal_search_processes_v3('','{}','name_asc',null,2)),
('modified1',api.portal_search_processes_v3('','{}','modified_desc',null,2)),
('history1',api.portal_search_processes_v3('','{"geographyNodeId":"geo:cn-ah"}','relevance',null,1)),
('facets_cn',api.portal_facets_v3('all','','{"geographyNodeId":"geo:cn"}')),
('facets_alias',api.portal_facets_v3('process','','{"geographyNodeId":"geo:cn-ah-hfe"}')),
('facets_none',api.portal_facets_v3('all','','{"source":"absent-723"}')),
('nav_cn',api.portal_navigation_v1('all','','{}','geography','geo:cn',null,500)),
('nav_direct',api.portal_navigation_v1('process','','{"geographyNodeId":"geo:cn-ah","geographyScope":"direct"}','classification','class:isic',null,100)),
('hidden',api.portal_search_processes_v3('723c0000-0000-4000-8000-000000000009'));
insert into bounded_results select 'name2',api.portal_search_processes_v3('','{}','name_asc',payload->>'nextCursor',2) from bounded_results where label='name1';
insert into bounded_results select 'modified2',api.portal_search_processes_v3('','{}','modified_desc',payload->>'nextCursor',2) from bounded_results where label='modified1';
insert into bounded_results select 'history2',api.portal_search_processes_v3('','{"geographyNodeId":"geo:cn-ah"}','relevance',payload->>'nextCursor',1) from bounded_results where label='history1';
reset role;
select is((select jsonb_array_length(payload->'items') from bounded_results where label='cn'),5,'empty-query subtree search retains historical versions and national-only records');
select is((select payload#>>'{items,0,key,id}' from bounded_results where label='direct'),'723c0000-0000-4000-8000-000000000002','direct province filter excludes cities and national-only placements');
select is((select jsonb_array_length(payload->'items') from bounded_results where label='intersection'),3,'classification direct and geography subtree combine as an intersection');
select is((select jsonb_array_length(payload->'items') from bounded_results where label='legacy_geo'),1,'legacy exact geography keeps authored alias identity rather than node equivalence');
select is((select jsonb_array_length(payload->'items') from bounded_results where label='years'),2,'reference-year bounds apply before ordering and paging');
select is((select payload#>>'{items,0,key,version}' from bounded_results where label='history1'),'01.00.001','relevance begins at the newer matched version');
select is((select payload#>>'{items,0,key,version}' from bounded_results where label='history2'),'01.00.000','cursor continuation retains the older matched version of the same id');
select is((select payload#>>'{items,0,key,id}' from bounded_results where label='name1'),'723c0000-0000-4000-8000-000000000001','name order selects Alpha');
select is((select payload#>>'{items,1,key,id}' from bounded_results where label='name1'),'723c0000-0000-4000-8000-000000000005','equal names use exact identity as the tie break');
select is((select payload#>>'{items,0,key,id}' from bounded_results where label='name2'),'723c0000-0000-4000-8000-000000000002','name cursor starts after both equal-name identities');
select is((select payload#>>'{items,0,key,id}' from bounded_results where label='modified1'),'723c0000-0000-4000-8000-000000000003','modified order uses synchronized source timestamps');
select is((select payload#>>'{items,0,key,id}' from bounded_results where label='modified2'),'723c0000-0000-4000-8000-000000000002','modified cursor selects the next older version');
select is((select pg_temp.facet_count(payload,'kind','process') from bounded_results where label='facets_cn'),5::bigint,'filtered facets count public Process versions, not only latest ids');
select is((select pg_temp.facet_count(payload,'kind','flow') from bounded_results where label='facets_cn'),2::bigint,'mixed-kind facets count Flow history independently');
select is((select pg_temp.facet_count(payload,'geography','hf-ah-cn') from bounded_results where label='facets_alias'),1::bigint,'facet labels preserve the normalized authored alias');
select is((select payload->'groups' from bounded_results where label='facets_none'),'[]'::jsonb,'no matches produce no synthetic zero facet groups');
select is((select (payload#>>'{parent,count}')::integer from bounded_results where label='nav_cn'),7,'unfiltered navigation counts the same exact public-version universe');
select is((select (payload#>>'{parent,directCount}')::integer from bounded_results where label='nav_cn'),4,'unfiltered navigation preserves direct placements');
select is((select (payload#>>'{totals,process}')::integer from bounded_results where label='nav_direct'),1,'filtered navigation totals preserve direct scope');
select is((select jsonb_array_length(payload->'items') from bounded_results where label='hidden'),0,'the existing nonempty UUID path does not disclose nonpublic data');
-- This cost-only rewrite preserves the retained filtered-empty-query tag.
select is((select payload#>'{items,0,match,reasonCodes}' from bounded_results where label='cn'),'["cas"]'::jsonb,'retained filtered-empty match metadata is unchanged');
select is((select payload#>'{items,0,match,reasonCodes}' from bounded_results where label='name1'),'[]'::jsonb,'unfiltered browse match metadata remains lexical');

-- The unnamed sentinel follows the database collation, so do not assume that
-- punctuation sorts after authored names. Prove visibility and complete paging.
update public.processes set json=jsonb_set(json,'{processDataSet,processInformation,dataSetInformation,name,baseName}','null'::jsonb)
where id='723c0000-0000-4000-8000-000000000004';
set local role anon;
with recursive pages(n,payload) as (
 select 1,api.portal_search_processes_v3('','{}','name_asc',null,1)
 union all
 select n+1,api.portal_search_processes_v3('','{}','name_asc',payload->>'nextCursor',1)
 from pages where payload->>'nextCursor' is not null and n<10
) insert into bounded_results select 'unnamed_pages',jsonb_agg(payload order by n) from pages;
reset role;
select is((select count(distinct (item#>>'{key,id}',item#>>'{key,version}')) from bounded_results,
lateral jsonb_array_elements(payload) page,lateral jsonb_array_elements(page->'items') item
where label='unnamed_pages'),6::bigint,'name cursor traverses every exact version once including an unnamed record');
select ok((select bool_or(item#>>'{key,id}'='723c0000-0000-4000-8000-000000000004' and item->'names'='[]'::jsonb)
from bounded_results,lateral jsonb_array_elements(payload) page,lateral jsonb_array_elements(page->'items') item
where label='unnamed_pages'),'name sorting does not invent a display name for the sentinel');

update public.processes set json=json,modified_at='2027-01-01' where id='723c0000-0000-4000-8000-000000000001' and version='01.00.000';
select ok((select f.modified_at=p.modified_at and f.modified_at='2027-01-01'::timestamptz from private.portal_catalog_facet_rows_v1 f join private.portal_catalog_search_rows_v2 p using(dataset_kind,id,version) where p.id='723c0000-0000-4000-8000-000000000001' and p.version='01.00.000'),'real updates synchronize the timestamp used by narrow paging');
set local role anon;
insert into bounded_results values('after_update',api.portal_search_processes_v3('','{}','modified_desc',null,1));
reset role;
select is((select payload#>>'{items,0,key,version}' from bounded_results where label='after_update'),'01.00.000','modified ordering immediately reflects source updates');
update public.processes set state_code=20 where id='723c0000-0000-4000-8000-000000000002';
set local role anon;
insert into bounded_results values('after_withdrawal',api.portal_search_processes_v3('','{"geographyNodeId":"geo:cn-ah","geographyScope":"direct"}'));
reset role;
select is((select jsonb_array_length(payload->'items') from bounded_results where label='after_withdrawal'),0,'withdrawal removes the version from narrow search in the same transaction');
select ok(not has_table_privilege('anon','private.portal_navigation_versions_v1','select'),'narrow storage remains closed to anon');
select ok(not has_function_privilege('anon','private.portal_navigation_matched_versions_v1(text,text,jsonb)','execute'),'internal matching helper remains closed to anon');
select lives_ok('select private.assert_portal_navigation_projection_v1()','immutable writer and forced-RLS derivation guard remains intact');
select * from finish();
rollback;
