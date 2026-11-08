begin;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, auth;
select no_plan();

-- Seed only synthetic data without projection/webhook setup effects. Every
-- production trigger is enabled again before the actual actor command runs.
set local session_replication_role = replica;
insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('95500000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
  'review955-owner@example.invalid', 'test', now(), '{}', '{}', now(), now()),
  ('95500000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
  'review955-other@example.invalid', 'test', now(), '{}', '{}', now(), now());
insert into private.users (id, raw_user_meta_data)
values ('95500000-0000-4000-8000-000000000001','{}'),
  ('95500000-0000-4000-8000-000000000002','{}') on conflict do nothing;

create temp table published_keys (table_name text, id uuid, version text);
create temp table fixture_refs (ref jsonb);
do $$
declare t text; kind text; n integer; k uuid; s integer;
begin
  for t, kind in select * from (values
    ('contacts','contact data set'), ('sources','source data set'),
    ('unitgroups','unit group data set'), ('flowproperties','flow property data set'),
    ('flows','flow data set'), ('processes','process data set'),
    ('lifecyclemodels','lifeCycleModel data set')) kinds(table_name,ref_type)
  loop
    for n in 1..case when t='flows' then 32 else 2 end loop
      k := md5('review955:'||t||':'||n)::uuid;
      s := case when n%2=0 and t in ('unitgroups','flowproperties','flows','processes')
        then 200 else 100 end;
      execute format('insert into public.%I (id,version,json,json_ordered,user_id,state_code,rule_verification,modified_at) values ($1,$2,$3,$3::json,$4,$5,true,$6)',t)
        using k,'03.00.000','{}'::jsonb,
          '95500000-0000-4000-8000-000000000001'::uuid,s,'2024-01-01'::timestamptz;
      insert into published_keys values(t,k,'03.00.000');
      insert into fixture_refs values(jsonb_build_object('@type',kind,'@refObjectId',k,'@version','03.00.000'));
    end loop;
  end loop;
end $$;
insert into public.contacts (id,version,json,json_ordered,user_id,state_code,rule_verification)
values ('95500000-0000-4000-8000-000000000010','01.00.000','{}','{}',
  '95500000-0000-4000-8000-000000000001',0,true);
insert into public.sources (id,version,json,json_ordered,user_id,state_code,rule_verification)
values ('95500000-0000-4000-8000-000000000011','02.00.000','{}','{}',
  '95500000-0000-4000-8000-000000000001',20,true);
insert into fixture_refs values
  ('{"@type":"contact data set","@refObjectId":"95500000-0000-4000-8000-000000000010","@version":"01.00.000"}'),
  ('{"@type":"source data set","@refObjectId":"95500000-0000-4000-8000-000000000011","@version":"02.00.000"}');
insert into public.lifecyclemodels (id,version,json,json_ordered,user_id,state_code,rule_verification)
select '95500000-0000-4000-8000-000000000020','06.00.000',j,j::json,
  '95500000-0000-4000-8000-000000000001',0,true
from (select jsonb_build_object('lifeCycleModelDataSet',jsonb_build_object(
  'lifeCycleModelInformation',jsonb_build_object('dataSetInformation',jsonb_build_object(
    'referenceToResultingProcess',jsonb_build_object('@type','process data set',
      '@refObjectId','95500000-0000-4000-8000-000000000021','@version','08.00.000'),
    'fixtureReferences',(select jsonb_agg(ref) from fixture_refs)),
    'technology',jsonb_build_object('processes',jsonb_build_object('processInstance',
      (select jsonb_agg(jsonb_build_object('referenceToProcess',ref)) from fixture_refs
        where ref->>'@type'='process data set')))))) j) payload;
insert into public.processes (id,version,json,json_ordered,user_id,state_code,rule_verification,model_id,model_version)
select '95500000-0000-4000-8000-000000000021','08.00.000',j,j::json,
  '95500000-0000-4000-8000-000000000001',0,true,
  '95500000-0000-4000-8000-000000000020','06.00.000'
from (select jsonb_build_object('processDataSet',jsonb_build_object('exchanges',
  jsonb_build_object('exchange',(select jsonb_agg(jsonb_build_object('referenceToFlowDataSet',ref))
    from fixture_refs where ref->>'@type'='flow data set')))) j) payload;
set local session_replication_role = origin;

-- Observe actual writes, including no-op UPDATEs: timestamp equality alone
-- would miss trigger fan-out because now() is constant inside a transaction.
create temp table observed_writes (table_name text, id uuid, version text);
create function pg_temp.review955_observe_write() returns trigger language plpgsql as $$
begin
  insert into pg_temp.observed_writes values(tg_table_name,new.id,new.version);
  return new;
end $$;
create temp table published_before (table_name text, id uuid, version text, row_json jsonb);
do $$
declare t text;
begin
  for t in select distinct table_name from published_keys loop
    execute format('create trigger review955_observe_write after update on public.%I for each row execute function pg_temp.review955_observe_write()',t);
    execute format('insert into published_before select $1,p.id,p.version,to_jsonb(p) from public.%I p join published_keys k on k.table_name=$1 and k.id=p.id and k.version=p.version',t) using t;
  end loop;
end $$;

select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','95500000-0000-4000-8000-000000000002',true);
set local role authenticated;
select is(api.cmd_review_submit('lifecyclemodels','95500000-0000-4000-8000-000000000020','06.00.000','{}')->>'code',
  'ROOT_DATASET_NOT_OWNED','a different actor cannot submit the model');
