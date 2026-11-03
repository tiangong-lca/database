begin;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, auth;
select plan(17);

-- Synthetic identities only. Authoring projection/webhook effects are not the
-- subject of this fixture; normal command and resolver guards remain enabled.
insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, is_sso_user, is_anonymous)
values
  ('19601000-0000-0000-0000-000000000001','authenticated','authenticated',
   'scope-reviewer@example.invalid','test',now(),
   '{"provider":"email","providers":["email"]}','{}',now(),now(),false,false),
  ('19601000-0000-0000-0000-000000000002','authenticated','authenticated',
   'scope-owner@example.invalid','test',now(),
   '{"provider":"email","providers":["email"]}','{}',now(),now(),false,false);
insert into private.users (id, raw_user_meta_data)
values ('19601000-0000-0000-0000-000000000001','{}'),
       ('19601000-0000-0000-0000-000000000002','{}')
on conflict (id) do nothing;
insert into private.teams (id,json,rank,is_public)
values ('00000000-0000-0000-0000-000000000000','{"name":"System Team"}',0,false)
on conflict (id) do nothing;
insert into private.roles (user_id,team_id,role)
values ('19601000-0000-0000-0000-000000000001',
 '00000000-0000-0000-0000-000000000000','review-member');

set local session_replication_role = replica;
insert into public.sources (id,version,json,json_ordered,user_id,state_code,rule_verification)
values ('39601000-0000-0000-0000-000000000001','01.01.000',
 '{"sourceDataSet":{"sourceInformation":{"dataSetInformation":{"referenceToDigitalFile":{"@uri":"../external_docs/synthetic/rejection.pdf"}}}}}',
 '{"sourceDataSet":{"sourceInformation":{"dataSetInformation":{"referenceToDigitalFile":{"@uri":"../external_docs/synthetic/rejection.pdf"}}}}}',
 '19601000-0000-0000-0000-000000000001',0,true);
insert into public.processes (id,version,json,json_ordered,user_id,state_code,rule_verification)
values ('49601000-0000-0000-0000-000000000001','01.01.000',
 '{"processDataSet":{"processInformation":{"dataSetInformation":{"common:UUID":"49601000-0000-0000-0000-000000000001"}}}}',
 '{"processDataSet":{"processInformation":{"dataSetInformation":{"common:UUID":"49601000-0000-0000-0000-000000000001"}}}}',
 '19601000-0000-0000-0000-000000000002',20,true);
set local session_replication_role = origin;

insert into private.reviews (id,data_id,data_version,state_code,reviewer_id,json,
 review_kind,target_table,submitted_revision_checksum,target_owner_id)
values ('59601000-0000-0000-0000-000000000001',
 '49601000-0000-0000-0000-000000000001','01.01.000',1,
 '["19601000-0000-0000-0000-000000000001"]','{"logs":[]}',
 'root','processes',repeat('a',64),'19601000-0000-0000-0000-000000000002');

create temporary table opinion(payload jsonb);
insert into opinion values ('{"modellingAndValidation":{"validation":{"review":[{"@type":"Not reviewed","common:referenceToCompleteReviewReport":{"@type":"source data set","@refObjectId":"39601000-0000-0000-0000-000000000001","@version":"01.01.000","@uri":"../sources/39601000-0000-0000-0000-000000000001.xml","common:shortDescription":{"@xml:lang":"en","#text":"Synthetic report"}}}]}}}');
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','19601000-0000-0000-0000-000000000001',true);
set local role authenticated;
-- Real reviewer rejection follows the same path as the observed failure.
select is(api.cmd_review_submit_comment(
 '59601000-0000-0000-0000-000000000001',
 '{"modellingAndValidation":{"validation":{"review":[{"@type":"Not reviewed","common:referenceToCompleteReviewReport":{"@type":"source data set","@refObjectId":"39601000-0000-0000-0000-000000000001","@version":"01.01.000","@uri":"../sources/39601000-0000-0000-0000-000000000001.xml","common:shortDescription":{"@xml:lang":"en","#text":"Synthetic report"}}}]}}}',
 -3,'{}')->>'ok','true','assigned member submits rejection opinion');
select lives_ok($$select * from api.qry_root_review_reference_progress_v2(
 '59601000-0000-0000-0000-000000000001')$$,
 'member progress remains readable after rejection with an unpublished report');
reset role;
select is((select state_code from private.comments
 where review_id='59601000-0000-0000-0000-000000000001'),-3,
 'rejection remains submitted, without changing lifecycle state');
