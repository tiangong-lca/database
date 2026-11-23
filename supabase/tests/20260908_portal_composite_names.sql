-- Database #628: complete names, frozen-v1 parity and public read convergence.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public;
select no_plan();
grant portal_public_executor,api_internal_executor to postgres;
create function pg_temp.name_payload(parts jsonb) returns jsonb
language sql immutable as $$ select jsonb_build_object('processDataSet',
 jsonb_build_object('processInformation',jsonb_build_object('dataSetInformation',
 jsonb_build_object('name',parts)), 'administrativeInformation',jsonb_build_object(
 'publicationAndOwnership',jsonb_build_object('common:dataSetVersion','01.00.000',
 'common:licenseType','Free of charge for all users and uses')))) $$;
select is(private.portal_process_names_v1(null),'[]'::jsonb,'null payload has no names');
select is(private.portal_process_names_v1(pg_temp.name_payload('{}')),'[]'::jsonb,'missing base remains missing');
select is(private.portal_process_names_v1(pg_temp.name_payload('{"treatmentStandardsRoutes":"route"}')),'[]'::jsonb,'modifier alone never becomes name');
select is(private.portal_process_names_v1(pg_temp.name_payload('{"baseName":" base ","treatmentStandardsRoutes":"route","mixAndLocationTypes":"mix","functionalUnitFlowProperties":"voltage"}')),
 '[{"language":"und","value":"base; route; mix; voltage"}]'::jsonb,'four ordered plain-string parts use und');
select is(private.portal_process_names_v1(pg_temp.name_payload('{"baseName":"base","treatmentStandardsRoutes":null,"mixAndLocationTypes":[],"functionalUnitFlowProperties":"   "}')),
 '[{"language":"und","value":"base"}]'::jsonb,'empty parts do not create separators');
select is(private.portal_process_names_v1(pg_temp.name_payload('{"baseName":[{"@xml:lang":"ZH","#text":"交流电"},{"@xml:lang":"zh","#text":"ignored"},{"@xml:lang":"en","#text":"electricity"}],"treatmentStandardsRoutes":[{"@xml:lang":"zh","#text":" "},{"@xml:lang":"zh","#text":"电网"},{"@xml:lang":"ZH","#text":"ignored"},{"@xml:lang":"fr","#text":"reseau"}],"mixAndLocationTypes":{"@xml:lang":"en","#text":"consumer mix"},"functionalUnitFlowProperties":{"@xml:lang":"zh-CN","#text":"must not merge"}}')),
 '[{"language":"ZH","value":"交流电; 电网"},{"language":"en","value":"electricity; consumer mix"}]'::jsonb,
 'first nonempty duplicate, case-insensitive exact tags, base order, no mixed-language or regional merge');
select is(private.portal_process_names_v1(pg_temp.name_payload('{"baseName":"a;b-c","functionalUnitFlowProperties":"1–35 kV"}')),
 '[{"language":"und","value":"a;b-c; 1–35 kV"}]'::jsonb,'source punctuation remains intact');
select is(private.portal_process_names_v1(pg_temp.name_payload(jsonb_build_object('baseName',E'base\nname','mixAndLocationTypes',E'mix\ttext'))) #>> '{0,value}',
 private.portal_scalar_text_v1(to_jsonb(E'base\nname'::text)) || '; ' || private.portal_scalar_text_v1(to_jsonb(E'mix\ttext'::text)),'control characters follow existing scalar normalization');
