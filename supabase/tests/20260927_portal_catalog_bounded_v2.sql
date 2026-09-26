-- Legacy V2 ranking, cursor, role and real-writer visibility regression.
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
('733c0000-0000-4000-8000-000000000001','01.00.000',pg_temp.catalog_payload('Zulu','CN-AH-HFE','[{"@classId":"A"},{"@classId":"01"}]','2018'),100,'2020-01-01'),
('733c0000-0000-4000-8000-000000000001','01.00.001',pg_temp.catalog_payload('Alpha','HF-AH-CN','[{"@classId":"A"},{"@classId":"01"}]','2024'),200,'2023-01-01'),
('733c0000-0000-4000-8000-000000000002','01.00.000',pg_temp.catalog_payload('Beta','CN-AH','[{"@classId":"A"}]','2022'),100,'2022-01-01'),
('733c0000-0000-4000-8000-000000000003','01.00.000',pg_temp.catalog_payload('Gamma','US','[{"@classId":"A"}]','2020'),100,'2024-01-01'),
('733c0000-0000-4000-8000-000000000004','01.00.000',pg_temp.catalog_payload('Omega','CN','[{"@classId":"A"}]','2021'),100,'2021-01-01'),
('733c0000-0000-4000-8000-000000000005','01.00.000',pg_temp.catalog_payload('Alpha','CN','[{"@classId":"A"}]','2019'),100,'2019-01-01'),
('733c0000-0000-4000-8000-000000000009','01.00.000',pg_temp.catalog_payload('Private','CN','[{"@classId":"A"}]','2026'),20,'2026-01-01');
insert into public.flows(id,version,json,state_code,modified_at) values
('733c0000-0000-4000-8000-000000000006','01.00.000',pg_temp.catalog_payload('FlowZ','CN','[{"@classId":"0"},{"@classId":"01"}]','2018',true),100,'2020-01-01'),
('733c0000-0000-4000-8000-000000000006','01.00.001',pg_temp.catalog_payload('FlowA','CN','[{"@classId":"0"},{"@classId":"01"}]','2024',true),200,'2023-01-01'),
('733c0000-0000-4000-8000-000000000007','01.00.000',pg_temp.catalog_payload('FlowB','US','[{"@classId":"0"}]','2021',true),100,'2021-01-01');
set constraints all immediate;

