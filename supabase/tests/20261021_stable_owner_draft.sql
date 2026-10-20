begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,api,private,auth;
select no_plan();
-- Keep database admission/lifecycle/JSON triggers enabled. These network-only
-- AFTER webhooks require provider/Edge credentials and are not part of this
-- synthetic database transaction proof; rollback restores their original state.
alter table public.processes disable trigger process_extract_md_trigger_insert;
alter table public.processes disable trigger process_extract_md_trigger_update;
alter table public.flows disable trigger flow_extract_md_trigger_update;

-- The tests exercise the real commands and enabled admission triggers. Historical
-- duplicate rows are covered by the populated-base upgrade fixture, not by
-- disabling the new guard to manufacture a post-upgrade state.
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at,is_sso_user,is_anonymous)
values
('00000000-0000-0000-0000-000000000000','85500000-0000-4000-8000-000000000001',
 'authenticated','authenticated','stable-owner-855@example.com','test-password-hash',now(),
 '{"provider":"email","providers":["email"]}','{}',now(),now(),false,false),
('00000000-0000-0000-0000-000000000000','85500000-0000-4000-8000-000000000002',
 'authenticated','authenticated','stable-foreign-855@example.com','test-password-hash',now(),
 '{"provider":"email","providers":["email"]}','{}',now(),now(),false,false);

create function pg_temp.stable_body(p_root text,p_version text,p_marker text default 'source')
returns jsonb language sql immutable as $$
select jsonb_build_object(p_root,jsonb_build_object('administrativeInformation',
  jsonb_build_object('publicationAndOwnership',jsonb_build_object('common:dataSetVersion',p_version))) ||
  case when p_root='flowDataSet' then '{"modellingAndValidation":{"LCIMethod":{"typeOfDataSet":"Product flow"}}}'::jsonb else '{}'::jsonb end,
  'fixture',jsonb_build_object('marker',p_marker,'ordered',jsonb_build_array(1,2),'number',1.0))
$$;
grant execute on function pg_temp.stable_body(text,text,text) to authenticated;
create function pg_temp.flow_body(p_version text,p_type text)
returns jsonb language sql immutable as $$
select case when p_type is null then pg_temp.stable_body('flowDataSet',p_version)#-'{flowDataSet,modellingAndValidation,LCIMethod,typeOfDataSet}'
 else jsonb_set(pg_temp.stable_body('flowDataSet',p_version),'{flowDataSet,modellingAndValidation,LCIMethod,typeOfDataSet}',to_jsonb(p_type)) end
$$;
grant execute on function pg_temp.flow_body(text,text) to authenticated;

insert into public.contacts(id,json_ordered,user_id,state_code,rule_verification)
select ('85500000-0000-4000-8000-'||lpad(to_hex(n),12,'0'))::uuid,
  pg_temp.stable_body('contactDataSet','01.00.000')::json,
  '85500000-0000-4000-8000-000000000001',100,true
from generate_series(257,270)n;
-- Other-owner draft and another table with the same UUID must not enter the
-- selected owner's complete typed census; allocation still sees all versions.
insert into public.contacts(id,json_ordered,user_id,state_code)
values
('85500000-0000-4000-8000-000000000101',pg_temp.stable_body('contactDataSet','01.00.004','foreign')::json,'85500000-0000-4000-8000-000000000002',0),
('85500000-0000-4000-8000-000000000102',pg_temp.stable_body('contactDataSet','01.00.002','existing')::json,'85500000-0000-4000-8000-000000000001',0);
update public.contacts set rule_verification=true where id='85500000-0000-4000-8000-000000000102' and version='01.00.002';
insert into public.flows(id,json_ordered,user_id,state_code)
values
('85500000-0000-4000-8000-000000000101',pg_temp.stable_body('flowDataSet','01.00.001','other-table')::json,'85500000-0000-4000-8000-000000000001',0),
('85500000-0000-4000-8000-000000000106',pg_temp.stable_body('flowDataSet','01.00.000')::json,'85500000-0000-4000-8000-000000000001',100);
insert into public.processes(id,json_ordered,user_id,state_code,rule_verification)
values
('85500000-0000-4000-8000-000000000201',pg_temp.stable_body('processDataSet','01.00.000')::json,'85500000-0000-4000-8000-000000000001',100,true),
('85500000-0000-4000-8000-000000000202',pg_temp.stable_body('processDataSet','01.00.000')::json,'85500000-0000-4000-8000-000000000001',100,true),
('85500000-0000-4000-8000-000000000203',pg_temp.stable_body('processDataSet','01.00.000')::json,'85500000-0000-4000-8000-000000000001',120,true),
('85500000-0000-4000-8000-000000000204',pg_temp.stable_body('processDataSet','01.00.000')::json,'85500000-0000-4000-8000-000000000002',0,true);
insert into public.flows(id,json_ordered,user_id,state_code,rule_verification)
select ('85500000-0000-4000-8000-'||lpad(to_hex(n),12,'0'))::uuid,
 pg_temp.flow_body('01.00.000',t)::json,'85500000-0000-4000-8000-000000000001',100,true
