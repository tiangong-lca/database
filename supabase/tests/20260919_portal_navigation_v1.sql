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

-- Suppress unrelated authoring, webhooks and jobs only in this rollback fixture.
-- Keep all existing public projection writers and ALL private child triggers.
alter table public.processes disable trigger user;
alter table public.processes enable trigger portal_catalog_projection_content_sync_v2;
alter table public.flows disable trigger user;
alter table public.flows enable trigger portal_catalog_projection_content_sync_v1;
insert into public.processes(id,version,json,state_code,modified_at) values
('65600000-0000-4000-8000-000000000001','01.00.000',pg_temp.nav_payload('NavAlpha656','CN-AH-HFE','[{"@classId":"A"},{"@classId":"01"},{"@classId":"01"}]'),100,'2026-09-19'),
('65600000-0000-4000-8000-000000000001','01.00.001',pg_temp.nav_payload('NavAlpha656','HF-AH-CN','[{"@classId":"A"},{"@classId":"01"}]'),200,'2026-09-19'),
('65600000-0000-4000-8000-000000000002','01.00.000',pg_temp.nav_payload('NavBeta656','CN-AH','[{"@classId":"A"}]'),100,'2026-09-19'),
('65600000-0000-4000-8000-000000000003','01.00.000',pg_temp.nav_payload('NavNation656','CN','[{"@classId":"A"}]'),100,'2026-09-19'),
('65600000-0000-4000-8000-000000000004','01.00.000',pg_temp.nav_payload('NavUnknown656','CN-AH-ZX','[{"@classId":"custom-656"}]'),100,'2026-09-19'),
('65600000-0000-4000-8000-000000000009','01.00.000',pg_temp.nav_payload('NavPrivate656','CN','[{"@classId":"A"}]'),20,'2026-09-19');
insert into public.flows(id,version,json,state_code,modified_at) values
('65600000-0000-4000-8000-000000000005','01.00.000',pg_temp.nav_payload('NavFlow656','US','[{"@classId":"0"},{"@classId":"01"}]',true),100,'2026-09-19');
set constraints all immediate;

select is((select count(*) from private.portal_navigation_versions_v1 where id::text like '65600000-%'),6::bigint,'both public kinds and historical versions are projected automatically');
select is((select count(*) from private.portal_navigation_versions_v1 where id='65600000-0000-4000-8000-000000000009'),0::bigint,'nonpublic state is never projected');
select is((select count(*) from private.portal_navigation_membership_v1 where id='65600000-0000-4000-8000-000000000001' and node_id='class:isic:0.0' and direct),2::bigint,'ILCD process classification resolves by kind; duplicates within a version collapse');
select is((select count(*) from private.portal_navigation_membership_v1 where id='65600000-0000-4000-8000-000000000001' and node_id='class:isic:0' and direct),0::bigint,'authored ancestors do not become direct placements when a descendant is present');
select is((select count(*) from private.portal_navigation_membership_v1 where id='65600000-0000-4000-8000-000000000005' and node_id='class:cpc:0.0' and direct),1::bigint,'same code 01 resolves to CPC for an ILCD Flow, not ISIC');
select is((select count(*) from private.portal_navigation_membership_v1 where id='65600000-0000-4000-8000-000000000001' and node_id='geo:cn-ah-hfe' and direct),2::bigint,'receipted legacy geography alias shares a node but retains two exact versions');
select is((select geography_code from private.portal_navigation_versions_v1 where id='65600000-0000-4000-8000-000000000001' and version='01.00.001'),'hf-ah-cn','original geography filter code is not rewritten');
select is((select parent_node_id from private.portal_navigation_node_v1 where code='CN-AH-ZX'),'geo:cn-ah','unknown city code remains under its verified province without a city boundary claim');
select ok(not has_table_privilege('anon','private.portal_navigation_membership_v1','select'),'anonymous callers cannot read membership storage');
select ok(not has_table_privilege('authenticated','private.portal_navigation_versions_v1','select'),'authenticated callers cannot read private narrow storage');
select ok(not has_function_privilege('anon','private.sync_portal_navigation_membership_v1(text,uuid,text,jsonb)','execute'),'projection writer is not externally executable');

