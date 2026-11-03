begin;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, auth;
select no_plan();

-- Synthetic identities only. Authoring projection/webhook effects are not the
-- subject of this fixture; normal command and resolver guards remain enabled.
insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, is_sso_user, is_anonymous)
values
  ('19609000-0000-0000-0000-000000000001','authenticated','authenticated',
   'scope-reviewer@example.invalid','test',now(),
   '{"provider":"email","providers":["email"]}','{}',now(),now(),false,false),
  ('19609000-0000-0000-0000-000000000002','authenticated','authenticated',
   'scope-owner@example.invalid','test',now(),
   '{"provider":"email","providers":["email"]}','{}',now(),now(),false,false);
insert into private.users (id, raw_user_meta_data)
values ('19609000-0000-0000-0000-000000000001','{}'),
       ('19609000-0000-0000-0000-000000000002','{}')
on conflict (id) do nothing;
insert into private.teams (id,json,rank,is_public)
values ('00000000-0000-0000-0000-000000000000','{"name":"System Team"}',0,false)
on conflict (id) do nothing;
insert into private.roles (user_id,team_id,role)
values ('19609000-0000-0000-0000-000000000001',
 '00000000-0000-0000-0000-000000000000','review-member');

set local session_replication_role = replica;
insert into public.sources (id,version,json,json_ordered,user_id,state_code,rule_verification)
values ('39609000-0000-0000-0000-000000000001','01.01.000',
 '{"sourceDataSet":{"sourceInformation":{"dataSetInformation":{"referenceToDigitalFile":{"@uri":"../external_docs/synthetic/rejection.pdf"}}}}}',
 '{"sourceDataSet":{"sourceInformation":{"dataSetInformation":{"referenceToDigitalFile":{"@uri":"../external_docs/synthetic/rejection.pdf"}}}}}',
 '19609000-0000-0000-0000-000000000001',0,true);
insert into public.processes (id,version,json,json_ordered,user_id,state_code,rule_verification)
values ('49609000-0000-0000-0000-000000000001','01.01.000',
 '{"processDataSet":{"processInformation":{"dataSetInformation":{"common:UUID":"49609000-0000-0000-0000-000000000001"}}}}',
 '{"processDataSet":{"processInformation":{"dataSetInformation":{"common:UUID":"49609000-0000-0000-0000-000000000001"}}}}',
 '19609000-0000-0000-0000-000000000002',20,true);
set local session_replication_role = origin;

insert into private.reviews (id,data_id,data_version,state_code,reviewer_id,json,
 review_kind,target_table,submitted_revision_checksum,target_owner_id)
values ('59609000-0000-0000-0000-000000000001',
 '49609000-0000-0000-0000-000000000001','01.01.000',1,
 '["19609000-0000-0000-0000-000000000001"]','{"logs":[]}',
 'root','processes',repeat('a',64),'19609000-0000-0000-0000-000000000002');

-- The real comment command runs under the assigned actor; invalid submissions roll back.
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','19609000-0000-0000-0000-000000000001',true);
set local role authenticated;
select is(api.cmd_review_save_comment_draft(
 '59609000-0000-0000-0000-000000000001',
 '{"modellingAndValidation":{"validation":{"review":[{"@type":"Not reviewed","common:referenceToCompleteReviewReport":{"common:shortDescription":[]}}]}}}', '{}')->>'ok','true','draft command accepts untouched optional report');
