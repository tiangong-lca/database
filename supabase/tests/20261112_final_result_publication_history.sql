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

select is(api.qry_final_result_download(p_format=>'tidas')#>>'{data,publicationId}',(select publication#>>'{data,publicationId}' from package_publication),'omitted publication selects current');
select is(api.qry_final_result_publication_history()#>'{data,publications}','[]'::jsonb,'current is not duplicated in history');
reset role;
update private.lca_release_publications set status='superseded',is_current=false,superseded_at=clock_timestamp();
set local role authenticated;
select is(api.qry_final_result_download(p_format=>'tidas')->>'code','result_package_not_available','no current does not fall back to latest historical');
select is(api.qry_final_result_download((select (publication#>>'{data,publicationId}')::uuid from package_publication),'tidas')#>>'{data,file,name}','result.tidas.7z','ordinary actor downloads exact superseded archive');
select is(api.qry_final_result_publication_history()#>'{data,publications,0,formats}','["ilcd","tidas"]'::jsonb,'history lists complete registered archive formats');
select is(api.qry_final_result_download('87960000-0000-4000-8000-000000000099','ilcd')->>'code','result_package_not_available','unknown explicit identity never falls back');
select is(api.cmd_lca_release_unpublish((select (publication#>>'{data,publicationId}')::uuid from package_publication),'test')->>'code','not_data_product_manager','reader cannot withdraw history');
reset role;
-- Rollback-only metadata copies exercise same-timestamp cursor boundaries. They
-- deliberately have no sealed package plans, so cannot acquire archive access.
insert into private.lca_release_runs select (jsonb_populate_record(null::private.lca_release_runs,to_jsonb(r)||jsonb_build_object(
 'id','87930000-0000-4000-8000-000000000020','release_version','2026.11.2','idempotency_key','history-page-2'))).* from private.lca_release_runs r;
insert into private.lca_release_publications select (jsonb_populate_record(null::private.lca_release_publications,to_jsonb(p)||jsonb_build_object(
 'id','87970000-0000-4000-8000-000000000020','release_run_id','87930000-0000-4000-8000-000000000020','release_version','2026.11.2','idempotency_key','history-page-2'))).* from private.lca_release_publications p;
insert into private.final_result_publication_bindings select '87970000-0000-4000-8000-000000000020',verification_id,null,null from private.final_result_publication_bindings;
create temporary table history_pages(first_page jsonb,second_page jsonb);
grant all on history_pages to authenticated;
set local role authenticated;
insert into history_pages(first_page) values(api.qry_final_result_publication_history(1));
update history_pages set second_page=api.qry_final_result_publication_history(1,(first_page#>>'{data,nextCursor,publishedAt}')::timestamptz,(first_page#>>'{data,nextCursor,publicationId}')::uuid);
select is(jsonb_array_length((select first_page#>'{data,publications}' from history_pages)),1,'bounded first history page');
select isnt((select first_page#>>'{data,publications,0,publicationId}' from history_pages),(select second_page#>>'{data,publications,0,publicationId}' from history_pages),'same-timestamp cursor does not repeat identity');
select is((select second_page#>'{data,nextCursor}' from history_pages),'null'::jsonb,'last page has no cursor');
select throws_ok($q$select api.qry_final_result_publication_history(51)$q$,'22023','Invalid publication history page','oversized history rejected');
select throws_ok($q$select api.qry_final_result_publication_history(1,now(),null)$q$,'22023','Invalid publication history page','partial cursor rejected');
select set_config('request.jwt.claim.sub','87930000-0000-4000-8000-000000000001',true);
select is(api.cmd_lca_release_unpublish((select (publication#>>'{data,publicationId}')::uuid from package_publication),'withdraw old archive')->>'ok','true','manager can withdraw superseded final publication');
select is(api.cmd_lca_release_unpublish((select (publication#>>'{data,publicationId}')::uuid from package_publication),'withdraw old archive')->>'reused','true','withdrawal retry is idempotent');
select is(api.qry_final_result_download((select (publication#>>'{data,publicationId}')::uuid from package_publication),'tidas')->>'code','result_package_not_available','withdrawn history cannot be downloaded');
select is((select count(*) from jsonb_array_elements(api.qry_final_result_publication_history()#>'{data,publications}') where value->>'status'='unpublished'),0::bigint,'withdrawn records excluded before history pagination');
select is(jsonb_array_length(api.qry_final_result_publication_history(1)#>'{data,publications}'),1,'withdrawn history does not consume a page slot');
select set_config('request.jwt.claim.sub','',true);
select is(api.qry_final_result_publication_history()->>'code','auth_required','history requires an actor');
reset role;
select ok(not has_function_privilege('anon','api.qry_final_result_publication_history(integer,timestamptz,uuid)','execute') and not has_function_privilege('service_role','api.qry_final_result_publication_history(integer,timestamptz,uuid)','execute'),'history uses authenticated grants only');
select throws_ok($q$update private.lca_release_publications set status='current',is_current=true where status='unpublished'$q$,'23514','lca_release_publication_immutable','withdrawn historical publication cannot be resurrected');
select * from finish();
rollback;
