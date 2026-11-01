begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,api,private,auth;
select no_plan();
\ir fixtures/final-result-candidate-setup.sql
set local role service_role;
select api.svc_result_candidate_register_v2(a->>'candidateText',a->>'catalogText',a->'receipt') from original_args;
reset role;
insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
 ('87930000-0000-4000-8000-000000000001','authenticated','authenticated','selection-manager@example.invalid','{}','{}',now(),now()),
 ('87930000-0000-4000-8000-000000000002','authenticated','authenticated','selection-reader@example.invalid','{}','{}',now(),now());
insert into private.users(id,raw_user_meta_data) values('87930000-0000-4000-8000-000000000001','{}'),('87930000-0000-4000-8000-000000000002','{}');
insert into private.teams(id,json,rank,is_public) values('00000000-0000-0000-0000-000000000000','{"name":"synthetic"}',0,false) on conflict(id) do nothing;
insert into private.roles(user_id,team_id,role) values('87930000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','data_product_manager');
create function pg_temp.final_release_plan(p_patch jsonb default '{}') returns text language sql as $$
 select (jsonb_build_object('schemaVersion','tiangong.final-result-publish-plan.v2','releaseRunId','87930000-0000-4000-8000-000000000010',
 'releaseVersion','2026.11.1','candidateSha256',pg_temp.candidate_fixture()#>>'{receipt,candidateSha256}',
 'targetHash',repeat('d',64),'selectionHash','cada21d09411290414089d96661ee0bfd20a8909a930e21bb85a305d545259bc','selectionCount',2,
 'expectedCurrentPublicationId',null,'rollbackOfPublicationId',null,'reason','synthetic selected direct and derived Results')||p_patch)::text
$$;
create function pg_temp.final_plan_hash() returns text language sql as $$
 select encode(extensions.digest(convert_to(pg_temp.final_release_plan(),'UTF8'),'sha256'),'hex')
