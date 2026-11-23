-- Functional, rollback-only proof for the summary repair. Large-scale timing
-- is measured separately by scripts/benchmark_portal_summary_bounded.py.
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
alter table public.processes disable trigger user;
alter table public.processes enable trigger portal_catalog_projection_content_sync_v2;
alter table public.flows disable trigger user;
alter table public.flows enable trigger portal_catalog_projection_content_sync_v1;
insert into public.processes(id,version,json,state_code,modified_at)
select '65610000-0000-4000-8000-000000000001','01.00.00'||i,
pg_temp.nav_payload('SummaryProcess656','CN','[{"@classId":"0111"}]'),100,'2026-09-19' from generate_series(0,1) i;
insert into public.flows(id,version,json,state_code,modified_at) values
('65610000-0000-4000-8000-000000000002','01.00.000',jsonb_set(
pg_temp.nav_payload('SummaryFlow656','US','[{"@classId":"17100"}]',true),
'{flowDataSet,flowInformation,dataSetInformation,CASNumber}','"50-00-0"'),100,'2026-09-19');
create temp table summary_result(payload jsonb);
grant select,insert on summary_result to anon;
set local role anon;
insert into summary_result select api.portal_catalog_summary_v1();
reset role;
select is((select payload->>'schemaVersion' from summary_result),'portal.public-catalog-summary.v1','published summary version is unchanged');
select is((select (payload#>>'{counts,process}')::integer from summary_result),1,'summary still counts latest-visible datasets rather than public versions');
select is((select (payload#>>'{counts,flow}')::integer from summary_result),1,'flow dataset count remains independent');
select is((select (payload#>>'{counts,total}')::integer from summary_result),2,'total is the dataset sum');
select ok((select octet_length(payload::text)<=16384 from summary_result),'summary is within 16 KiB');
select is((select jsonb_array_length(payload->'examples') from summary_result),3,'UUID, valid CAS and classification examples remain available');
select ok((select p.proconfig @> array['statement_timeout=2s','row_security=on','jit=off'] from pg_proc p where p.oid='api.portal_catalog_summary_v1()'::regprocedure),'timeout and constrained execution settings are unchanged');
select ok(has_function_privilege('anon','api.portal_catalog_summary_v1()','execute'),'anonymous callers retain the exact public entrypoint');
select ok((select allow_anon and not allow_service_role from private.api_capability_grants where routine_identity='api.portal_catalog_summary_v1()'),'capability boundary is unchanged');
select ok((select bool_and(jsonb_array_length(case when e->>'datasetKind'='process' then api.portal_search_processes_v2(e->>'query')->'items' else api.portal_search_flows_v2(e->>'query')->'items' end)>0)
from summary_result cross join lateral jsonb_array_elements(payload->'examples') e),'every example is executable through the existing public search');
select * from finish();
rollback;