select is(length(private.portal_process_names_v1(pg_temp.name_payload(jsonb_build_object('baseName',repeat('长',600),'functionalUnitFlowProperties',repeat('长',600)))) #>> '{0,value}'),1202,'long primary names are not truncated');
select is(private.portal_process_names_v1(pg_temp.name_payload($source${"baseName": [{"#text": "交流电生产", "@xml:lang": "zh"}, {"#text": "Alternating current production", "@xml:lang": "en"}], "mixAndLocationTypes": [{"#text": "consumption mix", "@xml:lang": "en"}, {"#text": "消费组合", "@xml:lang": "zh"}], "treatmentStandardsRoutes": [{"#text": "electricity mix", "@xml:lang": "en"}, {"#text": "电力混合", "@xml:lang": "zh"}], "functionalUnitFlowProperties": [{"#text": "1-35kV", "@xml:lang": "en"}, {"#text": "1-35千伏", "@xml:lang": "zh"}]}$source$::jsonb)), '[{"language":"zh","value":"交流电生产; 电力混合; 消费组合; 1-35千伏"},{"language":"en","value":"Alternating current production; electricity mix; consumption mix; 1-35kV"}]'::jsonb,'read-only verified public sample source fields compose exactly');
select lives_ok('select private.assert_portal_catalog_projection_contract_v1()','frozen V1 manifest intact');
select lives_ok('select private.assert_portal_catalog_projection_contract_cn1()','new derivation manifest intact');
select lives_ok('select private.assert_portal_process_keyword_rank_contract_cn1()','new rank manifest and GIN intact');
select lives_ok('select private.assert_portal_catalog_character_contract_cn1()','new narrow character child intact');
select ok(not has_function_privilege('anon','private.portal_process_names_v1(jsonb)','execute'),'anonymous users cannot invoke internal helper');
select ok(not has_table_privilege('anon','private.portal_catalog_search_rows_v2','select'),'new projection stays private');
create temporary table original_names_helper as
select pg_get_functiondef('private.portal_process_names_v1(jsonb)'::regprocedure) as definition;
create or replace function private.portal_process_names_v1(p_json jsonb) returns jsonb
language sql immutable parallel safe set search_path='' as $$ select '[]'::jsonb $$;
select throws_ok('select private.assert_portal_catalog_projection_contract_cn1()','55000','Portal projection derivation contract drifted','new manifest fails closed when composite helper drifts');
select lives_ok('select private.assert_portal_catalog_projection_contract_v1()','new-helper drift cannot redefine frozen V1 semantics');
do $$ begin execute (select definition from original_names_helper); end $$;
select lives_ok('select private.assert_portal_catalog_projection_contract_cn1()','restored exact helper satisfies the new manifest');
select is((select count(*) from pg_trigger where tgrelid='public.flows'::regclass and tgname='portal_catalog_projection_content_sync_v2'),0::bigint,'Flow has no second writer');
select ok(not has_table_privilege('anon','private.portal_catalog_search_current_v2','select'),'routing view is private');
select ok((select reloptions @> array['security_invoker=true'] from pg_class where oid='private.portal_catalog_search_current_v2'::regclass),'routing uses caller RLS and privileges');
alter view private.portal_catalog_search_current_v2 set (security_invoker=false);
select throws_ok('select private.assert_portal_catalog_projection_contract_cn1()','55000','Portal name routing contract drifted','routing security drift fails closed');
alter view private.portal_catalog_search_current_v2 set (security_invoker=true);
alter table private.portal_catalog_search_rows_v2 disable trigger portal_catalog_facet_sync_v2;
select throws_ok('select private.assert_portal_catalog_facet_contract_v1()','55000',
 'Portal facet derivation contract drifted','the shared facet guard requires its Process V2 trigger');
alter table private.portal_catalog_search_rows_v2 enable trigger portal_catalog_facet_sync_v2;
select ok((select proowner='api_internal_executor'::regrole and prosecdef
 and prosrc like '%private.portal_projection_semantic_process_exact_cn1(p_query_embedding)%'
 from pg_proc where oid='private.portal_projection_semantic_process_exact_v1(extensions.vector)'::regprocedure)
 and not has_function_privilege('anon','private.portal_projection_semantic_process_exact_v1(extensions.vector)','execute'),
 'earlier exact Process fallback dispatches to current keys under its original owner');
-- Disable unrelated publication/embedding jobs only in this rollback fixture.
alter table public.processes disable trigger user;
alter table public.processes enable trigger portal_catalog_projection_content_sync_v2;
insert into public.processes(id,version,json,state_code,modified_at)
select '62810000-0000-4000-8000-000000000001','01.00.00'||i,
 pg_temp.name_payload(jsonb_build_object('baseName',jsonb_build_object('@xml:lang','en','#text','SameBase628'),
 'treatmentStandardsRoutes',jsonb_build_object('@xml:lang','en','#text',case when i=0 then 'RouteHistorical628' else 'RouteCurrent628' end),
 'mixAndLocationTypes',jsonb_build_object('@xml:lang','en','#text','MixConsumer628'),
 'functionalUnitFlowProperties',jsonb_build_object('@xml:lang','en','#text','Voltage628 铜'))),100,'2026-09-08T00:00:00Z'
from generate_series(0,1) i;
select is((select count(*) from private.portal_catalog_search_rows_v2 where id='62810000-0000-4000-8000-000000000001'),2::bigint,'new writes preserve both exact versions');
select is((select count(*) from private.portal_catalog_search_rows_v2 n join public.processes o on o.id=n.id and o.version::text=n.version
 where n.id='62810000-0000-4000-8000-000000000001' and n.card - 'names' - 'document'=(private.portal_catalog_card_v1('process',o.state_code,o.json)-'names'-'document') and n.modified_at=o.modified_at),2::bigint,'all unrelated card fields and source timestamp unchanged');
select is((select count(*) from private.portal_catalog_search_rows_v1 where dataset_kind='process'),0::bigint,
 'publication writes no frozen Process card');
select throws_ok($test$insert into private.portal_catalog_search_rows_v1
select dataset_kind,id,version,state_code,modified_at,card,document,1 from private.portal_catalog_search_rows_v2
where id='62810000-0000-4000-8000-000000000001'$test$,'23514',null,'the V1 table rejects Process keys');
create temp table names_results(label text primary key,payload jsonb);
grant select,insert on names_results to anon;
set local role anon;
insert into names_results values
 ('detail',api.portal_get_dataset_v1('process','62810000-0000-4000-8000-000000000001','01.00.000')),
 ('search2',api.portal_search_processes_v2('RouteHistorical628')),
 ('search1',api.portal_search_processes_v1('RouteCurrent628')),
 ('base',api.portal_search_processes_v2('SameBase628')),
 ('character',api.portal_search_processes_v2('铜')),
 ('facet2',api.portal_facets_v2('process','RouteHistorical628')),
 ('facet1',api.portal_facets_v1('process','RouteCurrent628')),
 ('hybrid2',api.portal_hybrid_search_v2('process',array['RouteHistorical628'],'['||'1,'||repeat('0,',1022)||'0]','{}',20)),
 ('hybrid1',api.portal_hybrid_search_v1('process',array['RouteCurrent628'],'['||'1,'||repeat('0,',1022)||'0]','{}',20));
reset role;
select is((select payload #>> '{metadata,names,0,value}' from names_results where label='detail'),
 'SameBase628; RouteHistorical628; MixConsumer628; Voltage628 铜','detail uses original four fields');
select is((select payload #>> '{items,0,names,0,value}' from names_results where label='search2'),
 (select payload #>> '{metadata,names,0,value}' from names_results where label='detail'),'Search V2 equals exact detail');
select is((select payload #>> '{items,0,names,0,value}' from names_results where label='search1'),
 'SameBase628; RouteCurrent628; MixConsumer628; Voltage628 铜','Search V1 retains latest-version semantics');
select is((select payload #>> '{items,0,names,0,value}' from names_results where label='hybrid2'),
 (select payload #>> '{metadata,names,0,value}' from names_results where label='detail'),'Hybrid V2 hydrates exact matched version');
select is((select payload #>> '{items,0,names,0,value}' from names_results where label='hybrid1'),
 'SameBase628; RouteCurrent628; MixConsumer628; Voltage628 铜','Hybrid V1 receives latest-version full name');
select is((select jsonb_array_length(payload->'items') from names_results where label='character'),2,'modifier-only character query reaches character projection');
select is((select jsonb_array_length(payload->'items') from names_results where label='base'),2,'base query still recalls both matching versions');
select ok((select payload::text like '%open%' from names_results where label='facet2'),'modifier query facets include matching access level');
select ok((select payload::text like '%open%' from names_results where label='facet1'),'V1 modifier query facets remain available');
select is((select array_agg(version order by version) from private.portal_catalog_search_rows_v2 where id='62810000-0000-4000-8000-000000000001'),array['01.00.000','01.00.001'],'exact versions retained');
-- Full pages with multilingual names beyond the bounded name-sort key.
insert into public.processes(id,version,json,state_code,modified_at)
select md5('628-long-name:'||i)::uuid,'01.00.000',pg_temp.name_payload(
 jsonb_build_object(
 'baseName',jsonb_build_array(jsonb_build_object('@xml:lang','en','#text','LongName628 '||i||repeat('a',150)),jsonb_build_object('@xml:lang','zh','#text','长名称'||i||repeat('电',150))),
 'treatmentStandardsRoutes',jsonb_build_array(jsonb_build_object('@xml:lang','en','#text',repeat('r',150)),jsonb_build_object('@xml:lang','zh','#text',repeat('网',150))),
 'mixAndLocationTypes',jsonb_build_array(jsonb_build_object('@xml:lang','en','#text',repeat('m',150)),jsonb_build_object('@xml:lang','zh','#text',repeat('混',150))),
 'functionalUnitFlowProperties',jsonb_build_array(jsonb_build_object('@xml:lang','en','#text',repeat('v',150)),jsonb_build_object('@xml:lang','zh','#text',repeat('压',150)))
 )),100,'2026-09-08T00:00:00Z' from generate_series(1,55) i;
set local role anon;
insert into names_results values('longpage1',api.portal_search_processes_v2('LongName628','{}','name_asc',null,50));
insert into names_results select 'longpage2',api.portal_search_processes_v2('LongName628','{}','name_asc',payload->>'nextCursor',50) from names_results where label='longpage1';
reset role;
select is((select jsonb_array_length(payload->'items') from names_results where label='longpage1'),50,'long multilingual name full page retained');
select is((select jsonb_array_length(payload->'items') from names_results where label='longpage2'),5,'long name-sort cursor continues without losing rows');
select ok((select octet_length(payload::text)<524288 from names_results where label='longpage1'),'representative multilingual full page stays within response bound');
select ok((select octet_length(payload->>'nextCursor')<3000 from names_results where label='longpage1'),'long names do not create unbounded cursors');
select ok((select min(length(item#>>'{names,0,value}'))>600 from names_results cross join lateral jsonb_array_elements(payload->'items') item where label='longpage1'),'full primary names survive bounded sort fallback');
select is((select count(distinct item#>>'{key,id}') from names_results cross join lateral jsonb_array_elements(payload->'items') item where label in ('longpage1','longpage2')),55::bigint,'long-name pages contain no duplicate keys');
select ok((select (api.portal_search_processes_v1('LongName628','{}','name_asc',null,1)->>'queryFingerprint') is distinct from private.portal_query_fingerprint_v1('process','longname628','{}','name_asc')),'new Search epoch cannot accept frozen name-order cursors');
update public.processes set state_code=20 where id='62810000-0000-4000-8000-000000000001';
select is((select count(*) from private.portal_catalog_search_rows_v2 where id='62810000-0000-4000-8000-000000000001'),0::bigint,'withdrawal removes new search rows');
select is((select count(*) from private.portal_catalog_character_rows_v2 where id='62810000-0000-4000-8000-000000000001'),0::bigint,'withdrawal cascades new character rows');
select is((select count(*) from private.portal_catalog_facet_rows_v1 where id='62810000-0000-4000-8000-000000000001'),0::bigint,'Process withdrawal cascades from V2 to its name-independent facets');
-- Unchanged Flow content is read directly from V1, including future updates.
alter table public.flows disable trigger user;
alter table public.flows enable trigger portal_catalog_projection_content_sync_v1;
insert into public.flows(id,version,json,state_code,modified_at) values
('62810000-0000-4000-8000-000000000002','01.00.000',
'{"flowDataSet":{"flowInformation":{"dataSetInformation":{"name":{"baseName":"FlowStable628"}}}}}',100,'2026-09-08T00:00:00Z');
select is((select count(*) from private.portal_catalog_search_rows_v2 where dataset_kind='flow'),0::bigint,'Flow never copied into Process shadow');
select is((select card from private.portal_catalog_search_current_v2 where dataset_kind='flow' and id='62810000-0000-4000-8000-000000000002'),
(select card from private.portal_catalog_search_rows_v1 where dataset_kind='flow' and id='62810000-0000-4000-8000-000000000002'),'Flow current card is exactly V1');
select is(api.portal_search_flows_v1('FlowStable628')->>'queryFingerprint',private.portal_query_fingerprint_v1('flow','flowstable628','{}','relevance'),'Flow cursor epoch remains unchanged');
select throws_ok($test$insert into private.portal_catalog_search_rows_v2
select dataset_kind,id,version,state_code,modified_at,card,document,2 from private.portal_catalog_search_rows_v1 where dataset_kind='flow' and id='62810000-0000-4000-8000-000000000002'$test$,'23514',null,'shadow rejects Flow data');
update public.flows set state_code=20 where id='62810000-0000-4000-8000-000000000002';
select is((select count(*) from private.portal_catalog_search_current_v2 where dataset_kind='flow' and id='62810000-0000-4000-8000-000000000002'),0::bigint,'Flow withdrawal remains live through sole V1 writer');
select * from finish();
rollback;
