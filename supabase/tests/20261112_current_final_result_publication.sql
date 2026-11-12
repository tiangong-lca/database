begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,api,private,auth;
select no_plan();
\ir fixtures/final-result-readiness-setup.sql
select ok(not has_function_privilege('anon','api.qry_current_final_result_publication()','execute'),'anon cannot read catalog');
select ok(not has_function_privilege('service_role','api.qry_current_final_result_publication()','execute'),'service role has no catalog grant');
select ok(has_function_privilege('authenticated','api.qry_current_final_result_publication()','execute'),'ordinary authenticated role may read catalog');
set local role authenticated;
select set_config('request.jwt.claim.sub','',true);
select is(api.qry_current_final_result_publication()->>'code','auth_required','null actor is rejected');
select set_config('request.jwt.claim.sub','87930000-0000-4000-8000-000000000002',true);
select is(api.qry_current_final_result_publication(),'{"ok":true,"data":{"publication":null}}'::jsonb,'prepared draft is not listed');
reset role;
select set_config('request.jwt.claim.sub','87930000-0000-4000-8000-000000000001',true);
set local role service_role;
select api.svc_final_result_readiness_begin_v2(pg_temp.readiness_header());
select api.svc_final_result_readiness_artifacts_v2('87950000-0000-4000-8000-000000000001',pg_temp.readiness_proofs());
select api.svc_final_result_readiness_seal_v2('87950000-0000-4000-8000-000000000001');
reset role;
select set_config('request.jwt.claim.sub','87930000-0000-4000-8000-000000000001',true);
create temporary table recovery_fixture(expiry timestamptz,approval jsonb,publication jsonb);
insert into recovery_fixture(expiry) values(clock_timestamp()+interval '1 hour');
grant select,update on recovery_fixture to authenticated;
set local role authenticated;
update recovery_fixture set approval=api.cmd_final_result_release_approve_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash(),'87950000-0000-4000-8000-000000000001','87960000-0000-4000-8000-000000000001',null,expiry,'synthetic recovery');
update recovery_fixture set publication=api.cmd_final_result_release_activate_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash(),'87960000-0000-4000-8000-000000000001',approval#>>'{data,approvalHash}','87950000-0000-4000-8000-000000000001','synthetic-catalog970',repeat('f',64));
select set_config('request.jwt.claim.sub','87930000-0000-4000-8000-000000000002',true);
select is(api.qry_current_final_result_publication(),jsonb_build_object('ok',true,'data',jsonb_build_object('publication',jsonb_build_object(
 'publicationId',(select publication#>>'{data,publicationId}' from recovery_fixture),
 'releaseVersion','2026.11.1','format','final-result-pair.v2'))),'ordinary actor sees only current publication identity and version');
select is(api.qry_final_result_publication_head_v2()->>'code','not_data_product_manager','catalog read does not grant manager access');
reset role;
-- Independent canary: no Process or LCIA Method read is needed for this summary.
create policy catalog970_no_process on public.processes as restrictive for select to authenticated using(false);
set local role authenticated;
select isnt(api.qry_current_final_result_publication()#>'{data,publication}','null'::jsonb,'catalog is independent of dataset visibility');
select set_config('request.jwt.claim.sub','87930000-0000-4000-8000-000000000001',true);
select api.cmd_lca_release_unpublish((select (publication#>>'{data,publicationId}')::uuid from recovery_fixture),'synthetic catalog withdrawal');
select set_config('request.jwt.claim.sub','87930000-0000-4000-8000-000000000002',true);
select is(api.qry_current_final_result_publication()#>'{data,publication}','null'::jsonb,'withdrawn publication is not listed');
reset role;
select is((select count(*) from private.lca_release_publications),1::bigint,'catalog reads do not create publications');
select * from finish();
rollback;