from (values(769,'Elementary flow'),(770,'unexpected'),(771,null::text),(772,'Product flow'),(773,'Waste flow'))x(n,t);
insert into public.sources(id,json_ordered,user_id,state_code,rule_verification)
values('85500000-0000-4000-8000-000000000401',pg_temp.stable_body('sourceDataSet','01.00.000')::json,'85500000-0000-4000-8000-000000000001',100,true);
insert into public.contacts(id,json_ordered,user_id,state_code)
values
('85500000-0000-4000-8000-000000000109',pg_temp.stable_body('contactDataSet','01.00.001')::json,'85500000-0000-4000-8000-000000000001',20),
('85500000-0000-4000-8000-000000000109',pg_temp.stable_body('contactDataSet','01.00.002')::json,'85500000-0000-4000-8000-000000000001',20),
('85500000-0000-4000-8000-00000000010b',pg_temp.stable_body('contactDataSet','01.00.004')::json,'85500000-0000-4000-8000-000000000002',20);

create function pg_temp.stable_request(p_id uuid,p_table text default 'contacts')
returns jsonb language plpgsql security definer set search_path='' as $$
declare s jsonb; d jsonb;
begin
 execute format('select to_jsonb(x) from public.%I x where id=$1 and version=''01.00.000''',p_table) into s using p_id;
 execute format('select coalesce(jsonb_agg(jsonb_build_object(''version'',version,''jsonOrdered'',json_ordered::jsonb) order by version),''[]''::jsonb) from public.%I where id=$1 and user_id=$2 and state_code=0',p_table)
 into d using p_id,'85500000-0000-4000-8000-000000000001'::uuid;
 return jsonb_build_object('table',p_table,'id',p_id,'expectedActorId','85500000-0000-4000-8000-000000000001',
   'expectedDrafts',d,'source',jsonb_build_object('version',s->>'version','userId',s->>'user_id',
   'stateCode',100,'jsonOrdered',s->'json_ordered'));
end;
$$;
create temp table stable_cases(name text primary key, request jsonb not null, response jsonb);
insert into stable_cases(name,request)
values ('zero',pg_temp.stable_request('85500000-0000-4000-8000-000000000101')),
('one',pg_temp.stable_request('85500000-0000-4000-8000-000000000102')),
('stale-census',pg_temp.stable_request('85500000-0000-4000-8000-000000000103')),
('stale-body',pg_temp.stable_request('85500000-0000-4000-8000-000000000104')),
('stale-owner',pg_temp.stable_request('85500000-0000-4000-8000-000000000105')),
('stale-state',pg_temp.stable_request('85500000-0000-4000-8000-000000000106','flows')),
('unchanged-source',pg_temp.stable_request('85500000-0000-4000-8000-000000000107')),
('process',pg_temp.stable_request('85500000-0000-4000-8000-000000000201','processes')),
('model-first',pg_temp.stable_request('85500000-0000-4000-8000-000000000202','processes')),
('result-source',pg_temp.stable_request('85500000-0000-4000-8000-000000000203','processes')),
('foreign-private',pg_temp.stable_request('85500000-0000-4000-8000-000000000204','processes'));
insert into stable_cases(name,request) values
('flow-elementary',pg_temp.stable_request('85500000-0000-4000-8000-000000000301','flows')),
('flow-unknown',pg_temp.stable_request('85500000-0000-4000-8000-000000000302','flows')),
('flow-missing',pg_temp.stable_request('85500000-0000-4000-8000-000000000303','flows')),
('flow-product',pg_temp.stable_request('85500000-0000-4000-8000-000000000304','flows')),
('flow-waste',pg_temp.stable_request('85500000-0000-4000-8000-000000000305','flows')),
('source',pg_temp.stable_request('85500000-0000-4000-8000-000000000401','sources'));
insert into stable_cases(name,request) values
('owner-review',pg_temp.stable_request('85500000-0000-4000-8000-000000000109')),
('foreign-review',pg_temp.stable_request('85500000-0000-4000-8000-00000000010b'));
create temp table stable_source_before as select to_jsonb(c) row from public.contacts c where id='85500000-0000-4000-8000-000000000101' and state_code=100;
grant select,update on stable_cases to authenticated;
grant select on stable_source_before to authenticated;