select is((select count(*)::integer from private.reviews where review_kind='reference'),0,
 'rejection creates no Reference Review');
select is((select state_code from public.sources
 where id='39601000-0000-0000-0000-000000000001'),0,
 'report remains an unpublished owner draft');
select is((select count(*)::integer from private.review_resolve_current_reference_targets_v1(
 array['59601000-0000-0000-0000-000000000001'::uuid])),0,
 'rejection opinion creates no derived dependency');
select is((select count(*)::integer from private.review_derive_current_references_v1(
 array['59601000-0000-0000-0000-000000000001'::uuid])),0,
 'rejection report does not require a current Reference Review');

-- Exact dependency guards still apply to real Root JSON even if that identity
-- is also present in a rejected Comment.
set local session_replication_role = replica;
update public.processes set json=(select payload from opinion),
 json_ordered=(select payload::json from opinion)
where id='49601000-0000-0000-0000-000000000001';
set local session_replication_role = origin;
select throws_ok($$select * from private.review_derive_current_references_v1(
 array['59601000-0000-0000-0000-000000000001'::uuid])$$,
 '55000','MISSING_CURRENT_REFERENCE_REVIEW',
 'same report identity remains required when actual Root JSON references it');
set local session_replication_role = replica;
update public.processes set json='{}',json_ordered='{}'
where id='49601000-0000-0000-0000-000000000001';
set local session_replication_role = origin;

-- Draft, revoked and terminal rejected comments never acquire dependencies.
update private.comments set state_code=0
where review_id='59601000-0000-0000-0000-000000000001';
select is((select count(*)::integer from private.review_resolve_current_reference_targets_v1(
 array['59601000-0000-0000-0000-000000000001'::uuid])),0,'draft comment stays excluded');
update private.comments set state_code=-2
where review_id='59601000-0000-0000-0000-000000000001';
select is((select count(*)::integer from private.review_resolve_current_reference_targets_v1(
 array['59601000-0000-0000-0000-000000000001'::uuid])),0,'revoked comment stays excluded');
update private.comments set state_code=-1
where review_id='59601000-0000-0000-0000-000000000001';
select is((select count(*)::integer from private.review_resolve_current_reference_targets_v1(
 array['59601000-0000-0000-0000-000000000001'::uuid])),0,'terminal rejected comment stays excluded');

-- Approving submissions and retained finalized-comment compatibility keep the
-- exact-reference guard, including report Sources; this is not a report-key filter.
update private.comments set state_code=1
where review_id='59601000-0000-0000-0000-000000000001';
select throws_ok($$select * from private.review_derive_current_references_v1(
 array['59601000-0000-0000-0000-000000000001'::uuid])$$,
 '55000','MISSING_CURRENT_REFERENCE_REVIEW','approval metadata still requires an exact current reference');
update private.comments set state_code=2
where review_id='59601000-0000-0000-0000-000000000001';
select throws_ok($$select * from private.review_derive_current_references_v1(
 array['59601000-0000-0000-0000-000000000001'::uuid])$$,
 '55000','MISSING_CURRENT_REFERENCE_REVIEW','retained finalized-comment compatibility still requires an exact current reference');
update private.comments set state_code=-3
where review_id='59601000-0000-0000-0000-000000000001';

set local role authenticated;
select is(api.cmd_review_submit_comment(
 '59601000-0000-0000-0000-000000000001',
 '{"modellingAndValidation":{"validation":{"review":[{"@type":"Not reviewed","common:referenceToCompleteReviewReport":{"@type":"source data set","@refObjectId":"39601000-0000-0000-0000-000000000001","@version":"01.01.000","@uri":"../sources/39601000-0000-0000-0000-000000000001.xml","common:shortDescription":{"@xml:lang":"en","#text":"Synthetic report"}}}]}}}',
 1,'{}')->>'ok','true','subsequent approving submission provisions required references');
reset role;
select is((select count(*)::integer from private.review_derive_current_references_v1(
 array['59601000-0000-0000-0000-000000000001'::uuid])),1,
 'approved Comment derives its provisioned exact reference');
select is((select data_version::text from private.review_derive_current_references_v1(
 array['59601000-0000-0000-0000-000000000001'::uuid])),'01.01.000',
 'approval reference uses the exact version');
update private.comments set state_code=-3
where review_id='59601000-0000-0000-0000-000000000001';
select is((select count(*)::integer from private.review_derive_current_references_v1(
 array['59601000-0000-0000-0000-000000000001'::uuid])),0,
 'changing an opinion back to rejection revokes relationship without deleting reference history');
select * from finish();
rollback;
