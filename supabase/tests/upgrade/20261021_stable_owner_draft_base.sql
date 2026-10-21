-- Run only on the owned disposable local baseline BEFORE the new migration.
-- The matching head suite proves real historical duplicates survive the additive
-- upgrade. No new-trigger disabling is used to manufacture legacy data.
begin;
-- Network-only after-insert webhook is outside this database admission fixture;
-- keep every content/version/lifecycle trigger enabled.
alter table public.processes disable trigger process_extract_md_trigger_insert;
do $$begin
 if to_regprocedure('api.cmd_dataset_prepare_stable_draft(uuid,jsonb)') is not null then
   raise exception 'Stable draft upgrade fixture requires the canonical pre-migration baseline';
 end if;
 if exists(select 1 from auth.users where id='85510000-0000-4000-8000-000000000001') then
   raise exception 'Stable draft upgrade fixture identity already exists';
 end if;
end$$;
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
 raw_app_meta_data,raw_user_meta_data,created_at,updated_at,is_sso_user,is_anonymous)
values('00000000-0000-0000-0000-000000000000','85510000-0000-4000-8000-000000000001',
 'authenticated','authenticated','stable-upgrade-855@example.com','test-password-hash',now(),
 '{"provider":"email","providers":["email"]}','{}',now(),now(),false,false);
insert into public.contacts(id,json_ordered,user_id,state_code,rule_verification)
select '85510000-0000-4000-8000-000000000101',
 jsonb_build_object('contactDataSet',jsonb_build_object('administrativeInformation',
 jsonb_build_object('publicationAndOwnership',jsonb_build_object('common:dataSetVersion',v))),
 'fixture',jsonb_build_object('marker',v))::json,
 '85510000-0000-4000-8000-000000000001',s,true
from (values('01.00.000',100),('01.00.001',0),('01.00.002',0))x(v,s);
insert into public.sources(id,json_ordered,user_id,state_code,rule_verification)
select '85510000-0000-4000-8000-000000000102',
 jsonb_build_object('sourceDataSet',jsonb_build_object('administrativeInformation',
 jsonb_build_object('publicationAndOwnership',jsonb_build_object('common:dataSetVersion',v))),
 'fixture',jsonb_build_object('marker',v))::json,
 '85510000-0000-4000-8000-000000000001',0,true
from (values('01.00.000'),('01.00.001'))x(v);
-- Same typed UUID with a historical mixed model/standalone family is preserved
-- but refused by the new generic command. model_id is not native authentication.
insert into public.processes(id,json_ordered,user_id,state_code,model_id,model_version)
select '85510000-0000-4000-8000-000000000103',
 jsonb_build_object('processDataSet',jsonb_build_object('administrativeInformation',
 jsonb_build_object('publicationAndOwnership',jsonb_build_object('common:dataSetVersion',v))))::json,
 '85510000-0000-4000-8000-000000000001',s,m::uuid,mv
from (values('01.00.000',100,null::text,null::text),
 ('01.00.001',0,null,null),
 ('01.00.002',0,'85510000-0000-4000-8000-00000000f001','01.00.002'))x(v,s,m,mv);
insert into public.flows(id,json_ordered,user_id,state_code,rule_verification)
select '85510000-0000-4000-8000-000000000104',
 jsonb_build_object('flowDataSet',jsonb_build_object('administrativeInformation',
 jsonb_build_object('publicationAndOwnership',jsonb_build_object('common:dataSetVersion',v)),
 'modellingAndValidation',jsonb_build_object('LCIMethod',jsonb_build_object('typeOfDataSet',t))))::json,
 '85510000-0000-4000-8000-000000000001',s,true
from (values('01.00.000',100,'Product flow'),('01.00.001',0,'Product flow'),('01.00.002',0,'Elementary flow'))x(v,s,t);
insert into public.contacts(id,json_ordered,user_id,state_code,rule_verification)
select '85510000-0000-4000-8000-000000000105',
 jsonb_build_object('contactDataSet',jsonb_build_object('administrativeInformation',
 jsonb_build_object('publicationAndOwnership',jsonb_build_object('common:dataSetVersion',v))))::json,
 '85510000-0000-4000-8000-000000000001',s,true
from (values('01.00.000',100),('01.00.001',20))x(v,s);
create table private.stable_draft_855_upgrade_evidence as
select 'contacts'::text table_name,to_jsonb(c) row_data from public.contacts c where id in ('85510000-0000-4000-8000-000000000101','85510000-0000-4000-8000-000000000105')
union all select 'sources',to_jsonb(s) from public.sources s where id='85510000-0000-4000-8000-000000000102'
union all select 'processes',to_jsonb(p) from public.processes p where id='85510000-0000-4000-8000-000000000103'
union all select 'flows',to_jsonb(f) from public.flows f where id='85510000-0000-4000-8000-000000000104';
revoke all on private.stable_draft_855_upgrade_evidence from public,anon,authenticated,service_role;
alter table public.processes enable trigger process_extract_md_trigger_insert;
commit;