select ok(has_function_privilege('authenticated','api.cmd_dataset_prepare_stable_draft(uuid,jsonb)','execute')
 and not has_function_privilege('anon','api.cmd_dataset_prepare_stable_draft(uuid,jsonb)','execute')
 and not has_function_privilege('service_role','api.cmd_dataset_prepare_stable_draft(uuid,jsonb)','execute'),
 'prepare is actor-only, not anonymous or service-role');
select is((select capability_id from private.api_capability_grants where routine_identity='api.cmd_dataset_prepare_stable_draft(uuid, jsonb)'),
 'CLI-RPC-01','prepare retains the version-command capability');
select is((select capability_id from private.api_capability_grants where routine_identity='api.get_dataset_stable_draft_request(uuid, jsonb)'),
 'DB-CORE-READ-01','readonly recovery uses the read capability');
select ok(not has_table_privilege('authenticated','public.contacts','insert'), 'RLS does not reopen direct actor INSERT');
select ok(not has_table_privilege('authenticated','private.command_audit_log','select'), 'receipt storage remains private');
select is((select provolatile::text from pg_proc where oid='api.get_dataset_stable_draft_request(uuid,jsonb)'::regprocedure),
 's','request recovery is read-only STABLE');
select is((select count(*) from pg_trigger where tgname='zzz_guard_owner_draft_stability' and not tgisinternal),4::bigint,
 'all four mutable types enforce the common boundary');
select ok(not exists(
 select 1 from pg_trigger t where t.tgrelid in ('public.contacts'::regclass,'public.sources'::regclass,'public.flows'::regclass,'public.processes'::regclass)
 and not t.tgisinternal and (t.tgtype & 2)=2 and t.tgname>'zzz_guard_owner_draft_stability'
 and t.tgname<>'zzz_guard_process_result_lifecycle'),
 'draft guard follows transforming BEFORE triggers and precedes the final Result guard');

select set_config('request.jwt.claim.sub','85500000-0000-4000-8000-000000000001',true);
set local role authenticated;
update stable_cases set response=api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000001001',request) where name='zero';
select is((select response#>>'{data,outcome}' from stable_cases where name='zero'),'created','zero owner drafts creates one successor');
select is((select response#>>'{data,version}' from stable_cases where name='zero'),'01.00.005','server allocates past foreign-owner versions');
select is((select response#>>'{data,selectedDraft,userId}' from stable_cases where name='zero'),
 '85500000-0000-4000-8000-000000000001','successor belongs to the authenticated actor');
select is((select response#>'{data,selectedDraft,jsonOrdered,fixture}' from stable_cases where name='zero'),
 '{"marker":"source","ordered":[1,2],"number":1}'::jsonb,'scientific/source content remains byte-value equivalent');
select is((select response#>>'{data,selectedDraft,jsonOrdered,contactDataSet,administrativeInformation,publicationAndOwnership,common:permanentDataSetURI}' from stable_cases where name='zero'),
 'https://lcdn.tiangong.earth/datasetdetail/contact.xhtml?uuid=85500000-0000-4000-8000-000000000101&version=01.00.005','native allocator owns permanent URI');
select is((select to_jsonb(c) from public.contacts c where id='85500000-0000-4000-8000-000000000101' and state_code=100),
 (select row from stable_source_before),'published source whole row remains unchanged');
select is((select rule_verification from public.contacts where id='85500000-0000-4000-8000-000000000101' and version='01.00.005'),
 false,'cloning never inherits a public source scientific/rule-ready flag');
select is((select rule_verification from public.contacts where id='85500000-0000-4000-8000-000000000101' and version='01.00.000'),
 true,'original public rule verification stays unchanged');
select is((select count(*) from public.contacts where id='85500000-0000-4000-8000-000000000101' and user_id=auth.uid() and state_code=0),1::bigint,
 'exactly one current-owner draft exists');
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000001001',(select request from stable_cases where name='zero'))#>>'{data,replayed}',
 'true','exact original prepare request cannot allocate a second version');
select is(api.get_dataset_stable_draft_request('85500000-0000-4000-8000-000000001001',(select request from stable_cases where name='zero'))#>>'{data,targetStatus}',
 'unchanged','lost-response readback recovers the original unchanged target');
select is(api.get_dataset_stable_draft_request('85500000-0000-4000-8000-000000001099',(select request from stable_cases where name='zero'))->>'code',
 'REQUEST_NOT_RECORDED','unknown outcome is not converted into another dispatch');
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000001001',
 (select jsonb_set(request,'{selectedVersion}','"01.00.005"') from stable_cases where name='zero'))->>'code',
 'REQUEST_ID_REUSED','same request ID cannot bind changed request fields');
update stable_cases set response=api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000001002',request) where name='one';
select is((select response#>>'{data,outcome}' from stable_cases where name='one'),'reused','one draft is reused');
select is((select response#>>'{data,version}' from stable_cases where name='one'),'01.00.002','reuse preserves the exact existing version');
select is((select rule_verification from public.contacts where id='85500000-0000-4000-8000-000000000102' and version='01.00.002'),
 true,'reuse does not rewrite the existing draft verification flag');
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000001003',
 (select jsonb_set(request,'{selectedVersion}','"01.00.003"') from stable_cases where name='one'))->>'code',
 'DATASET_DRAFT_SELECTION_INVALID','cannot substitute an absent version');
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000001004',
 (select jsonb_set(request,'{expectedActorId}','"85500000-0000-4000-8000-000000000002"') from stable_cases where name='one'))->>'code',
 'DATASET_ACTOR_MISMATCH','actor binding is checked before selection');
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000001005',
 (select jsonb_set(request,'{source}','null') from stable_cases where name='one'))->>'code',
 'DATASET_INITIAL_CREATION_UNSUPPORTED','initial creation is an explicit unsupported slice');
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000001006',
 (select request||'{"extra":true}' from stable_cases where name='one'))->>'code',
 'INVALID_STABLE_DRAFT_REQUEST','extra request fields fail before mutation');
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000001007',
 (select jsonb_set(request,'{expectedDrafts}',(request->'expectedDrafts')||(request->'expectedDrafts')) from stable_cases where name='one'))->>'code',
 'INVALID_STABLE_DRAFT_REQUEST','duplicate expected versions are malformed');

