-- Only on a task-owned disposable full-schema project. Commits synthetic rows;
-- the owner must reset it afterwards. No solver, remote service or real data.
begin;
create extension if not exists pgtap with schema extensions;
set search_path=extensions,public,api,private;
select no_plan();
\ir ../fixtures/calculation-admission.sql
commit;

-- Real separate transactions, not two calls sharing transaction-stable now().
begin;
set local statement_timeout='16s';
set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','c9580000-0000-4000-8000-000000000001',true);
create temporary table admission_first_transaction as
select clock_timestamp() started_at,pg_temp.admission_submit('admission958-transactions') response;
select is((select response->>'ok' from admission_first_transaction),'true',
  'production-cardinality submission completes under the 16-second statement budget');
commit;

begin;
set local statement_timeout='16s';
set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','c9580000-0000-4000-8000-000000000001',true);
create temporary table admission_second_transaction as
select clock_timestamp() started_at,pg_temp.admission_submit('admission958-transactions') response;
select is((select response#>>'{data,workerJobId}' from admission_second_transaction),
  (select response#>>'{data,workerJobId}' from admission_first_transaction),
  'later transaction recovers the same canonical job');
commit;

begin;
select is((select count(*) from private.worker_jobs where
  idempotency_key='lcia_result.package_build:admission958-transactions'),1::bigint,
  'separate committed retries leave exactly one worker job');
select is((select count(*) from private.worker_job_events
  where job_id=(select (response#>>'{data,workerJobId}')::uuid from admission_first_transaction)
  and event_type='enqueued'),1::bigint,'separate committed retries leave one enqueue event');
select * from finish();
commit;