reset role;
select is((select json::jsonb #> '{modellingAndValidation,validation,review,0}' from private.comments where review_id='59609000-0000-0000-0000-000000000001'), '{"@type":"Not reviewed"}'::jsonb, 'draft is persisted without an empty report reference');
set local role authenticated;
select throws_ok($$select api.cmd_review_submit_comment(
 '59609000-0000-0000-0000-000000000001',
 '{"modellingAndValidation":{"validation":{"review":[{"@type":"Not reviewed","common:scope":{"@name":"单一操作单元过程","common:method":{"@name":"数据源验证"}}}]}}}',1,'{}')$$,
 '22023','REVIEW_METADATA_INVALID','translated scope and method values cannot be submitted');
reset role;
select is((select state_code from private.comments where review_id='59609000-0000-0000-0000-000000000001'),0,'invalid submission preserves prior draft state');
select is((select json::jsonb #> '{modellingAndValidation,validation,review,0}' from private.comments where review_id='59609000-0000-0000-0000-000000000001'), '{"@type":"Not reviewed"}'::jsonb, 'invalid submission preserves prior draft content');
set local role authenticated;
select is(api.cmd_review_submit_comment(
 '59609000-0000-0000-0000-000000000001',
 '{"comment":{"message":"Please correct the scope"},"modellingAndValidation":{"validation":{"review":[{"common:scope":{"@name":"单一操作单元过程"}}]}}}',-3,'{}')->>'ok','true','rejection permits incomplete or invalid review metadata');
reset role;
select is((select state_code from private.comments where review_id='59609000-0000-0000-0000-000000000001'),-3,'rejection remains a rejection');
select is((select count(*)::integer from private.reviews where review_kind='reference'),0,'failed approval and rejection create no reference review');
set local role authenticated;
select throws_ok($$select api.cmd_review_submit_comment(
 '59609000-0000-0000-0000-000000000001',
 '{"modellingAndValidation":{"validation":{"review":[{"@type":"Not reviewed","common:scope":{"@name":"单一操作单元过程"},"common:referenceToCompleteReviewReport":{"@type":"source data set","@refObjectId":"39609000-0000-0000-0000-000000000001","@version":"01.01.000","@uri":"../sources/39609000-0000-0000-0000-000000000001.xml","common:shortDescription":{"@xml:lang":"en","#text":"Synthetic report"}}}]}}}',1,'{}')$$,
 '22023','REVIEW_METADATA_INVALID','failed validation rolls back earlier reference provisioning');
reset role;
select is((select count(*)::integer from private.reviews where review_kind='reference'),0,'no reference review survives failed submission');
select is((select state_code from public.sources where id='39609000-0000-0000-0000-000000000001'),0,'source state is rolled back with the rejected comment');
set local role authenticated;
select is(api.cmd_review_submit_comment('59609000-0000-0000-0000-000000000001','{"modellingAndValidation":{"validation":{"review":{"@type":"Not reviewed"}}}}',1,'{}')->>'ok','true','valid approval command still succeeds');
reset role;
select is((select state_code from private.comments where review_id='59609000-0000-0000-0000-000000000001'),1,'valid approval persists submitted state');


select lives_ok($$select private.review_assert_metadata_v1('{"validation":{"review":{"@type":"Not reviewed"}}}','processes')$$,'valid singleton review is accepted');
select lives_ok($$select private.review_assert_metadata_v1('{"validation":{"review":[{"@type":"Not reviewed"},{"@type":"Not reviewed"}]}}','processes')$$,'ordered repeated reviews are accepted');
select throws_ok($$select private.review_assert_metadata_v1('{"validation":{"review":{"@type":"Not reviewed","common:referenceToCompleteReviewReport":{"common:shortDescription":{"@xml:lang":"en","#text":"Unselected report"}}}}}','processes')$$,'22023','REVIEW_METADATA_INVALID','a meaningful partial reference is rejected, never silently dropped');
select throws_ok($$select private.review_assert_metadata_v1('{"validation":{"review":{"@type":"Not reviewed","common:scope":{"@name":"Documentation","common:method":{"@name":"数据源验证"}}}}}','processes')$$,'22023','REVIEW_METADATA_INVALID','translated method alone is rejected');
select throws_ok($$select private.review_assert_metadata_v1('{"complianceDeclarations":{"compliance":{"common:approvalOfOverallCompliance":"完全符合"}}}','processes')$$,'22023','REVIEW_METADATA_INVALID','invalid compliance is rejected');
select is(private.review_clean_metadata_v1('{"a":{},"b":[],"c":null,"d":"  ","e":false,"f":0,"g":{"h":[null,{"@type":"Not reviewed"}]}}'),'{"e":false,"f":0,"g":{"h":[{"@type":"Not reviewed"}]}}'::jsonb,'cleanup preserves values and array order');
select throws_ok($$select api.cmd_review_apply_mv_payload('processes','49609000-0000-0000-0000-000000000001','01.01.000','[{"@type":"Not reviewed","common:scope":{"@name":"单一操作单元过程"}}]','[]')$$,'22023','REVIEW_METADATA_INVALID','final writeback rejects malformed previously saved opinions');
select ok((select json::jsonb #> '{processDataSet,modellingAndValidation}' is null from public.processes where id='49609000-0000-0000-0000-000000000001'),'failed writeback leaves dataset content untouched');
-- External webhooks require deployed Vault bindings and are outside this SQL fixture.
-- Disable only those dispatch triggers; the review immutability guard stays active.
do $fixture$
declare v_name text;
begin
  for v_name in select tgname from pg_trigger where tgrelid='public.processes'::regclass
    and tgfoid='util.invoke_edge_webhook()'::regprocedure loop
    execute format('alter table public.processes disable trigger %I',v_name);
  end loop;
end;
$fixture$;
select set_config('app.review_controlled_write','on',true);
select lives_ok($$select api.cmd_review_apply_mv_payload('processes','49609000-0000-0000-0000-000000000001','01.01.000','[{"@type":"Not reviewed","common:referenceToCompleteReviewReport":{"common:shortDescription":[]}}]','[]')$$,'final writeback cleans old empty selectors');
select is((select json::jsonb #> '{processDataSet,modellingAndValidation,validation,review}' from public.processes where id='49609000-0000-0000-0000-000000000001'),'[{"@type":"Not reviewed"}]'::jsonb,'final dataset contains only normalized review metadata');
select is((select json::jsonb from public.processes where id='49609000-0000-0000-0000-000000000001'),(select json_ordered::jsonb from public.processes where id='49609000-0000-0000-0000-000000000001'),'both dataset JSON representations stay synchronized');
select set_config('app.review_controlled_write','off',true);
select ok(not has_function_privilege('authenticated','private.review_assert_metadata_v1(jsonb,text)','execute'),'validation helper is not a new client RPC');
select lives_ok($$select private.review_assert_metadata_v1('{"validation":{"review":[{"common:referenceToNameOfReviewerAndInstitution":{"@type":"contact data set","@refObjectId":"19609000-0000-0000-0000-000000000001","@version":"01.01.000","@uri":"../contacts/synthetic.xml","common:shortDescription":{"@xml:lang":"en","#text":"Synthetic reviewer"}}}]}}','lifecyclemodels')$$,'valid LifecycleModel review uses its own schema');
select throws_ok($$select private.review_assert_metadata_v1('{"validation":{"review":{"common:referenceToCompleteReviewReport":{"common:shortDescription":{"@xml:lang":"en","#text":"Partial report"}}}}}','lifecyclemodels')$$,'22023','REVIEW_METADATA_INVALID','LifecycleModel partial references also fail closed');
select * from finish();
rollback;