reset role;
select is((select count(*) from private.command_audit_log where command='cmd_dataset_create_version'
 and target_id='85500000-0000-4000-8000-000000000101'),1::bigint,'native version writer dispatched exactly once');
select is((select count(*) from private.command_audit_log where command='cmd_dataset_prepare_stable_draft'
 and actor_user_id='85500000-0000-4000-8000-000000000001'),2::bigint,
 'one receipt each for successful create/reuse; readback and failures append nothing');

-- Source and census admission are checked afresh, even when a reusable draft is present.
insert into public.contacts(id,json_ordered,user_id,state_code)
values('85500000-0000-4000-8000-000000000103',pg_temp.stable_body('contactDataSet','01.00.001','racer')::json,'85500000-0000-4000-8000-000000000001',0);
-- Simulate a separately authorized controlled lifecycle/maintenance change. The
-- new draft guard has no GUC bypass, including while the review owner is active.
select set_config('app.review_controlled_write','on',true);
update public.contacts set json_ordered=pg_temp.stable_body('contactDataSet','01.00.000','edited-source')::json
where id='85500000-0000-4000-8000-000000000104' and version='01.00.000';
update public.contacts set user_id='85500000-0000-4000-8000-000000000002'
where id='85500000-0000-4000-8000-000000000105' and version='01.00.000';
update public.flows set state_code=200 where id='85500000-0000-4000-8000-000000000106' and version='01.00.000';
select set_config('app.review_controlled_write','off',true);
set local role authenticated;
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000001010',(select request from stable_cases where name='stale-census'))->>'code',
 'DATASET_DRAFT_CENSUS_CHANGED','stale empty census cannot create after a competing insertion');
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000001011',(select request from stable_cases where name='stale-body'))->>'code',
 'DATASET_SOURCE_CHANGED','changed full source body is rejected');
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000001012',(select request from stable_cases where name='stale-owner'))->>'code',
 'DATASET_SOURCE_CHANGED','source owner is an exact binding');
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000001013',(select request from stable_cases where name='stale-state'))->>'code',
 'DATASET_SOURCE_CHANGED','even another public state invalidates a stale source binding');
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000001014',
 (select jsonb_set(request,'{source,jsonOrdered,fixture,marker}','"changed"') from stable_cases where name='one'))->>'code',
 'DATASET_SOURCE_CHANGED','reuse still binds the full public source');
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000001015',
 (select jsonb_set(request,'{expectedDrafts,0,jsonOrdered,fixture,marker}','"changed"') from stable_cases where name='one'))->>'code',
 'DATASET_BEFORE_CONTENT_CHANGED','same version with stale draft before body is refused');
