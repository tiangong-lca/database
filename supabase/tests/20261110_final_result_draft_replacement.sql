begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,api,private,auth;
select no_plan();
\ir fixtures/final-result-release-setup.sql

select ok(not has_function_privilege('anon','api.qry_final_result_release_version_v2(text)','execute'),'version inspection denies anonymous');
select ok(not has_function_privilege('service_role','api.cmd_final_result_release_replace_v2(text,text,uuid,text)','execute'),'storage service cannot replace actor drafts');
select ok(not has_function_privilege('authenticated','private.final_result_prepare_draft(text,text,uuid,text)','execute'),'private prepare helper is not an actor escape hatch');
select ok((select bool_and(has_function_privilege('authenticated',sig,'execute') and not has_function_privilege('anon',sig,'execute') and not has_function_privilege('service_role',sig,'execute')) from (values('api.qry_final_result_release_version_v2(text)'),('api.qry_final_result_release_draft_v2(uuid)'),('api.cmd_final_result_release_replace_v2(text,text,uuid,text)')) f(sig)),'all three public seams preserve authenticated-only ACLs');
select ok((select not bool_or(has_function_privilege(actor,sig,'execute')) from (values('anon'),('authenticated'),('service_role')) a(actor) cross join (values('private.final_result_prepare_draft(text,text,uuid,text)'),('private.final_result_version_state(text)'),('private.final_result_version_error(text,text)'),('private.final_result_replacement_guard()'),('private.final_result_replacement_target_guard()')) f(sig)),'all private helpers and deferred guards are closed to caller roles');
set local role authenticated;
select set_config('request.jwt.claim.sub','87930000-0000-4000-8000-000000000002',true);
select is(api.qry_final_result_release_version_v2('2026.11.1')->>'code','not_data_product_manager','inspection requires current manager');
select set_config('request.jwt.claim.sub','87930000-0000-4000-8000-000000000001',true);
select is(api.qry_final_result_release_version_v2('2026.11.1')#>'{data,occupant}','null'::jsonb,'unoccupied version is explicit');
select is(api.qry_final_result_release_version_v2('invalid')->>'code','final_result_prepare_invalid','invalid version is typed');
select is(api.cmd_final_result_release_prepare_v2(pg_temp.final_release_plan(),'draft961-old')->>'ok','true','ordinary initial draft is prepared');
select api.cmd_final_result_release_members_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash(),
 '[{"uuid":"87920000-0000-4000-8000-000000000010","version":"01.00.000"},{"uuid":"87920000-0000-4000-8000-000000000012","version":"01.00.000"}]');
