-- Caller owns BEGIN / pgTAP / ROLLBACK. Synthetic Candidate and actor setup only.
\ir final-result-candidate-setup.sql
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