select is(api.cmd_dataset_create('contacts','85500000-0000-4000-8000-000000000102',
 pg_temp.stable_body('contactDataSet','01.00.003','legacy-new')) ->>'message',
 'DATASET_DRAFT_CONFLICT','legacy create cannot add another ordinary owner draft');
select is(api.cmd_dataset_create_version('contacts','85500000-0000-4000-8000-000000000102','01.00.000',
 pg_temp.stable_body('contactDataSet','01.00.000')) ->>'message',
 'DATASET_DRAFT_CONFLICT','legacy create-version cannot bypass stable target reuse');
select is(api.cmd_dataset_save_draft_guarded('contacts','85500000-0000-4000-8000-000000000102','01.00.002',
 pg_temp.stable_body('contactDataSet','01.00.002','edited'),pg_temp.stable_body('contactDataSet','01.00.002','existing'))->>'ok',
 'true','the existing exact before-image writer remains usable');
select is(api.get_dataset_stable_draft_request('85500000-0000-4000-8000-000000001002',(select request from stable_cases where name='one'))#>>'{data,targetStatus}',
 'changed','readback preserves the original receipt and reports later target edits');
reset role;

-- UPDATE owner/state/implicit version admission, not just the new command.
insert into public.contacts(id,json_ordered,user_id,state_code)
values
('85500000-0000-4000-8000-000000000108',pg_temp.stable_body('contactDataSet','01.00.001')::json,'85500000-0000-4000-8000-000000000001',0),
('85500000-0000-4000-8000-000000000108',pg_temp.stable_body('contactDataSet','01.00.002')::json,'85500000-0000-4000-8000-000000000002',0);
select throws_ok($$update public.contacts set user_id='85500000-0000-4000-8000-000000000001'
 where id='85500000-0000-4000-8000-000000000108' and version='01.00.002'$$,
 '23514','DATASET_DRAFT_CONFLICT','owner transfer into an occupied draft family is refused');
insert into public.contacts(id,json_ordered,user_id,state_code)
values('85500000-0000-4000-8000-000000000108',pg_temp.stable_body('contactDataSet','01.00.003')::json,'85500000-0000-4000-8000-000000000001',20);
select set_config('app.review_controlled_write','on',true);
select throws_ok($$update public.contacts set state_code=0
 where id='85500000-0000-4000-8000-000000000108' and version='01.00.003'$$,
 '23514','DATASET_DRAFT_CONFLICT','review/withdrawal cannot enter an occupied owner draft family');
update public.contacts set state_code=100
where id='85500000-0000-4000-8000-000000000108' and version='01.00.003';
select set_config('app.review_controlled_write','off',true);
select lives_ok($$update public.contacts set json_ordered=pg_temp.stable_body('contactDataSet','01.00.006')::json
 where id='85500000-0000-4000-8000-000000000108' and version='01.00.001'$$,
 'implicit JSON-sync version change checks the actual new version');
select is((select version from public.contacts where id='85500000-0000-4000-8000-000000000108' and user_id='85500000-0000-4000-8000-000000000001' and state_code=0),
 '01.00.006','guard runs after JSON/version synchronization');

-- model_id is an existing model-bound exclusion, never an authentication token.
-- Preserve the old model-only contract but prove that caller-supplied modelId
-- cannot mix a second draft into a prepared standalone family.
set local role authenticated;
update stable_cases set response=api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000002001',request) where name='process';
select is((select response#>>'{data,outcome}' from stable_cases where name='process'),'created','standalone Process successor uses the native version allocator');
select is(api.cmd_dataset_create('processes','85500000-0000-4000-8000-000000000201',
 pg_temp.stable_body('processDataSet','01.00.002','fake-model'),'85500000-0000-4000-8000-00000000f001')->>'message',
 'LIFECYCLEMODEL_BUNDLE_REQUIRED','fabricated modelId cannot insert alongside a standalone draft');
select is(api.cmd_dataset_create('processes','85500000-0000-4000-8000-000000000202',
 pg_temp.stable_body('processDataSet','01.00.001','model-only'),'85500000-0000-4000-8000-00000000f001')->>'ok',
 'true','existing model-bound-only creation semantics remain outside this slice');
select is(api.cmd_dataset_create('processes','85500000-0000-4000-8000-000000000202',
 pg_temp.stable_body('processDataSet','01.00.002','model-only-2'),'85500000-0000-4000-8000-00000000f001')->>'ok',
 'true','no false global-uniqueness claim is made for model-only drafts');
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000002002',(select request from stable_cases where name='model-first'))->>'code',
 'LIFECYCLEMODEL_BUNDLE_REQUIRED','model-bound drafts appearing first close generic stable preparation');
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000002003',(select request from stable_cases where name='result-source'))->>'code',
 'RESULT_VERSION_DERIVATION_BLOCKED','owner Result source is explicitly rejected');
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000002004',(select request from stable_cases where name='foreign-private'))->>'code',
 'DATASET_SOURCE_NOT_FOUND','foreign private source existence/state remains hidden');
