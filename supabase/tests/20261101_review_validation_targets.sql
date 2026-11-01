begin;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, auth;
select no_plan();

-- Contain outbound extraction while retaining normal database guards. This
-- replacement and every fixture are rolled back at the end of the test.
create or replace function util.invoke_edge_function(
  name text, body jsonb, timeout_milliseconds integer default 300000
) returns void language plpgsql security definer set search_path = '' as $$
begin
  return;
end;
$$;

-- Synthetic fixtures bypass derivative creation only during setup. All normal
-- table triggers are enabled before the authenticated commands execute.
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,is_sso_user,is_anonymous)
select '00000000-0000-0000-0000-000000000000'::uuid,
  ('18800002-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,
  'authenticated','authenticated','review-880-' || n || '@example.com','synthetic',now(),
  '{"provider":"email","providers":["email"]}'::jsonb,'{}'::jsonb,now(),now(),false,false
from generate_series(1,2) n;
insert into private.users(id,raw_user_meta_data)
select id,'{}'::jsonb from auth.users where id::text like '18800002-%'
on conflict(id) do nothing;

alter table public.contacts disable trigger user;
alter table public.processes disable trigger user;
alter table public.lifecyclemodels disable trigger user;

-- Two standalone roots share a draft dependency and published dependencies.
-- The last root has an accessible dependency ordered before an inaccessible one.
insert into public.contacts(id,version,json,json_ordered,user_id,state_code,rule_verification,modified_at,reviews)
select ('38800002-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,'01.00.000',
  case when n in (1,2) then
    '{"refs":[{"@type":"contact data set","@refObjectId":"38800002-0000-0000-0000-000000000003","@version":"01.00.000"},{"@type":"contact data set","@refObjectId":"38800002-0000-0000-0000-000000000004","@version":"01.00.000"},{"@type":"contact data set","@refObjectId":"38800002-0000-0000-0000-000000000005","@version":"01.00.000"}]}'::jsonb
  when n=6 then
    '{"refs":[{"@type":"contact data set","@refObjectId":"38800002-0000-0000-0000-000000000007","@version":"01.00.000"},{"@type":"contact data set","@refObjectId":"38800002-0000-0000-0000-000000000008","@version":"01.00.000"}]}'::jsonb
  else '{}'::jsonb end,
  '{}'::json,
  case when n=5 then null when n=8 then '18800002-0000-0000-0000-000000000002'::uuid else '18800002-0000-0000-0000-000000000001'::uuid end,
  case when n=4 then 100 when n=5 then 100 when n in (2,3) then null else 0 end,
  true,'2000-01-01'::timestamptz,'[]'::jsonb
from generate_series(1,8) n;

-- The same UUID has a published historical result at the Model's version and
-- a current draft result at a different version. Other results include a legacy
-- null model_version row, a second current result, and an unrelated Model version.
insert into public.lifecyclemodels(id,version,json,json_ordered,json_tg,user_id,state_code,rule_verification,reviews,modified_at)
values ('48800002-0000-0000-0000-000000000001','01.00.000',
  '{"lifeCycleModelDataSet":{"lifeCycleModelInformation":{"dataSetInformation":{"referenceToResultingProcess":[{"@type":"process data set","@refObjectId":"48800002-0000-0000-0000-000000000001","@version":"02.00.000"},{"@type":"process data set","@refObjectId":"48800002-0000-0000-0000-000000000002","@version":"03.00.000"}]}}}}',
  '{}','{"selected":"stale frontend value"}','18800002-0000-0000-0000-000000000001',0,true,'[]','2000-01-01');
insert into public.processes(id,version,json,json_ordered,user_id,state_code,model_id,model_version,rule_verification,reviews,modified_at)
values
 ('48800002-0000-0000-0000-000000000001','01.00.000','{}','{}','18800002-0000-0000-0000-000000000001',100,'48800002-0000-0000-0000-000000000001','01.00.000',true,'[]','2000-01-01'),
 ('48800002-0000-0000-0000-000000000001','02.00.000','{}','{}','18800002-0000-0000-0000-000000000001',0,'48800002-0000-0000-0000-000000000001','01.00.000',true,'[]','2000-01-01'),
 ('48800002-0000-0000-0000-000000000002','03.00.000','{}','{}','18800002-0000-0000-0000-000000000001',0,'48800002-0000-0000-0000-000000000001','01.00.000',true,'[]','2000-01-01'),
 ('48800002-0000-0000-0000-000000000003','01.00.000','{}','{}','18800002-0000-0000-0000-000000000001',0,'48800002-0000-0000-0000-000000000001',null,true,'[]','2000-01-01'),
 ('48800002-0000-0000-0000-000000000004','04.00.000','{}','{}','18800002-0000-0000-0000-000000000001',0,'48800002-0000-0000-0000-000000000001','02.00.000',true,'[]','2000-01-01'),
 ('48800002-0000-0000-0000-000000000005','01.00.000','{}','{}','18800002-0000-0000-0000-000000000001',200,'48800002-0000-0000-0000-000000000001','01.00.000',true,'[]','2000-01-01');

alter table public.contacts enable trigger user;
alter table public.processes enable trigger user;
alter table public.lifecyclemodels enable trigger user;

create temporary table issue880_immutable_rows as
select 'contacts'::text as table_name,to_jsonb(c) as row_data from public.contacts c where id::text like '38800002-%' and state_code>=100
union all
select 'processes',to_jsonb(p) from public.processes p where id::text like '48800002-%' and (state_code>=100 or model_version='02.00.000');
create temporary table issue880_updates(table_name text,id uuid,version text);
create function pg_temp.issue880_capture_update() returns trigger language plpgsql as $$
begin
  insert into issue880_updates values(TG_TABLE_NAME,new.id,new.version);
  return new;
end;
$$;
create trigger issue880_capture_update after update on public.contacts for each row execute function pg_temp.issue880_capture_update();
create trigger issue880_capture_update after update on public.processes for each row execute function pg_temp.issue880_capture_update();

create temporary table issue880_results(label text,result jsonb);
grant insert on issue880_results to authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','18800002-0000-0000-0000-000000000001',true);
set local role authenticated;
insert into issue880_results values('standalone',api.cmd_review_submit('contacts','38800002-0000-0000-0000-000000000001','01.00.000','{}'));
insert into issue880_results values('shared',api.cmd_review_submit('contacts','38800002-0000-0000-0000-000000000002','01.00.000','{}'));
insert into issue880_results values('model',api.cmd_review_submit('lifecyclemodels','48800002-0000-0000-0000-000000000001','01.00.000','{}'));
reset role;

select is((select result->>'ok' from issue880_results where label='standalone'),'true','standalone owner draft with published support submits through the authenticated command');
select is((select result #>> '{data,reviewKind}' from issue880_results where label='standalone'),'root','standalone submission retains the root review contract');
select is((select result->>'ok' from issue880_results where label='shared'),'true','a second legacy null-state root may share the pending reference');
select is((select state_code from public.contacts where id='38800002-0000-0000-0000-000000000002'),20,'legacy null root state follows the command’s existing draft normalization');
select is((select state_code from public.contacts where id='38800002-0000-0000-0000-000000000003'),20,'legacy null dependency state is normalized consistently when mutated');
select is((select count(*)::integer from private.reviews where review_kind='reference' and data_id='38800002-0000-0000-0000-000000000003'),1,'shared pending support reuses one exact Reference Review');
select is((select jsonb_array_length(reviews) from public.contacts where id='38800002-0000-0000-0000-000000000003'),2,'shared pending support retains both root candidate hints');
select is((select result->>'ok' from issue880_results where label='model'),'true','Model submission handles same-UUID different-version and multiple results');
select is((select count(*)::integer from public.processes where id::text like '48800002-%' and state_code=20),3,'all three current relational results including legacy ownership enter review');
select is((select count(*)::integer from private.reviews where review_kind='reference' and target_table='processes' and data_id::text like '48800002-%'),3,'only current unpublished Model results receive Reference Reviews');
select is((select count(*)::integer from issue880_updates u join issue880_immutable_rows b on b.table_name=u.table_name and b.row_data->>'id'=u.id::text and b.row_data->>'version'=u.version),0,'published support, historical siblings and other Model versions receive no UPDATE at all');
select ok(not exists(
  select 1 from issue880_immutable_rows b
  left join lateral (
    select to_jsonb(c) row_data from public.contacts c where b.table_name='contacts' and c.id=(b.row_data->>'id')::uuid and c.version=b.row_data->>'version'
    union all
    select to_jsonb(p) from public.processes p where b.table_name='processes' and p.id=(b.row_data->>'id')::uuid and p.version=b.row_data->>'version'
  ) current_row on true
  where b.row_data is distinct from current_row.row_data
),'validation-only and historical rows remain byte-equivalent as JSON including modified_at and reviews');
select ok(not exists(
  select 1 from private.reviews r join issue880_immutable_rows b
    on r.target_table=b.table_name and r.data_id=(b.row_data->>'id')::uuid and btrim(r.data_version)=b.row_data->>'version'
),'validation-only and historical rows acquire no review membership');
select is((select jsonb_array_length(result #> '{data,affectedDatasets}') from issue880_results where label='standalone'),2,'affectedDatasets contains only the mutable root and draft dependency');
select is((select jsonb_array_length(result #> '{data,affectedDatasets}') from issue880_results where label='model'),4,'Model affectedDatasets contains its root and three mutable exact results');

-- A repaired reference with existing Root candidates keeps the established
-- reference-only submission path, including legacy null-state normalization.
select set_config('app.review_controlled_write','on',true);
update public.contacts set state_code=null where id='38800002-0000-0000-0000-000000000003';
select set_config('app.review_controlled_write','off',true);
set local role authenticated;
insert into issue880_results values('repair',api.cmd_review_submit('contacts','38800002-0000-0000-0000-000000000003','01.00.000','{}'));
reset role;
select is((select result #>> '{data,submissionMode}' from issue880_results where label='repair'),'reference_repair','repair submission retains the reference-only path');
select is((select state_code from public.contacts where id='38800002-0000-0000-0000-000000000003'),20,'reference repair updates its exact legacy null-state draft');
select is((select count(*)::integer from private.reviews where review_kind='root' and data_id='38800002-0000-0000-0000-000000000003'),0,'repair does not create an extra Root Review');

-- Reject after inspecting a readable draft but before creating its review.
create temporary table issue880_before_failure as
select (select count(*) from private.reviews) reviews,
       (select count(*) from private.command_audit_log where actor_user_id='18800002-0000-0000-0000-000000000001') audits,
       (select count(*) from issue880_updates) updates;
set local role authenticated;
insert into issue880_results values('denied',api.cmd_review_submit('contacts','38800002-0000-0000-0000-000000000006','01.00.000','{}'));
insert into issue880_results values('foreign',api.cmd_review_submit('contacts','38800002-0000-0000-0000-000000000008','01.00.000','{}'));
insert into issue880_results values('published',api.cmd_review_submit('contacts','38800002-0000-0000-0000-000000000004','01.00.000','{}'));
reset role;
select is((select result->>'code' from issue880_results where label='denied'),'REFERENCE_ACCESS_DENIED','unreadable draft dependency fails closed');
select is((select result->>'code' from issue880_results where label='foreign'),'ROOT_DATASET_NOT_OWNED','foreign root fails closed');
select is((select result->>'code' from issue880_results where label='published'),'APPROVED_DATASET_IMMUTABLE','published root fails closed');
select is((select count(*) from private.reviews),(select reviews from issue880_before_failure),'failed closure validation creates no partial Reference Reviews');
select is((select count(*) from private.command_audit_log where actor_user_id='18800002-0000-0000-0000-000000000001'),(select audits from issue880_before_failure),'failed submissions create no successful-command audit records');
select is((select count(*) from issue880_updates),(select updates from issue880_before_failure),'failed submissions do not update any dataset');
select is((select state_code from public.contacts where id='38800002-0000-0000-0000-000000000006'),0,'failed root remains draft');
select is((select state_code from public.contacts where id='38800002-0000-0000-0000-000000000007'),0,'earlier readable dependency remains draft after failed closure validation');

select * from finish();
rollback;
