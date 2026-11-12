begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,api,private,auth;
select no_plan();
-- Caller owns BEGIN / ROLLBACK. Only synthetic service attestations, not actual
-- external file/numeric qualification. Release owns the real reader integration.
\ir fixtures/final-result-release-setup.sql
create or replace function pg_temp.final_release_plan(p_patch jsonb default '{}') returns text language sql as $$
 select (jsonb_build_object('schemaVersion','tiangong.final-result-publish-plan.v2','releaseRunId','87930000-0000-4000-8000-000000000010',
 'releaseVersion','2026.11.1','candidateSha256',pg_temp.candidate_fixture()#>>'{receipt,candidateSha256}',
 'targetHash',repeat('d',64),'selectionHash','402fe6857b36ec20ac91b65c3de19973d2b0fc8fd284df7c8deb09bae89a017e','selectionCount',3,
 'expectedCurrentPublicationId',null,'rollbackOfPublicationId',null,'reason','synthetic selected direct and derived Results')||p_patch)::text
$$;

set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','87930000-0000-4000-8000-000000000001',true);
select api.cmd_final_result_release_prepare_v2(pg_temp.final_release_plan(),'synthetic-readiness');
select api.cmd_final_result_release_members_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash(),'[{"uuid":"87920000-0000-4000-8000-000000000010","version":"01.00.000"},{"uuid":"87920000-0000-4000-8000-000000000011","version":"01.00.000"},{"uuid":"87920000-0000-4000-8000-000000000012","version":"01.00.000"}]');
select api.cmd_final_result_release_seal_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash());
reset role;
set local role service_role;
select api.svc_result_query_runtime_configure_v2('87940000-0000-4000-8000-000000000001',null,repeat('d',64),repeat('c',64),true,'synthetic readiness reader');
reset role;
\ir fixtures/final-result-probe-evidence.sql

set local role service_role;
select api.svc_final_result_readiness_begin_v2(pg_temp.readiness_header());
select api.svc_final_result_readiness_artifacts_v2('87950000-0000-4000-8000-000000000001',pg_temp.readiness_proofs());
select is(api.svc_final_result_readiness_seal_v2('87950000-0000-4000-8000-000000000001')#>>'{data,probeCount}','3','complete Candidate uses both first/last samples on shared artifact');
reset role;
create temporary table package_publication(approval jsonb,publication jsonb);
grant select,insert,update on package_publication to authenticated;
set local role authenticated;
insert into package_publication(approval) select api.cmd_final_result_release_approve_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash(),'87950000-0000-4000-8000-000000000001','87960000-0000-4000-8000-000000000001',null,clock_timestamp()+interval '1 hour','synthetic complete package');
update package_publication set publication=api.cmd_final_result_release_activate_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash(),'87960000-0000-4000-8000-000000000001',approval#>>'{data,approvalHash}','87950000-0000-4000-8000-000000000001','synthetic-complete',repeat('f',64));
select is((select publication#>>'{data,status}' from package_publication),'current','complete Candidate activated');
select set_config('request.jwt.claim.sub','87930000-0000-4000-8000-000000000002',true);
select is(api.qry_final_result_download((select (publication#>>'{data,publicationId}')::uuid from package_publication),'tidas')#>>'{data,file,name}','result.tidas.7z','complete publication serves TIDAS even when the exact support row is absent from authoring tables');
select is(api.qry_final_result_download((select (publication#>>'{data,publicationId}')::uuid from package_publication),'ilcd')#>>'{data,file,name}','result.ilcd.7z','complete publication serves its exact ILCD archive to a non-manager');
select is(api.qry_final_result_download('87960000-0000-4000-8000-000000000099','tidas')->>'code','result_package_not_available','unknown publication cannot fall back to the current package');
select throws_ok($q$select api.qry_final_result_download((select (publication#>>'{data,publicationId}')::uuid from package_publication),'hdf5')$q$,'22023','Supported archive format is required','browser download never exposes whole numeric matrices');
reset role;
select ok(to_regprocedure('api.qry_final_result_download_v2(uuid,text)') is null and not exists (select 1 from private.api_capability_grants where routine_identity='api.qry_final_result_download_v2(uuid, text)'), 'transition RPC and capability registration are retired');
select ok(not has_function_privilege('anon','api.qry_final_result_download(uuid,text)','execute') and not has_function_privilege('service_role','api.qry_final_result_download(uuid,text)','execute'),'stable download RPC is authenticated-only');
set local role authenticated;
select set_config('request.jwt.claim.sub','',true);
select is(api.qry_final_result_download((select (publication#>>'{data,publicationId}')::uuid from package_publication),'tidas')->>'code','auth_required','a missing actor is denied');
select set_config('request.jwt.claim.sub','87930000-0000-4000-8000-000000000001',true);
reset role;
create temporary table package_readback(observation jsonb);
insert into package_readback select jsonb_build_object('schemaVersion','tiangong.final-result-public-observation.v1','releaseRunId','87930000-0000-4000-8000-000000000010','publishPlanHash',pg_temp.final_plan_hash(),'publicationId',publication#>>'{data,publicationId}',
 'candidateHash',pg_temp.candidate_fixture()#>>'{receipt,candidateSha256}','targetHash',repeat('d',64),'selectionHash','402fe6857b36ec20ac91b65c3de19973d2b0fc8fd284df7c8deb09bae89a017e',
 'actorId','87930000-0000-4000-8000-000000000001','runtimeRevision','87940000-0000-4000-8000-000000000001','readerSha256',repeat('c',64),'resultCount',3,
 'startedAt',clock_timestamp(),'verifiedAt',clock_timestamp(),'observationsSha256',repeat('a',64),'downloads','{"tidas":{"status":"unavailable"},"ilcd":{"status":"unavailable"}}'::jsonb) from package_publication;
grant select,update on package_readback to authenticated;
set local role authenticated;
select is(api.cmd_final_result_release_readback_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash(),(select observation::text from package_readback))->>'code','final_result_readback_changed','available archives cannot be recorded as unavailable');
update package_readback set observation=jsonb_set(observation,'{downloads}',jsonb_build_object('tidas',jsonb_build_object('status','verified','file',api.qry_final_result_download((select (publication#>>'{data,publicationId}')::uuid from package_publication),'tidas')#>'{data,file}'),'ilcd',jsonb_build_object('status','verified','file',api.qry_final_result_download((select (publication#>>'{data,publicationId}')::uuid from package_publication),'ilcd')#>'{data,file}')));
select is(api.cmd_final_result_release_readback_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash(),(select jsonb_set(observation,'{downloads,tidas,file,sha256}',to_jsonb(repeat('f',64)))::text from package_readback))->>'code','final_result_readback_changed','wrong archive digest is rejected');
select is(api.cmd_final_result_release_readback_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash(),(select observation::text from package_readback))->>'ok','true','both exact archive attestations can be recorded');
select api.cmd_lca_release_unpublish((select (publication#>>'{data,publicationId}')::uuid from package_publication),'synthetic complete package withdrawal');
select is(api.qry_final_result_download((select (publication#>>'{data,publicationId}')::uuid from package_publication),'tidas')->>'code','result_package_not_available','withdrawn package cannot get a fresh download descriptor');
reset role;
select * from finish();
rollback;