select is(api.cmd_dataset_save_draft_guarded('processes','85500000-0000-4000-8000-000000000201','01.00.001',
 (select response#>'{data,selectedDraft,jsonOrdered}' from stable_cases where name='process'),
 (select response#>'{data,selectedDraft,jsonOrdered}' from stable_cases where name='process'),
 '85500000-0000-4000-8000-00000000f001')->>'ok','true','legacy model relinking is not silently redesigned by this slice');
select is(api.get_dataset_stable_draft_request('85500000-0000-4000-8000-000000002001',(select request from stable_cases where name='process'))#>>'{data,targetStatus}',
 'changed','model relinking changes recovery status even when JSON is identical');
reset role;

set local role authenticated;
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000003001',(select request from stable_cases where name='flow-elementary'))->>'code',
 'DATASET_REFERENCE_ONLY','Elementary Flow source cannot use the new generic creation path');
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000003002',(select request from stable_cases where name='flow-unknown'))->>'code',
 'DATASET_REFERENCE_ONLY','unknown Flow type fails closed');
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000003003',(select request from stable_cases where name='flow-missing'))->>'code',
 'DATASET_REFERENCE_ONLY','missing Flow type fails closed');
update stable_cases set response=api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000003004',request) where name='flow-product';
select is((select response#>>'{data,outcome}' from stable_cases where name='flow-product'),'created','Product Flow successor is supported');
update stable_cases set response=api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000003005',request) where name='flow-waste';
select is((select response#>>'{data,outcome}' from stable_cases where name='flow-waste'),'created','Waste Flow successor is supported');
update stable_cases set response=api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000004001',request) where name='source';
select is((select response#>>'{data,outcome}' from stable_cases where name='source'),'created','Source successor retains the existing creator');
select is(api.cmd_dataset_create('flows','85500000-0000-4000-8000-000000000304',pg_temp.flow_body('01.00.002','Elementary flow'))->>'message',
 'DATASET_DRAFT_CONFLICT','reference-only insertion cannot mix with an active Product Flow draft');
select is(api.cmd_dataset_create('flows','85500000-0000-4000-8000-000000000301',pg_temp.flow_body('01.00.001','Elementary flow'))->>'ok',
 'true','legacy Elementary-only creation is explicitly outside the stable contract');
select is(api.cmd_dataset_create('flows','85500000-0000-4000-8000-000000000301',pg_temp.flow_body('01.00.002','Elementary flow'))->>'ok',
 'true','legacy Elementary-only duplicate semantics are preserved');
select is(api.cmd_dataset_create('flows','85500000-0000-4000-8000-000000000301',pg_temp.flow_body('01.00.003','Product flow'))->>'message',
 'DATASET_DRAFT_CONFLICT','new Product Flow cannot mix into an existing reference-only draft family');
reset role;
select is((select count(*) from private.command_audit_log where command='cmd_dataset_prepare_stable_draft'
 and target_id in ('85500000-0000-4000-8000-000000000301','85500000-0000-4000-8000-000000000302','85500000-0000-4000-8000-000000000303')),0::bigint,
 'reference-only failures append zero stable receipts');
select is((select count(*) from private.command_audit_log where command='cmd_dataset_create_version'
 and target_id in ('85500000-0000-4000-8000-000000000301','85500000-0000-4000-8000-000000000302','85500000-0000-4000-8000-000000000303')),0::bigint,
 'reference-only failures dispatch zero native version writes');
-- The selected-draft guard is independent from the public source's type.
insert into public.flows(id,json_ordered,user_id,state_code)
values('85500000-0000-4000-8000-000000000306',pg_temp.flow_body('01.00.000','Product flow')::json,'85500000-0000-4000-8000-000000000001',100),
('85500000-0000-4000-8000-000000000306',pg_temp.flow_body('01.00.001','Elementary flow')::json,'85500000-0000-4000-8000-000000000001',0);
insert into stable_cases(name,request) values('flow-selected-ef',pg_temp.stable_request('85500000-0000-4000-8000-000000000306','flows'));
set local role authenticated;
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000003006',(select request from stable_cases where name='flow-selected-ef'))->>'code',
 'DATASET_REFERENCE_ONLY','Product source does not admit a selected Elementary draft');
select is(api.cmd_dataset_save_draft_guarded('flows','85500000-0000-4000-8000-000000000304','01.00.001',
 jsonb_set((select response#>'{data,selectedDraft,jsonOrdered}' from stable_cases where name='flow-product'),'{flowDataSet,modellingAndValidation,LCIMethod,typeOfDataSet}','"Elementary flow"'),
 (select response#>'{data,selectedDraft,jsonOrdered}' from stable_cases where name='flow-product'))->>'ok',
 'true','this slice does not redefine the old exact-row scientific writer');
select is(api.get_dataset_stable_draft_request('85500000-0000-4000-8000-000000003004',(select request from stable_cases where name='flow-product'))#>>'{data,targetStatus}',
 'changed','reference-only type relinking invalidates stable receipt recovery');
reset role;

-- A zero state-0 census is not permission to fork an in-progress owner review.
-- Complete return points are existing dataset/review coordinates, not a new queue.
set local role authenticated;
update stable_cases set response=api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000006001',request) where name='owner-review';
select is((select response->>'code' from stable_cases where name='owner-review'),
 'DATASET_REVIEW_IN_PROGRESS','owner review blocks zero-draft preparation');
select is((select response->>'status' from stable_cases where name='owner-review'),'409','review conflict has a specific structured status');
select is((select jsonb_array_length(response#>'{details,reviews}') from stable_cases where name='owner-review'),2,
 'every owner review version is returned');
select is((select response#>'{details,reviews,0}' from stable_cases where name='owner-review'),
 '{"table":"contacts","id":"85500000-0000-4000-8000-000000000109","version":"01.00.001","userId":"85500000-0000-4000-8000-000000000001","stateCode":20,"reviewId":null}'::jsonb,
 'return point names the exact existing dataset review with no fabricated queue');
select is(api.cmd_dataset_create('contacts','85500000-0000-4000-8000-000000000109',pg_temp.stable_body('contactDataSet','01.00.003'))->>'code',
 'DATASET_REVIEW_IN_PROGRESS','legacy generic create cannot bypass an owner review');
select is(jsonb_array_length(api.cmd_dataset_create_version('contacts','85500000-0000-4000-8000-000000000109','01.00.000',pg_temp.stable_body('contactDataSet','01.00.000'))#>'{details,reviews}'),2,
 'legacy create-version retains complete structured review targets');
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000006002',(select request from stable_cases where name='foreign-review'))#>>'{data,outcome}',
 'created','another owner review does not become this actor review');
reset role;
select is((select count(*) from public.contacts where id='85500000-0000-4000-8000-000000000109' and state_code=0),0::bigint,
 'review conflicts create no draft');
select is((select count(*) from private.command_audit_log where target_id='85500000-0000-4000-8000-000000000109'),0::bigint,
 'review conflicts append no native write audit or stable receipt');
update public.contacts set state_code=20 where id='85500000-0000-4000-8000-000000000101' and version='01.00.005';
set local role authenticated;
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000001001',(select request from stable_cases where name='zero'))->>'code',
 'DATASET_REVIEW_IN_PROGRESS','even original-request prepare replay cannot claim an in-review family prepared');
select is(api.get_dataset_stable_draft_request('85500000-0000-4000-8000-000000001001',(select request from stable_cases where name='zero'))#>>'{data,targetStatus}',
 'changed','read-only lost-response recovery retains the receipt but exposes review transition');
select is(api.get_dataset_stable_draft_request('85500000-0000-4000-8000-000000001001',(select request from stable_cases where name='zero'))#>>'{data,currentDraft,stateCode}',
 '20','current readback returns the original target review state');
reset role;

-- The existing allocator overflows 99.99.999 through lpad(100,2) -> 10. The
-- new facade refuses allocation at that boundary without copying the allocator.
insert into public.contacts(id,json_ordered,user_id,state_code)
values('85500000-0000-4000-8000-00000000010e',pg_temp.stable_body('contactDataSet','99.99.999')::json,'85500000-0000-4000-8000-000000000001',100);
insert into stable_cases(name,request) values('exhausted',pg_temp.stable_request('85500000-0000-4000-8000-00000000010e'));
set local role authenticated;
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000004010',(select request from stable_cases where name='exhausted'))->>'code',
 'DATASET_VERSION_EXHAUSTED','an exhausted family is rejected before delegation');
reset role;
select is((select count(*) from private.command_audit_log where target_id='85500000-0000-4000-8000-00000000010e'),0::bigint,
 'version exhaustion performs no native write or receipt');
insert into public.contacts(id,json_ordered,user_id,state_code)
values('85500000-0000-4000-8000-00000000010e',pg_temp.stable_body('contactDataSet','02.00.000')::json,'85500000-0000-4000-8000-000000000001',0);
update stable_cases set request=pg_temp.stable_request('85500000-0000-4000-8000-00000000010e') where name='exhausted';
set local role authenticated;
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000004011',(select request from stable_cases where name='exhausted'))#>>'{data,outcome}',
 'reused','exhausted allocation does not prevent reuse of an existing exact draft');
reset role;

-- Fault injection is transaction-local and replaces only the delegated writer,
-- not the guard under test. The stub performs a real insert/audit before returning
-- invalid/missing/wrong results; every post-insert rejection must roll both back.
create or replace function api.cmd_dataset_create_version(
 p_table text,p_id uuid,p_source_version text,p_json_ordered jsonb,p_model_id uuid default null,
 p_rule_verification boolean default null,p_audit jsonb default '{}'::jsonb,p_model_version text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_payload jsonb;v_row jsonb;v_fault text:=right(p_audit->>'requestId',1);
begin
 v_payload:=jsonb_set(p_json_ordered,'{contactDataSet,administrativeInformation,publicationAndOwnership,common:dataSetVersion}','"01.00.001"');
 v_payload:=jsonb_set(v_payload,'{contactDataSet,administrativeInformation,publicationAndOwnership,common:permanentDataSetURI}',
 to_jsonb('https://lcdn.tiangong.earth/datasetdetail/contact.xhtml?uuid='||p_id::text||'&version=01.00.001'));
 if v_fault='2' then v_payload:=jsonb_set(v_payload,'{fixture,marker}','"unexpected-science-change"');end if;
 if v_fault<>'6' then
  insert into public.contacts(id,json_ordered,user_id,state_code,rule_verification) values(p_id,v_payload::json,auth.uid(),0,false) returning to_jsonb(contacts) into v_row;
  insert into private.command_audit_log(command,actor_user_id,target_table,target_id,target_version,payload)
  values('cmd_dataset_create_version',auth.uid(),'contacts',p_id,'01.00.001','{"fixture":"injected-writer"}');
 else
  v_row:=jsonb_build_object('id',p_id,'version','01.00.001','user_id',auth.uid(),'state_code',0,'rule_verification',false,'json_ordered',v_payload);
 end if;
 if v_fault='1' then v_row:=jsonb_set(v_row,'{id}','"85500000-0000-4000-8000-00000000ffff"');
 elsif v_fault='3' then return '{"ok":false,"code":"TEST_DELEGATE_REJECTED","status":409,"message":"synthetic rejection after insert"}'::jsonb;
 elsif v_fault='4' then return '{"ok":true}'::jsonb;
 elsif v_fault='5' then v_row:=jsonb_set(v_row,'{state_code}','20'::jsonb);
 end if;
 return jsonb_build_object('ok',true,'data',v_row);
end;
$$;
set local role authenticated;
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000005001',(select request from stable_cases where name='unchanged-source'))->>'code',
 'DATASET_STABLE_DRAFT_RESULT_INVALID','wrong delegated target is rolled back');
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000005002',(select request from stable_cases where name='unchanged-source'))->>'code',
 'DATASET_STABLE_DRAFT_RESULT_INVALID','a delegated scientific content change is rolled back');
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000005003',(select request from stable_cases where name='unchanged-source'))->>'code',
 'TEST_DELEGATE_REJECTED','even an explicit delegated failure rolls back a prior insert');
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000005004',(select request from stable_cases where name='unchanged-source'))->>'code',
 'DATASET_STABLE_DRAFT_RESULT_INVALID','missing delegated data cannot produce a success receipt');
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000005005',(select request from stable_cases where name='unchanged-source'))->>'code',
 'DATASET_STABLE_DRAFT_RESULT_INVALID','wrong delegated state cannot produce a success receipt');
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000005006',(select request from stable_cases where name='unchanged-source'))->>'code',
 'DATASET_STABLE_DRAFT_RESULT_INVALID','a plausible response without a real target fails exact database readback');
reset role;
select is((select count(*) from public.contacts where id='85500000-0000-4000-8000-000000000107' and state_code=0),0::bigint,
 'all post-insert failures leave zero draft rows');
select is((select count(*) from private.command_audit_log where target_id='85500000-0000-4000-8000-000000000107'),0::bigint,
 'all post-insert failures leave zero native audit and stable receipts');

select set_config('request.jwt.claim.sub','',true);
select is(api.cmd_dataset_prepare_stable_draft('85500000-0000-4000-8000-000000001020',(select request from stable_cases where name='one'))->>'code',
 'AUTH_REQUIRED','no authenticated actor cannot select or create');
select * from finish();
rollback;