reset role;
select is((select count(*) from observed_writes),0::bigint,'denied submission performs no dataset writes');

select set_config('request.jwt.claim.sub','95500000-0000-4000-8000-000000000001',true);
-- An error after root/references have been provisioned must undo all of them.
-- Catch query_canceled explicitly, as WHEN OTHERS intentionally excludes it.
create function pg_temp.review955_timeout() returns trigger language plpgsql as $$
begin
  raise exception using errcode='57014', message='review955_test_timeout';
end $$;
create trigger review955_timeout after update on public.processes for each row
  when (new.id='95500000-0000-4000-8000-000000000021'::uuid and new.state_code=20)
  execute function pg_temp.review955_timeout();
create function pg_temp.review955_catch_timeout() returns text language plpgsql as $$
begin
  perform api.cmd_review_submit('lifecyclemodels',
    '95500000-0000-4000-8000-000000000020','06.00.000','{}');
  return 'unexpected_success';
exception when query_canceled then
  return sqlstate;
end $$;
grant execute on function pg_temp.review955_catch_timeout() to authenticated;
set local role authenticated;
select is(pg_temp.review955_catch_timeout(),'57014','a timeout in a later result write propagates');
reset role;
select is((select count(*) from private.reviews where data_id::text like '95500000-%'),
  0::bigint,'timeout rolls back root and generated-result/reference reviews');
select is((select count(*) from observed_writes),0::bigint,'timeout rolls back all dataset writes');
select is((select state_code from public.lifecyclemodels where id='95500000-0000-4000-8000-000000000020'),
  0,'timeout leaves the model draft');
select is((select state_code from public.processes where id='95500000-0000-4000-8000-000000000021'),
  0,'timeout leaves the exact owned result draft');
drop trigger review955_timeout on public.processes;
create temp table submission (result jsonb);
grant insert on submission to authenticated;
set local role authenticated;
insert into submission select api.cmd_review_submit('lifecyclemodels',
  '95500000-0000-4000-8000-000000000020','06.00.000','{}');
reset role;
select is((select result->>'ok' from submission),'true','the real actor command submits the Model root');
select is((select count(*) from observed_writes w join published_keys k using(table_name,id,version)),
  0::bigint,'approved 100 and commercial 200 references incur zero row writes on all seven tables');
select is((select count(*) from public.lifecyclemodels where id='95500000-0000-4000-8000-000000000020' and version='06.00.000' and state_code=20),
  1::bigint,'the exact Model version freezes');
select is((select count(*) from public.processes where id='95500000-0000-4000-8000-000000000021' and version='08.00.000' and state_code=20),
  1::bigint,'the independent-ID, different-version owned result freezes');
select is((select state_code from public.contacts where id='95500000-0000-4000-8000-000000000010'),20,
  'a draft reference still enters review');
select is((select state_code from public.sources where id='95500000-0000-4000-8000-000000000011'),20,
  'an existing in-review reference stays frozen');
select is((select count(*) from private.reviews where review_kind='root' and data_id='95500000-0000-4000-8000-000000000020'),
  1::bigint,'one Root Review is created');
select is((select count(*) from private.reviews r join published_keys k on k.table_name=r.target_table and k.id=r.data_id and k.version=btrim(r.data_version)),
  0::bigint,'public references do not acquire Reference Reviews');
select is((select count(*) from private.reviews where review_kind='reference' and data_id in
  ('95500000-0000-4000-8000-000000000010','95500000-0000-4000-8000-000000000011','95500000-0000-4000-8000-000000000021')),
  3::bigint,'draft/in-review references and the generated result retain their Reference Reviews');
select is((select jsonb_array_length(reviews) from public.sources where id='95500000-0000-4000-8000-000000000011'),
  1,'the in-review reference still receives the root link');

create temp table published_after (like published_before);
do $$
declare t text;
begin
  for t in select distinct table_name from published_keys loop
    execute format('insert into published_after select $1,p.id,p.version,to_jsonb(p) from public.%I p join published_keys k on k.table_name=$1 and k.id=p.id and k.version=p.version',t) using t;
  end loop;
end $$;
select results_eq('select * from published_after order by table_name,id,version',
  'select * from published_before order by table_name,id,version',
  'entire published rows, including timestamps, payload and review links, remain unchanged');
select is((select jsonb_array_length(result #> '{data,affectedDatasets}') from submission),
  (select count(*)::integer+4 from published_keys),'the affected-dataset response retains the same reference inventory');
create temp table writes_before_retry as select count(*) n from observed_writes;
set local role authenticated;
select is(api.cmd_review_submit('lifecyclemodels','95500000-0000-4000-8000-000000000020','06.00.000','{}')->>'code',
  'DATA_UNDER_REVIEW','repeat submit is rejected without a duplicate review');
reset role;
select is((select count(*) from observed_writes),(select n from writes_before_retry),'repeat submit performs no further dataset writes');
set local role authenticated;
select is(api.cmd_review_submit('processes',md5('review955:processes:1')::uuid,'03.00.000','{}')->>'code',
  'APPROVED_DATASET_IMMUTABLE','an approved root cannot be resubmitted');
reset role;
select is((select count(*) from observed_writes),(select n from writes_before_retry),'approved-root denial performs no further writes');

select * from finish();
rollback;