create temp table nav_results(label text primary key,payload jsonb);
grant select,insert on nav_results to anon;
set local role anon;
insert into nav_results values
('china',api.portal_navigation_v1('process','nav','{}','geography','geo:cn',null,500)),
('anhui',api.portal_navigation_v1('process','nav','{}','geography','geo:cn-ah',null,500)),
('alpha',api.portal_navigation_v1('all','NavAlpha656','{}','geography','geo:cn',null,500)),
('absent',api.portal_navigation_v1('all','DoesNotExist656','{}','geography',null,null,500)),
('classification',api.portal_navigation_v1('process','nav','{}','classification','class:isic:0',null,500)),
('combined',api.portal_navigation_v1('process','nav','{"classificationNodeId":"class:isic:0","geographyNodeId":"geo:cn-ah","geographyScope":"direct"}','geography','geo:cn-ah',null,500)),
('search',api.portal_search_processes_v3('nav','{"classificationNodeId":"class:isic:0","geographyNodeId":"geo:cn-ah","geographyScope":"direct"}')),
('facets',api.portal_facets_v3('process','nav','{"classificationNodeId":"class:isic:0","geographyNodeId":"geo:cn-ah","geographyScope":"direct"}')),
('historical1',api.portal_search_processes_v3('NavAlpha656','{"geographyNodeId":"geo:cn"}','relevance',null,1)),
('v2',api.portal_search_processes_v2('NavAlpha656')),
('world1',api.portal_navigation_v1('all','','{}','geography',null,null,100));
insert into nav_results select 'historical2',api.portal_search_processes_v3('NavAlpha656','{"geographyNodeId":"geo:cn"}','relevance',payload->>'nextCursor',1) from nav_results where label='historical1';
insert into nav_results select 'world2',api.portal_navigation_v1('all','','{}','geography',null,payload->>'nextCursor',100) from nav_results where label='world1';
reset role;
select is((select (payload#>>'{parent,count}')::integer from nav_results where label='china'),5,'China includes descendants and national-only records, not nonpublic versions');
select is((select (payload#>>'{parent,directCount}')::integer from nav_results where label='china'),1,'national-only records are not distributed to provinces');
select is((select (payload#>>'{parent,count}')::integer from nav_results where label='anhui'),4,'province includes its city aliases and unresolved code');
select is((select (payload#>>'{parent,directCount}')::integer from nav_results where label='anhui'),1,'province direct count excludes city placements');
select is((select (payload#>>'{parent,count}')::integer from nav_results where label='alpha'),2,'navigation query matches only the two historical Alpha versions');
select is((select (payload#>>'{totals,process}')::integer from nav_results where label='alpha'),2,'kind totals use the query before aggregation');
select is((select (payload#>>'{totals,flow}')::integer from nav_results where label='china'),1,'a process branch still measures the flow total');
select is((select (payload#>>'{totals,process}')::integer from nav_results where label='absent'),0,'nonmatching query has zero process versions');
select is((select (payload#>>'{parent,count}')::integer from nav_results where label='classification'),4,'classification subtree deduplicates authored path members per exact version');
select is((select (payload#>>'{parent,directCount}')::integer from nav_results where label='classification'),2,'classification direct count includes only genuinely parent-level placements');
select is((select (payload#>>'{parent,count}')::integer from nav_results where label='combined'),1,'combined direct geography and subtree classification filter matches one version');
select is((select jsonb_array_length(payload->'items') from nav_results where label='search'),1,'V3 search matches the navigation count');
select is((select (vals.value->>'count')::integer from nav_results cross join lateral jsonb_array_elements(payload->'groups') g cross join lateral jsonb_array_elements(g->'values') vals(value) where label='facets' and g->>'id'='kind'),1,'V3 facets match the same constrained version universe');
select is((select count(distinct item#>>'{key,version}') from nav_results cross join lateral jsonb_array_elements(payload->'items') item where label in('historical1','historical2')),2::bigint,'keyset continuation preserves independent historical version matches');
select is((select jsonb_array_length(payload->'items') from nav_results where label='v2'),2,'existing V2 still retrieves both versions');
select is((select count(distinct n->>'nodeId') from nav_results cross join lateral jsonb_array_elements(payload->'nodes') n where label in('world1','world2')),200::bigint,'more than 100 geography nodes are reachable without duplication');
select ok((select bool_and(octet_length(payload::text)<=65536) from nav_results where payload->>'schemaVersion'='portal.public-navigation.v1'),'every navigation response respects 64 KiB');
select throws_ok($$select api.portal_navigation_v1('all','','{}','geography','class:isic',null,1)$$,'22023','invalid portal request','cross-dimension parent is rejected');
select throws_ok($$select api.portal_search_processes_v3('','{"geographyScope":"direct"}')$$,'22023','invalid portal request','orphan scope is rejected');
select throws_ok($$select api.portal_navigation_v1('all','','{"team_id":"x"}','geography',null,null,1)$$,'22023','invalid portal request','private scope filter is rejected');
select throws_ok($$select api.portal_navigation_v1('all','','{}','geography',null,null,501)$$,'22023','invalid portal request','unbounded page is rejected');
select throws_ok(format('select api.portal_search_processes_v3(%L,%L,%L,%L,1)','NavAlpha656','{"geographyNodeId":"geo:us"}','relevance',(select payload->>'nextCursor' from nav_results where label='historical1')),'22023','invalid portal request','search cursor cannot cross node scopes');

-- Real source updates exercise both public writers and private FK withdrawals.
update public.processes set state_code=20 where id='65600000-0000-4000-8000-000000000001' and version='01.00.001';
select is((select count(*) from private.portal_navigation_versions_v1 where id='65600000-0000-4000-8000-000000000001'),1::bigint,'withdrawal cascades narrow version facts');
select is((select count(*) from private.portal_navigation_membership_v1 where id='65600000-0000-4000-8000-000000000001' and version='01.00.001'),0::bigint,'withdrawal cascades every ancestor membership');
update public.processes set json=pg_temp.nav_payload('NavMoved656','CN-SD-JNA','[{"@classId":"B"},{"@classId":"05"}]') where id='65600000-0000-4000-8000-000000000001' and version='01.00.000';
select is((select count(*) from private.portal_navigation_membership_v1 where id='65600000-0000-4000-8000-000000000001' and node_id='geo:cn-ah'),0::bigint,'moving source geography removes the old province membership');
select is((select count(*) from private.portal_navigation_membership_v1 where id='65600000-0000-4000-8000-000000000001' and node_id='class:isic:0'),0::bigint,'changing classification removes the old ancestor');
select is((api.portal_navigation_v1('process','NavMoved656','{}','geography','geo:cn-sd')->'parent'->>'count')::integer,1,'new name, classification and geography are visible transactionally');
delete from public.processes where id='65600000-0000-4000-8000-000000000002';
select is((select count(*) from private.portal_navigation_versions_v1 where id='65600000-0000-4000-8000-000000000002'),0::bigint,'deletion cannot leave a stale narrow row');
-- Dataset-derived custom values disappear with their last public member.
create temp table retired_node as select node_id from private.portal_navigation_node_v1 where code='CN-AH-ZX';
update public.processes set state_code=20 where id='65600000-0000-4000-8000-000000000004';
select ok(not exists(select 1 from jsonb_array_elements(api.portal_navigation_v1('process','','{}','geography','geo:cn-ah')->'nodes') n where n->>'code'='CN-AH-ZX'),'withdrawal hides retired nonstandard geography values');
select throws_ok(format('select api.portal_navigation_v1(%L,%L,%L,%L,%L)', 'process','','{}','geography',(select node_id from retired_node)),'22023','invalid portal request','known old locator cannot disclose a fully withdrawn custom code');
select lives_ok('select private.assert_portal_navigation_projection_v1()','independent navigation derivation guard passes');
select throws_ok($$update private.portal_navigation_node_v1 set code='changed' where node_id='geo:cn'$$,'55000','Seeded navigation vocabulary is immutable','runtime cannot alter reviewed geography meanings');
select throws_ok($$update private.portal_navigation_node_v1 set code='changed' where code='CN-AH-ZX'$$,'55000','Seeded navigation vocabulary is immutable','runtime-derived identities are immutable too');
-- A definition drift is rejected independently of the old source manifests.
create temp table original_navigation_helper as select pg_get_functiondef('private.portal_navigation_raw_taxonomy_v1(jsonb)'::regprocedure) as definition;
create or replace function private.portal_navigation_raw_taxonomy_v1(p_system jsonb) returns text language sql immutable set search_path='' as $$select 'unclassified'::text$$;
select throws_ok('select private.assert_portal_navigation_projection_v1()','55000','Portal navigation derivation contract drifted','derivation guard detects changed mapping helper');
do $$begin execute (select definition from original_navigation_helper); end$$;
select lives_ok('select private.assert_portal_navigation_projection_v1()','restoring the reviewed helper restores the guard');
select lives_ok('select private.assert_portal_catalog_projection_contract_v1()','old immutable projection manifest remains valid');
select lives_ok('select private.assert_portal_catalog_projection_contract_cn1()','current immutable projection manifest remains valid');
select * from finish();
rollback;
