begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,api,private,auth;
select no_plan();
\ir fixtures/final-result-readiness-setup.sql
set local role service_role;
select api.svc_final_result_readiness_begin_v2(pg_temp.readiness_header());
select api.svc_final_result_readiness_artifacts_v2('87950000-0000-4000-8000-000000000001',pg_temp.readiness_proofs());
select api.svc_final_result_readiness_seal_v2('87950000-0000-4000-8000-000000000001');
reset role;
create temporary table readback_fixture(approval jsonb,publication jsonb,observation jsonb,receipt jsonb);
insert into readback_fixture default values;
grant select,update on readback_fixture to authenticated;
set local role authenticated;
update readback_fixture set approval=api.cmd_final_result_release_approve_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash(),'87950000-0000-4000-8000-000000000001','87960000-0000-4000-8000-000000000001',null,clock_timestamp()+interval '1 hour','synthetic public observation');
update readback_fixture set publication=api.cmd_final_result_release_activate_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash(),'87960000-0000-4000-8000-000000000001',approval#>>'{data,approvalHash}','87950000-0000-4000-8000-000000000001','synthetic-readback',repeat('f',64));
update readback_fixture set observation=jsonb_build_object('schemaVersion','tiangong.final-result-public-observation.v1','releaseRunId','87930000-0000-4000-8000-000000000010','publishPlanHash',pg_temp.final_plan_hash(),'publicationId',publication#>>'{data,publicationId}',
 'candidateHash',api.qry_final_result_release_v2('87930000-0000-4000-8000-000000000010')#>>'{data,candidateHash}',
 'targetHash',repeat('d',64),'selectionHash',api.qry_final_result_release_v2('87930000-0000-4000-8000-000000000010')#>>'{data,selectionHash}',
 'actorId',auth.uid(),'runtimeRevision','87940000-0000-4000-8000-000000000001','readerSha256',repeat('c',64),'resultCount',2,
 'startedAt',clock_timestamp(),'verifiedAt',clock_timestamp(),'observationsSha256',repeat('a',64),'downloads','{"tidas":{"status":"unavailable"},"ilcd":{"status":"unavailable"}}'::jsonb);
reset role;
create function pg_temp.readback(p_patch jsonb default '{}') returns jsonb language sql as $$
 select api.cmd_final_result_release_readback_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash(),(observation||p_patch)::text) from readback_fixture
$$;
grant execute on function pg_temp.readback(jsonb) to authenticated;
select ok(not has_function_privilege('service_role','api.cmd_final_result_release_readback_v2(uuid,text,text)','execute'),'service attestor cannot record manager public observations');
select ok(not has_function_privilege('anon','api.cmd_final_result_release_readback_v2(uuid,text,text)','execute'),'anonymous caller cannot record observations');
set local role authenticated;
select is(pg_temp.readback('{"resultCount":1}')->>'code','final_result_readback_changed','partial numerical coverage cannot be recorded as complete');
select is(pg_temp.readback('{"runtimeRevision":"87940000-0000-4000-8000-000000000099"}')->>'code','final_result_readback_changed','reader revision is pinned');
select is(pg_temp.readback('{"publicationId":"87940000-0000-4000-8000-000000000099"}')->>'code','final_result_readback_changed','publication identity is pinned');
select is(pg_temp.readback('{"verifiedAt":"2020-01-01T00:00:00Z"}')->>'code','final_result_readback_expired','old evidence is rejected');
select throws_ok($q$select pg_temp.readback('{"downloads":{}}')$q$,'22023','Both public ZIP outcomes are required','missing ZIP observations fail');
select throws_ok($q$select pg_temp.readback('{"extra":"signed-url"}')$q$,'22023','Invalid public Result observation binding','arbitrary evidence fields cannot persist');
select is(api.qry_final_result_release_v2('87930000-0000-4000-8000-000000000010')#>>'{data,status}','published','failed observation never withdraws or changes authority');
update readback_fixture set receipt=pg_temp.readback();
select is((select receipt->>'ok' from readback_fixture),'true','all selected rows and expected inaccessible ZIPs can be attested');
select is(api.qry_final_result_release_v2('87930000-0000-4000-8000-000000000010')#>>'{data,status}','readback_verified','observation advances run audit status');
select is(pg_temp.readback(),(select receipt from readback_fixture),'lost ACK recovers exact original receipt');
select is(pg_temp.readback('{"observationsSha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}')->>'code','final_result_readback_conflict','second observation cannot overwrite immutable receipt');
select api.cmd_lca_release_unpublish((select (publication#>>'{data,publicationId}')::uuid from readback_fixture),'synthetic withdrawal');
select is(pg_temp.readback(),(select receipt from readback_fixture),'historical receipt recovery does not resurrect publication');
select is(api.qry_final_result_publication_head_v2()->'data','null'::jsonb,'receipt recovery leaves withdrawal intact');
select set_config('request.jwt.claim.sub','87930000-0000-4000-8000-000000000002',true);
select is(pg_temp.readback()->>'code','not_data_product_manager','ordinary user cannot recover manager evidence');
reset role;
select throws_ok($q$update private.lca_release_runs set readback_receipt='{}' where id='87930000-0000-4000-8000-000000000010'$q$,'23514','Final Result public readback is immutable','storage trigger rejects evidence rewrite');
select * from finish();
rollback;