create temp table legacy_results(label text primary key,payload jsonb);
grant select,insert on legacy_results to anon,portal_public_executor,api_internal_executor;
set local role anon;
insert into legacy_results values
('empty',api.portal_search_processes_v2('','{}','relevance',null,50)),
('geo',api.portal_search_processes_v2('','{"geography":"cn-ah"}')),
('exact_name',api.portal_search_processes_v2('alpha')),
('class_and_name',api.portal_search_processes_v2('a')),
('identifier',api.portal_search_processes_v2('733c0000-0000-4000-8000-000000000001')),
('hidden',api.portal_search_processes_v2('733c0000-0000-4000-8000-000000000009')),
('flow_text',api.portal_search_flows_v2('flow')),
('flow_filtered',api.portal_search_flows_v2('flow','{"geography":"cn","referenceYearFrom":2020}')),
('facets_filtered',api.portal_facets_v2('all','flow','{"geography":"cn"}')),
('name1',api.portal_search_processes_v2('','{}','name_asc',null,2)),
('date1',api.portal_search_processes_v2('','{}','modified_desc',null,2));
insert into legacy_results select 'name2',api.portal_search_processes_v2('','{}','name_asc',payload->>'nextCursor',2) from legacy_results where label='name1';
insert into legacy_results select 'date2',api.portal_search_processes_v2('','{}','modified_desc',payload->>'nextCursor',2) from legacy_results where label='date1';
reset role;
select is((select jsonb_array_length(payload->'items') from legacy_results where label='empty'),6,'blank V2 retains all public historical versions');
select is((select jsonb_array_length(payload->'items') from legacy_results where label='hidden'),0,'nonpublic source state stays invisible');
select is((select payload#>>'{items,0,key,id}' from legacy_results where label='geo'),'733c0000-0000-4000-8000-000000000002','classic exact geography uses the same authored code');
select is((select payload#>'{items,0,match,reasonCodes}' from legacy_results where label='geo'),'["cas"]'::jsonb,'filtered-empty CAS metadata remains deliberately unchanged');
select is((select payload#>'{items,0,match,reasonCodes}' from legacy_results where label='empty'),'[]'::jsonb,'unfiltered empty remains lexical');
select is((select jsonb_array_length(payload->'items') from legacy_results where label='exact_name'),2,'exact names retain all matching public identities');
select is((select (payload#>>'{items,0,match,score}')::numeric from legacy_results where label='exact_name'),0.95::numeric,'exact-name score remains 0.95');
select is((select (payload#>>'{items,0,match,score}')::numeric from legacy_results where label='identifier'),1::numeric,'exact id remains the highest score');
select is((select payload#>>'{items,0,key,version}' from legacy_results where label='identifier'),'01.00.001','id ties keep descending exact version');
select is((select (payload#>>'{items,0,match,score}')::numeric from legacy_results where label='class_and_name'),0.92::numeric,'classification exact score is retained');
select is((select payload#>'{items,0,match,reasonCodes}' from legacy_results where label='class_and_name'),'["name"]'::jsonb,'display reasons preserve name-contains precedence over classification exact');
select is((select payload#>>'{items,0,match,kind}' from legacy_results where label='class_and_name'),'lexical','display kind derives from retained reasons rather than inventing rank semantics');
select is((select payload#>'{items,1,match,reasonCodes}' from legacy_results where label='class_and_name'),'["classification"]'::jsonb,'classification reason remains when the name does not contain the query');
select is((select jsonb_array_length(payload->'items') from legacy_results where label='flow_text'),3,'Flow text keeps historical versions');
select is((select (payload#>>'{items,0,match,score}')::numeric from legacy_results where label='flow_text'),0.70::numeric,'non-exact lexical score remains 0.70');
select is((select jsonb_array_length(payload->'items') from legacy_results where label='flow_filtered'),0,'missing authored Flow reference years remain ineligible for year filters');
select is((select pg_temp.facet_count(payload,'kind','flow') from legacy_results where label='facets_filtered'),2::bigint,'filtered V2 facet counts exact matching versions');
select is((select payload#>>'{items,0,key,id}' from legacy_results where label='name2'),'733c0000-0000-4000-8000-000000000002','name cursor tie boundary is preserved');
select is((select payload#>>'{items,0,key,id}' from legacy_results where label='date2'),'733c0000-0000-4000-8000-000000000002','date cursor boundary is preserved');

-- Compare both existing execution principals; the definer owner is the public
-- reader and explicit visibility predicates stay active in both invocations.
set local role api_internal_executor;
insert into legacy_results values ('role_internal',private.catalog_portal_search_v2_impl('process','a','{}','relevance',null,null,null,50,'role-fixture'));
set local role portal_public_executor;
insert into legacy_results values ('role_public',private.catalog_portal_search_v2_impl('process','a','{}','relevance',null,null,null,50,'role-fixture'));
reset role;
select is((select payload from legacy_results where label='role_internal'),(select payload from legacy_results where label='role_public'),'internal/public callers receive byte-identical visible kernels');
select is((select p.proowner::regrole::text from pg_proc p where p.oid='private.catalog_portal_search_v2_impl(text,text,jsonb,text,text,uuid,text,integer,text)'::regprocedure),'portal_public_executor','V2 read owner aligns with the existing public reader');
select ok(has_function_privilege('api_internal_executor','private.catalog_portal_search_v2_impl(text,text,jsonb,text,text,uuid,text,integer,text)','execute'),'prior internal execute authority is retained');
select ok(not has_function_privilege('anon','private.catalog_portal_search_v2_impl(text,text,jsonb,text,text,uuid,text,integer,text)','execute'),'anonymous callers cannot invoke the internal kernel');
select ok(not has_table_privilege('anon','private.portal_catalog_search_rows_v2','select'),'private card storage remains closed');
select ok(not has_schema_privilege('portal_public_executor','private','create'),'temporary DDL schema privilege is restored');
select ok(not pg_has_role('api_internal_executor','portal_public_executor','member'),'temporary migration role membership is restored');
select throws_ok($q$insert into private.portal_catalog_search_rows_v2 select dataset_kind,'733c0000-0000-4000-8000-000000000010'::uuid,version,0,modified_at,card,document,projection_contract_version from private.portal_catalog_search_rows_v2 limit 1$q$,'23514',null,'storage itself rejects a nonpublic orphan projection');

select throws_ok($q$insert into private.portal_catalog_search_rows_v2 select dataset_kind,'733c0000-0000-4000-8000-000000000011'::uuid,version,state_code,modified_at,'[]'::jsonb,''::text,projection_contract_version from private.portal_catalog_search_rows_v2 limit 1$q$,'23514',null,'storage rejects non-object cards before record decoding is reachable');

update public.processes set modified_at='2027-01-01' where id='733c0000-0000-4000-8000-000000000001' and version='01.00.000';
set local role anon;
insert into legacy_results values ('after_update',api.portal_search_processes_v2('','{}','modified_desc',null,1));
reset role;
select is((select payload#>>'{items,0,key,version}' from legacy_results where label='after_update'),'01.00.000','real writer updates affect V2 date paging immediately');
update public.processes set state_code=20 where id='733c0000-0000-4000-8000-000000000002';
set local role anon;
insert into legacy_results values ('after_withdrawal',api.portal_search_processes_v2('','{"geography":"cn-ah"}')),
 ('facet_after_withdrawal',api.portal_facets_v2('process','','{"geography":"cn-ah"}'));
reset role;
select is((select jsonb_array_length(payload->'items') from legacy_results where label='after_withdrawal'),0,'real withdrawal is invisible to V2 in the same transaction');
select is((select payload->'groups' from legacy_results where label='facet_after_withdrawal'),'[]'::jsonb,'real withdrawal removes the matching V2 facet values');
select lives_ok('select private.assert_portal_navigation_projection_v1()','immutable writer/forced-RLS derivation guard remains intact');
select * from finish();
rollback;