select api.cmd_final_result_release_seal_v2('87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash());
select is(api.qry_final_result_release_version_v2('2026.11.1')#>>'{data,occupant,releaseRunId}','87930000-0000-4000-8000-000000000010','preflight identifies occupied draft');
select is(api.qry_final_result_release_version_v2('2026.11.1')#>>'{data,occupant,replaceable}','true','sealed selection is still an unapproved draft');
select is(api.cmd_final_result_release_prepare_v2(pg_temp.final_release_plan('{"releaseRunId":"87930000-0000-4000-8000-000000000020"}'),'draft961-normal-conflict')->>'code','final_result_release_version_conflict','ordinary new run cannot silently adopt occupied version');
select is(api.cmd_final_result_release_replace_v2(pg_temp.final_release_plan('{"releaseRunId":"87930000-0000-4000-8000-000000000020"}'),'draft961-replace','87930000-0000-4000-8000-000000000010',repeat('f',64))->>'code','final_result_draft_replacement_conflict','stale predecessor hash rejected');
select throws_ok($q$select api.cmd_final_result_release_replace_v2(pg_temp.final_release_plan('{"releaseRunId":"87930000-0000-4000-8000-000000000020","candidateSha256":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}'),'draft961-bad-candidate','87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash())$q$,'22023','Final Result Candidate storage or selection count is invalid','invalid replacement Candidate does not retire old draft');
select is(api.qry_final_result_release_v2('87930000-0000-4000-8000-000000000010')#>>'{data,status}','prepared','failed admission leaves original usable');
select is(api.cmd_final_result_release_replace_v2(pg_temp.final_release_plan('{"releaseRunId":"87930000-0000-4000-8000-000000000020"}'),'draft961-replace','87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash())->>'ok','true','explicit same-version replacement succeeds atomically');
select is(api.cmd_final_result_release_replace_v2(pg_temp.final_release_plan('{"releaseRunId":"87930000-0000-4000-8000-000000000020"}'),'draft961-replace','87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash())->>'ok','true','lost acknowledgement replay returns same replacement');
select is(api.cmd_final_result_release_prepare_v2(pg_temp.final_release_plan('{"releaseRunId":"87930000-0000-4000-8000-000000000020"}'),'draft961-replace')->>'code','final_result_draft_replacement_conflict','replacement retry cannot omit confirmed predecessor');
select is(api.qry_final_result_release_version_v2('2026.11.1')#>>'{data,occupant,releaseRunId}','87930000-0000-4000-8000-000000000020','new draft owns version');
select is(api.qry_final_result_release_version_v2('2026.11.1')#>>'{data,occupant,replacesReleaseRunId}','87930000-0000-4000-8000-000000000010','version read carries immutable predecessor reference');
select is(api.qry_final_result_release_draft_v2('87930000-0000-4000-8000-000000000010')#>>'{data,replacedByReleaseRunId}','87930000-0000-4000-8000-000000000020','retired draft exposes its exact successor');
select is(api.qry_final_result_release_draft_v2('87930000-0000-4000-8000-000000000020')#>>'{data,replacesPublishPlanHash}',pg_temp.final_plan_hash(),'replacement history exposes exact predecessor hash');
select is(api.qry_final_result_release_v2('87930000-0000-4000-8000-000000000010')#>>'{data,status}','abandoned','old draft remains readable and retired');
select is(api.qry_final_result_release_v2('87930000-0000-4000-8000-000000000010')#>>'{data,selectionSealed}','true','old selection seal retained');
select is(api.cmd_final_result_release_replace_v2(pg_temp.final_release_plan('{"releaseRunId":"87930000-0000-4000-8000-000000000030"}'),'draft961-stale','87930000-0000-4000-8000-000000000010',pg_temp.final_plan_hash())->>'code','final_result_draft_replacement_conflict','second contender cannot replace an already replaced predecessor');
reset role;
select is((select count(*) from private.final_result_release_members where release_run_id='87930000-0000-4000-8000-000000000010'),2::bigint,'all original members retained');
select is((select count(*) from private.command_audit_log where command='cmd_final_result_release_replace_v2'),1::bigint,'replay does not duplicate replacement audit');
select throws_ok($q$update private.lca_release_runs set replaced_by_run_id=null where id='87930000-0000-4000-8000-000000000010'$q$,'23514','Only an unpublished unapproved draft may be replaced once','replacement link cannot be cleared');
select throws_ok($q$update private.lca_release_runs set release_version='2026.11.99' where id='87930000-0000-4000-8000-000000000010'$q$,'23514','lca_release_run_immutable_content','original version cannot be rewritten');
select throws_ok($q$delete from private.final_result_release_members where release_run_id='87930000-0000-4000-8000-000000000010'$q$,'55000','Result query evidence is immutable','replacement never permits history deletion');

-- An injected insert failure proves retirement, pointer and audit all roll back.
create function pg_temp.reject_replacement_insert() returns trigger language plpgsql as $$
begin
 if new.id='87930000-0000-4000-8000-000000000040' then raise exception using errcode='23514',message='synthetic insert failure'; end if;
 return new;
end $$;
create trigger draft961_injected_failure before insert on private.lca_release_runs for each row execute function pg_temp.reject_replacement_insert();
set local role authenticated;
select throws_ok($q$select api.cmd_final_result_release_replace_v2(pg_temp.final_release_plan('{"releaseRunId":"87930000-0000-4000-8000-000000000040"}'),'draft961-insert-failure','87930000-0000-4000-8000-000000000020',encode(extensions.digest(convert_to(pg_temp.final_release_plan('{"releaseRunId":"87930000-0000-4000-8000-000000000020"}'),'UTF8'),'sha256'),'hex'))$q$,'23514','synthetic insert failure','failure after retirement rolls back entire helper');
reset role;
select ok((select status='prepared' and replaced_by_run_id is null from private.lca_release_runs where id='87930000-0000-4000-8000-000000000020'),'injected failure restores active predecessor');
select ok(not exists(select 1 from private.lca_release_runs where id='87930000-0000-4000-8000-000000000040'),'injected failure leaves no new run');
drop trigger draft961_injected_failure on private.lca_release_runs;

select throws_ok($q$do $$begin
 update private.lca_release_runs set status='abandoned',replaced_by_run_id='87930000-0000-4000-8000-000000000010' where id='87930000-0000-4000-8000-000000000020';
 set constraints all immediate;
end; $$$q$,'23514','Replacement must create an exact same-version Final Result draft','existing retired history cannot be used as a successor or create a cycle');
select ok((select status='prepared' and replaced_by_run_id is null from private.lca_release_runs where id='87930000-0000-4000-8000-000000000020'),'failed fabricated cycle preserves current reservation');

-- Seed an approved-state history fixture; never invoke approval/activation.
update private.lca_release_runs set status='ready_for_approval' where id='87930000-0000-4000-8000-000000000020';
update private.lca_release_runs set status='approved' where id='87930000-0000-4000-8000-000000000020';
set local role authenticated;
select is(api.qry_final_result_release_version_v2('2026.11.1')#>>'{data,occupant,replaceable}','false','approved fixture is reserved');
select is(api.cmd_final_result_release_replace_v2(pg_temp.final_release_plan('{"releaseRunId":"87930000-0000-4000-8000-000000000030"}'),'draft961-approved-reject','87930000-0000-4000-8000-000000000020',encode(extensions.digest(convert_to(pg_temp.final_release_plan('{"releaseRunId":"87930000-0000-4000-8000-000000000020"}'),'UTF8'),'sha256'),'hex'))->>'code','final_result_draft_not_replaceable','approved history cannot be replaced');
reset role;
select is((select count(*) from private.lca_release_publications),0::bigint,'no publication created');
set constraints all immediate;
select * from finish();
rollback;
