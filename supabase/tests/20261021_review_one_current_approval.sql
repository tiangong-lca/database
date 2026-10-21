begin;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, auth;
select no_plan();

insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,is_sso_user,is_anonymous)
select '00000000-0000-0000-0000-000000000000'::uuid,
  ('18570000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,
  'authenticated','authenticated','review-857-' || n || '@example.com','synthetic',now(),
  '{"provider":"email","providers":["email"]}'::jsonb,'{}'::jsonb,now(),now(),false,false
from generate_series(1,4) n;
insert into private.users(id,raw_user_meta_data)
select id,'{}'::jsonb from auth.users where id::text like '18570000-%'
on conflict(id) do nothing;
insert into private.roles(user_id,team_id,role)
select ('18570000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,
 '00000000-0000-0000-0000-000000000000'::uuid,
 case when n=1 then 'review-admin' else 'review-member' end
from generate_series(1,4) n;

alter table public.contacts disable trigger contacts_json_sync_trigger;
alter table public.contacts disable trigger contact_dataset_extraction_trigger_insert;
alter table public.contacts disable trigger contact_dataset_extraction_trigger_update;
alter table public.contacts disable trigger contact_embedding_ft_on_extract_md_update;
insert into public.contacts(id,version,json,json_ordered,user_id,state_code,rule_verification)
select ('38570000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,'01.00.000',
 '{"contactDataSet":{"contactInformation":{"dataSetInformation":{"common:shortName":[{"@xml:lang":"en","#text":"Synthetic review 857"}]}}}}'::jsonb,
 '{"contactDataSet":{"contactInformation":{"dataSetInformation":{"common:shortName":[{"@xml:lang":"en","#text":"Synthetic review 857"}]}}}}'::jsonb,
 '18570000-0000-0000-0000-000000000001'::uuid,case when n=11 then 0 else 20 end,true
from generate_series(1,11) n;
insert into private.reviews(id,data_id,data_version,state_code,reviewer_id,json,review_kind,target_table,submitted_revision_checksum,target_owner_id)
select ('58570000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,
 ('38570000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,'01.00.000',
 case when n=8 then 0 else 1 end,
 case when n in(7,8) then '[]'::jsonb else '["18570000-0000-0000-0000-000000000002","18570000-0000-0000-0000-000000000003"]'::jsonb end,
 jsonb_build_object('data',jsonb_build_object('id','38570000-0000-0000-0000-' || lpad(n::text,12,'0'),'version','01.00.000','table','contacts'),'logs','[]'::jsonb),
 case when n=2 then 'reference' else 'root' end,'contacts',
 case when n=10 then repeat('0',64) else private.review_revision_fingerprint_v1('contacts',api.cmd_review_get_dataset_row('contacts',('38570000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,'01.00.000',false)) end,
 '18570000-0000-0000-0000-000000000001'::uuid
from generate_series(1,11) n;
insert into private.comments(review_id,reviewer_id,json,state_code)
select ('58570000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,
 '18570000-0000-0000-0000-000000000002'::uuid,'{}'::json,
 case when n in(1,2,10,11) then 1 when n=4 then -3 when n=5 then -2 else 0 end
from generate_series(1,11) n where n not in(7,8);
insert into private.comments(review_id,reviewer_id,json,state_code)
select ('58570000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,
 '18570000-0000-0000-0000-000000000003'::uuid,'{}'::json,
 case when n in(2,3,4) then -3 else 0 end
from generate_series(1,11) n where n not in(7,8);
insert into private.comments(review_id,reviewer_id,json,state_code) values
 ('58570000-0000-0000-0000-000000000006','18570000-0000-0000-0000-000000000004','{}',1);
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','18570000-0000-0000-0000-000000000001',true);

select is((select eligible from api.qry_review_batch_eligibility_v1(array['58570000-0000-0000-0000-000000000001'::uuid],'admin-approve'))::text, 'true', 'task 1 batch permits one approval with another pending');
select is((select eligible from api.qry_review_batch_eligibility_v1(array['58570000-0000-0000-0000-000000000002'::uuid],'admin-approve'))::text, 'true', 'task 2 batch permits an approval alongside a rejection');
select is((api.cmd_review_finalize_approve('58570000-0000-0000-0000-000000000003'::uuid,'{}'::jsonb)->>'code')::text, 'REVIEWER_APPROVAL_REQUIRED', 'task 3 finalization requires a current assigned approving opinion');
select is((select reason_code from api.qry_review_batch_eligibility_v1(array['58570000-0000-0000-0000-000000000003'::uuid],'admin-approve'))::text, 'REVIEWER_APPROVAL_REQUIRED', 'task 3 batch uses identical approval guard');
select is((api.cmd_review_finalize_approve('58570000-0000-0000-0000-000000000004'::uuid,'{}'::jsonb)->>'code')::text, 'REVIEWER_APPROVAL_REQUIRED', 'task 4 finalization requires a current assigned approving opinion');
select is((select reason_code from api.qry_review_batch_eligibility_v1(array['58570000-0000-0000-0000-000000000004'::uuid],'admin-approve'))::text, 'REVIEWER_APPROVAL_REQUIRED', 'task 4 batch uses identical approval guard');
select is((api.cmd_review_finalize_approve('58570000-0000-0000-0000-000000000005'::uuid,'{}'::jsonb)->>'code')::text, 'REVIEWER_APPROVAL_REQUIRED', 'task 5 finalization requires a current assigned approving opinion');
select is((select reason_code from api.qry_review_batch_eligibility_v1(array['58570000-0000-0000-0000-000000000005'::uuid],'admin-approve'))::text, 'REVIEWER_APPROVAL_REQUIRED', 'task 5 batch uses identical approval guard');
select is((api.cmd_review_finalize_approve('58570000-0000-0000-0000-000000000006'::uuid,'{}'::jsonb)->>'code')::text, 'REVIEWER_APPROVAL_REQUIRED', 'task 6 finalization requires a current assigned approving opinion');
select is((select reason_code from api.qry_review_batch_eligibility_v1(array['58570000-0000-0000-0000-000000000006'::uuid],'admin-approve'))::text, 'REVIEWER_APPROVAL_REQUIRED', 'task 6 batch uses identical approval guard');
select is((api.cmd_review_finalize_approve('58570000-0000-0000-0000-000000000007'::uuid,'{}'::jsonb)->>'code')::text, 'REVIEWER_REQUIRED', 'no reviewers still blocks finalization');
select is((api.cmd_review_finalize_approve('58570000-0000-0000-0000-000000000010'::uuid,'{}'::jsonb)->>'code')::text, 'REVISION_CHECKSUM_MISMATCH', 'revision mismatch remains blocked');
select is((api.cmd_review_finalize_approve('58570000-0000-0000-0000-000000000011'::uuid,'{}'::jsonb)->>'code')::text, 'REVIEW_TARGET_NOT_IN_REVIEW', 'invalid target state remains blocked');
select set_config('request.jwt.claim.sub','18570000-0000-0000-0000-000000000002',true);
select is((api.cmd_review_finalize_approve('58570000-0000-0000-0000-000000000001'::uuid,'{}'::jsonb)->>'code')::text, 'REVIEW_ADMIN_REQUIRED', 'reviewer cannot finalize even with an approving opinion');
select set_config('request.jwt.claim.sub','18570000-0000-0000-0000-000000000001',true);
select is((api.cmd_review_finalize_approve('58570000-0000-0000-0000-000000000001'::uuid,'{}'::jsonb)->>'ok')::text, 'true', 'task 1 finalizes without waiting for another reviewer');
select is((select state_code from public.contacts where id='38570000-0000-0000-0000-000000000001')::text, '100', 'task 1 publishes only its exact target');
select is((select state_code from private.reviews where id='58570000-0000-0000-0000-000000000001'::uuid)::text, '2', 'task 1 becomes finalized');
select is((select state_code from private.comments where review_id='58570000-0000-0000-0000-000000000001'::uuid and reviewer_id='18570000-0000-0000-0000-000000000003')::text, '2', 'task 1 retains existing pending-comment finalization behavior');
select is((api.cmd_review_finalize_approve('58570000-0000-0000-0000-000000000001'::uuid,'{}'::jsonb)->>'code')::text, 'INVALID_REVIEW_STATE', 'task 1 cannot be finalized again');
select is((api.cmd_review_finalize_approve('58570000-0000-0000-0000-000000000002'::uuid,'{}'::jsonb)->>'ok')::text, 'true', 'task 2 finalizes with mixed opinions');
select is((select state_code from public.contacts where id='38570000-0000-0000-0000-000000000002')::text, '100', 'task 2 publishes only its exact target');
select is((select state_code from private.reviews where id='58570000-0000-0000-0000-000000000002'::uuid)::text, '2', 'task 2 becomes finalized');
select is((select state_code from private.comments where review_id='58570000-0000-0000-0000-000000000002'::uuid and reviewer_id='18570000-0000-0000-0000-000000000003')::text, '2', 'task 2 retains existing pending-comment finalization behavior');
select is((api.cmd_review_finalize_approve('58570000-0000-0000-0000-000000000002'::uuid,'{}'::jsonb)->>'code')::text, 'INVALID_REVIEW_STATE', 'task 2 cannot be finalized again');
select is((select eligible from api.qry_review_batch_eligibility_v1(array['58570000-0000-0000-0000-000000000008'::uuid],'admin-reject'))::text, 'true', 'task 8 rejection does not require opinions');
select is((api.cmd_review_finalize_reject('58570000-0000-0000-0000-000000000008'::uuid,'repair synthetic fixture','{}'::jsonb)->>'ok')::text, 'true', 'task 8 can be rejected immediately');
select is((select state_code from public.contacts where id='38570000-0000-0000-0000-000000000008')::text, '0', 'task 8 rejection returns only its target to draft');
select is((select eligible from api.qry_review_batch_eligibility_v1(array['58570000-0000-0000-0000-000000000009'::uuid],'admin-reject'))::text, 'true', 'task 9 rejection does not require opinions');
select is((api.cmd_review_finalize_reject('58570000-0000-0000-0000-000000000009'::uuid,'repair synthetic fixture','{}'::jsonb)->>'ok')::text, 'true', 'task 9 can be rejected immediately');
select is((select state_code from public.contacts where id='38570000-0000-0000-0000-000000000009')::text, '0', 'task 9 rejection returns only its target to draft');
select is((has_function_privilege('authenticated','private.review_assert_current_approval_v1(private.reviews)','EXECUTE'))::text, 'false', 'browser cannot execute private approval helper');
select is((has_function_privilege('service_role','private.review_assert_current_approval_v1(private.reviews)','EXECUTE'))::text, 'false', 'service role gains no helper authority');

select * from finish();
rollback;
