-- Run on a freshly reset local Supabase database. Both clients use the public RPC.
\set ON_ERROR_STOP on
select :'HOST' = '127.0.0.1' and :'PORT' = :'fixture_port'
  and current_database() = 'postgres' and not exists (select from auth.users) as blank_local \gset
\if :blank_local
\else
  do $$begin raise exception 'Expected a blank local test database'; end$$;
\endif
set statement_timeout = '20s';
create extension if not exists dblink with schema extensions;
set search_path = extensions, public;

\set actor '10160000-0000-4000-8000-000000000001'
\set dataset '10160000-0000-4000-8000-000000000002'
\set root_review '10160000-0000-4000-8000-000000000003'
\set ref_review '10160000-0000-4000-8000-000000000004'
\set other_version_review '10160000-0000-4000-8000-000000000005'

create function pg_temp.check_result(ok boolean, description text)
returns void language plpgsql as $$
begin
  if ok is not true then raise exception 'FAIL: %', description; end if;
  raise notice 'PASS: %', description;
end $$;
grant execute on function pg_temp.check_result(boolean,text) to authenticated;

begin;
insert into auth.users (id, aud, role) values (:'actor', 'authenticated', 'authenticated');
insert into private.roles (user_id, team_id, role)
values (:'actor','00000000-0000-0000-0000-000000000000','review-admin');
-- Suppress extraction jobs while seeding the synthetic process versions.
set local session_replication_role = replica;
insert into public.processes (id,version,user_id,state_code,json,json_ordered) values
  (:'dataset','01.00.000',:'actor',20,'{}','{}'),
  (:'dataset','02.00.000',:'actor',20,'{}','{}');
set local session_replication_role = origin;
insert into private.reviews (id,target_table,data_id,data_version,review_kind,state_code,
  reviewer_id,json,submitted_revision_checksum,target_owner_id)
select rid,'processes',:'dataset',ver,kind,review_state,'[]','{}',repeat('a',64),:'actor'
from (values (:'root_review'::uuid,'01.00.000','root',0),
             (:'ref_review'::uuid,'01.00.000','reference',1),
             (:'other_version_review'::uuid,'02.00.000','root',0)) f(rid,ver,kind,review_state);
commit;

select dblink_connect('peer','host=db port=5432 dbname=postgres user=postgres password=postgres');
select pid as peer_pid from dblink('peer','select pg_backend_pid()') as p(pid integer) \gset
select set_config('test.peer_pid', :'peer_pid', false);
select dblink_exec('peer','set statement_timeout = ''15s''');
select dblink_exec('peer', format('set request.jwt.claim.sub = %L', :'actor'));
select dblink_exec('peer','set role authenticated');

begin;
set local role authenticated;
select pg_temp.check_result(api.cmd_review_finalize_reject(:'root_review','test')->>'code'='REVIEW_ADMIN_REQUIRED',
  'a caller without an authenticated review admin cannot reject');
select set_config('request.jwt.claim.sub', :'actor', true);
select pg_temp.check_result(
  (api.cmd_review_finalize_reject(:'root_review','test')->'data'->>'targetReleased')::boolean = false,
  'one rejection keeps the target under review');
reset role;
select pg_temp.check_result((select state_code from public.processes
  where id=:'dataset' and version='01.00.000') = 20, 'first rejection leaves the version in review');

select pg_temp.check_result((result->'data'->>'targetReleased')::boolean,
  'another version can finish while the first transaction is open')
from dblink('peer',format('select api.cmd_review_finalize_reject(%L,%L)', :'other_version_review','test'))
  as p(result jsonb);
select dblink_send_query('peer',format('select api.cmd_review_finalize_reject(%L,%L)', :'ref_review','test'));
-- Check the actual wait before releasing the first transaction.
do $$
declare deadline timestamptz := clock_timestamp() + interval '8 seconds';
begin
  while not pg_backend_pid() = any(pg_blocking_pids(current_setting('test.peer_pid')::integer)) loop
    if extensions.dblink_is_busy('peer') = 0 or clock_timestamp() >= deadline then
      raise exception 'Second decision did not wait for the first';
    end if;
    perform pg_sleep(0.01);
  end loop;
end $$;
commit;
select pg_temp.check_result((result->'data'->>'targetReleased')::boolean,
  'last rejection releases the version') from dblink_get_result('peer') as p(result jsonb);
select dblink_disconnect('peer');

select pg_temp.check_result(count(*)=2 and bool_and(state_code=0), 'both versions are editable drafts')
from public.processes where id=:'dataset';
select pg_temp.check_result(count(*)=3 and bool_and(state_code=-1), 'all three reviews were rejected')
from private.reviews where data_id=:'dataset';
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'actor', true);
select pg_temp.check_result(api.cmd_review_finalize_reject(:'ref_review','retry')->>'code'='INVALID_REVIEW_STATE',
  'retry preserves the existing response');
commit;
select pg_temp.check_result(count(*)=3, 'each decision was audited once')
from private.command_audit_log where command='cmd_review_finalize_reject'
  and target_id in (:'root_review',:'ref_review',:'other_version_review');

select pg_temp.check_result(count(*)=2
  and count(*) filter (where dataset_version='01.00.000' and json->>'event_type'='reference_rejected')=1
  and count(*) filter (where dataset_version='02.00.000' and json->>'event_type'='root_rejected')=1,
  'the owner sees the latest rejection notification for each version')
from private.notifications where recipient_user_id=:'actor' and dataset_id=:'dataset';

begin;
delete from private.notifications where dataset_type='processes' and dataset_id=:'dataset';
delete from private.command_audit_log where command='cmd_review_finalize_reject'
  and target_id in (:'root_review',:'ref_review',:'other_version_review');
delete from private.reviews where id in (:'root_review',:'ref_review',:'other_version_review');
delete from public.processes where id=:'dataset';
delete from private.roles where user_id=:'actor';
delete from auth.users where id=:'actor';
commit;