$$;
grant execute on function pg_temp.final_release_plan(jsonb),pg_temp.final_plan_hash(),pg_temp.candidate_fixture() to authenticated;
select ok(not has_function_privilege('service_role','api.cmd_final_result_release_prepare_v2(text,text)','execute'),'storage service role cannot prepare actor publication');
select ok(not has_table_privilege('authenticated','private.final_result_release_members','select,insert,update,delete'),'selection tables remain closed to browser SQL');
select is((select count(*) from pg_class where oid in ('private.final_result_release_plans'::regclass,'private.final_result_release_members'::regclass,'private.final_result_release_selection_seals'::regclass) and relrowsecurity),3::bigint,'all new selection relations retain RLS');
set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claims','{"role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','',true);
select is(api.cmd_final_result_release_prepare_v2('{}','synthetic')->>'code','auth_required','authentication checked before plan decoding');
select set_config('request.jwt.claim.sub','87930000-0000-4000-8000-000000000002',true);
select is(api.cmd_final_result_release_prepare_v2(pg_temp.final_release_plan(),'synthetic')->>'code','not_data_product_manager','ordinary actor cannot prepare publication');
select set_config('request.jwt.claim.sub','87930000-0000-4000-8000-000000000001',true);
select throws_ok($q$select api.cmd_final_result_release_prepare_v2(pg_temp.final_release_plan('{"unknown":true}'),'synthetic')$q$,'22023','Invalid final Result publish plan','unknown plan fields rejected');
select throws_ok($q$select api.cmd_final_result_release_prepare_v2(pg_temp.final_release_plan(jsonb_build_object('candidateSha256',repeat('a',64))),'synthetic')$q$,'22023','Final Result Candidate storage or selection count is invalid','unknown Candidate rejected before run creation');
select throws_ok($q$select api.cmd_final_result_release_prepare_v2(pg_temp.final_release_plan(jsonb_build_object('targetHash',repeat('e',64))),'synthetic')$q$,'22023','Final Result Candidate storage or selection count is invalid','unverified target is not a publishing source');
select is(api.cmd_final_result_release_prepare_v2(pg_temp.final_release_plan('{"expectedCurrentPublicationId":"87930000-0000-4000-8000-000000000099"}'),'synthetic')->>'code','expected_current_conflict','stale current precondition does not create a run');
select throws_ok($q$select api.cmd_final_result_release_prepare_v2(pg_temp.final_release_plan('{"rollbackOfPublicationId":"87930000-0000-4000-8000-000000000099"}'),'synthetic')$q$,'22023','Rollback must reference terminal history with the exact retained Candidate','rollback cannot invent history or bypass exact Candidate binding');
select throws_ok($q$select api.cmd_final_result_release_prepare_v2(pg_temp.final_release_plan('{"selectionCount":0}'),'synthetic')$q$,'22023','Empty final Result publication selection','empty publication cannot prepare');
select throws_ok($q$select api.cmd_final_result_release_prepare_v2(pg_temp.final_release_plan(jsonb_build_object('releaseVersion','2026.11.'||repeat('1',10000))),'synthetic')$q$,'22023','Invalid final Result publish plan','oversized version rejected before unique-index writes');
select throws_ok($q$select api.cmd_final_result_release_prepare_v2(null,'synthetic')$q$,'22023','Invalid final Result publish plan','null plan rejected');
select is(api.cmd_final_result_release_prepare_v2(pg_temp.final_release_plan(),'synthetic')#>>'{data,status}','prepared','actor creates a versioned prepared run');
select is(api.cmd_final_result_release_prepare_v2(pg_temp.final_release_plan(),'synthetic')#>>'{data,publishPlanHash}',pg_temp.final_plan_hash(),'same prepare recovers exact raw plan hash');
select throws_ok($q$select api.cmd_final_result_release_prepare_v2(pg_temp.final_release_plan('{"reason":"changed"}'),'synthetic')$q$,'23505','Final Result release preparation identity conflict','same run cannot bind changed plan bytes');
select throws_ok($q$select api.cmd_final_result_release_prepare_v2(pg_temp.final_release_plan('{"releaseRunId":"87930000-0000-4000-8000-000000000011","releaseVersion":"2026.11.2"}'),'synthetic')$q$,'23505','Final Result release preparation identity conflict','actor idempotency key cannot name another run');
select is(api.qry_final_result_release_v2('87930000-0000-4000-8000-000000000010')#>>'{data,registeredResultCount}','0','prepared selection starts empty');
select is(api.cmd_lca_release_approve('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash())->>'code','release_not_ready_for_approval','legacy approval cannot approve prepared final Results');
select throws_ok($q$select api.cmd_final_result_release_members_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash(),'[{"uuid":"87920000-0000-4000-8000-000000000030","version":"01.00.000"}]')$q$,'22023','Selected Result is absent from the exact Candidate','source Unit identity cannot stand in for final Result');
select throws_ok($q$select api.cmd_final_result_release_members_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash(),'[{"uuid":"87920000-0000-4000-8000-000000000010","version":"01.00.000","ordinal":1}]')$q$,'22023','Invalid final Result selection identity','caller cannot supply raw artifact row ordinals');
select throws_ok($q$select api.cmd_final_result_release_members_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash(),'[{"uuid":"87920000-0000-4000-8000-000000000010","version":"01.00.000"},{"uuid":"87920000-0000-4000-8000-000000000099","version":"01.00.000"}]')$q$,'22023','Selected Result is absent from the exact Candidate','late invalid member rolls back earlier valid member');
select is(api.qry_final_result_release_v2('87930000-0000-4000-8000-000000000010')#>>'{data,registeredResultCount}','0','late batch failure leaves no partial rows');
select throws_ok($q$select api.cmd_final_result_release_members_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash(),(select jsonb_agg(jsonb_build_object('uuid','87920000-0000-4000-8000-000000000010','version','01.00.000')) from generate_series(1,501)))$q$,'22023','Invalid final Result release membership batch','batch bound checked before deduplication');
select is(api.cmd_final_result_release_members_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash(),'[{"uuid":"87920000-0000-4000-8000-000000000010","version":"01.00.000"}]')#>>'{data,registeredResultCount}','1','exact direct Result derives its own artifact row');
select throws_ok($q$select api.cmd_final_result_release_seal_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash())$q$,'22023','Final Result selection is incomplete','partial selection cannot seal');
select is(api.cmd_final_result_release_members_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash(),'[{"uuid":"87920000-0000-4000-8000-000000000012","version":"01.00.000"}]')#>>'{data,registeredResultCount}','2','derived Result can select a second artifact without its unselected parent');
select throws_ok($q$select api.cmd_final_result_release_members_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash(),'[{"uuid":"87920000-0000-4000-8000-000000000011","version":"01.00.000"}]')$q$,'22023','Final Result selection exceeds the frozen count','oversized batch rolls back newly inserted membership');
select is(api.qry_final_result_release_v2('87930000-0000-4000-8000-000000000010')#>>'{data,registeredResultCount}','2','failed extension leaves selected membership unchanged');
select is(api.cmd_final_result_release_seal_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash())#>>'{data,selectionHash}','cada21d09411290414089d96661ee0bfd20a8909a930e21bb85a305d545259bc','selection matches independent Python exact-key block hash');
select is(api.cmd_final_result_release_seal_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash())#>>'{data,sealed}','true','seal retry preserves exact identity');
select is(api.cmd_final_result_release_members_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash(),'[{"uuid":"87920000-0000-4000-8000-000000000010","version":"01.00.000"}]')#>>'{data,registeredResultCount}','2','same member retry works after seal');
select throws_ok($q$select api.cmd_final_result_release_members_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash(),'[{"uuid":"87920000-0000-4000-8000-000000000011","version":"01.00.000"}]')$q$,'55000','Sealed final Result release selection is immutable','sealed membership cannot expand to other file-contained Results');
select is(api.qry_final_result_release_v2('87930000-0000-4000-8000-000000000010')#>>'{data,status}','prepared','selection seal does not claim reader readiness or approval');
select api.cmd_final_result_release_prepare_v2(pg_temp.final_release_plan(jsonb_build_object('releaseRunId','87930000-0000-4000-8000-000000000013','releaseVersion','2026.11.3','selectionHash',repeat('f',64),'selectionCount',1)),'wrong-hash');
select api.cmd_final_result_release_members_v2('87930000-0000-4000-8000-000000000013',encode(extensions.digest(convert_to(pg_temp.final_release_plan(jsonb_build_object('releaseRunId','87930000-0000-4000-8000-000000000013','releaseVersion','2026.11.3','selectionHash',repeat('f',64),'selectionCount',1)),'UTF8'),'sha256'),'hex'),'[{"uuid":"87920000-0000-4000-8000-000000000010","version":"01.00.000"}]');
select throws_ok($q$select api.cmd_final_result_release_seal_v2('87930000-0000-4000-8000-000000000013',encode(extensions.digest(convert_to(pg_temp.final_release_plan(jsonb_build_object('releaseRunId','87930000-0000-4000-8000-000000000013','releaseVersion','2026.11.3','selectionHash',repeat('f',64),'selectionCount',1)),'UTF8'),'sha256'),'hex'))$q$,'22023','Final Result selection hash mismatch','complete count cannot substitute for exact selection hash');
reset role;
select ok((select calculation_bundle_hash is null and calculation_bundle_ref is null and publication_format='final-result-pair.v2' from private.lca_release_runs where id='87930000-0000-4000-8000-000000000010'),'final Result release has no fabricated Bundle');
select is((select count(distinct artifact_id) from private.final_result_release_members where release_run_id='87930000-0000-4000-8000-000000000010'),2::bigint,'selection retains exact mapping across multiple artifacts');
select is((select count(*) from private.final_result_release_selection_seals where release_run_id='87930000-0000-4000-8000-000000000010'),1::bigint,'retry creates no duplicate selection seal');
select throws_ok($q$update private.lca_release_runs set publication_format='legacy-four-zip.v1' where id='87930000-0000-4000-8000-000000000010'$q$,'23514','lca_release_run_immutable_content','publication format cannot be rewritten after prepare');
select throws_ok($q$delete from private.final_result_release_members where release_run_id='87930000-0000-4000-8000-000000000010'$q$,'55000','Result query evidence is immutable','selection history cannot be deleted');
select is((select count(*) from private.lca_release_publications),0::bigint,'prepare/stage/seal never switch current publication');
delete from private.roles where user_id='87930000-0000-4000-8000-000000000001' and team_id='00000000-0000-0000-0000-000000000000';
set local role authenticated;
select is(api.qry_final_result_release_v2('87930000-0000-4000-8000-000000000010')->>'code','not_data_product_manager','readback rechecks live role after revocation');
select is(api.cmd_final_result_release_seal_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash())->>'code','not_data_product_manager','idempotent mutation retry also rechecks role');
reset role;
select * from finish();
rollback;
