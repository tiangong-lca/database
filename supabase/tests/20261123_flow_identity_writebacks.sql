begin;
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
set local search_path = extensions, public, auth;
select no_plan();
\ir fixtures/flow_identity_scope.sql

-- Generate requests from the shared receipt fixture as its owner. Only the
-- guarded production RPCs below run as the authenticated migration actor.
insert into flow_identity_state values ('request', pg_temp.flow_identity_capture());
select set_config('request.jwt.claim.sub', pg_temp.flow_identity_id('owner')::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'flow-owner@example.com', true);

select dblink_connect('ordinary_writer',
  'host=db port=5432 dbname=' || current_database() || ' user=postgres password=postgres');
select dblink_exec('ordinary_writer', 'begin');
select dblink_exec('ordinary_writer', $peer$
  set local session_replication_role = replica;
  insert into public.flows (id,version,user_id,json,json_ordered)
  values ('fa000000-ffff-4000-8000-000000000001','01.00.000',
          'f1000000-0000-4000-8000-000000000001','{}','{}');
  set local session_replication_role = origin;
  update public.flows set rule_verification = true, search_text = array['mixed']
  where id = 'fa000000-ffff-4000-8000-000000000001';
$peer$);
set local role authenticated;
select is(api.cmd_dataset_flow_identity_capture_attest_guarded(
  (select value from flow_identity_state where key='request'))->>'code',
  'FLOW_IDENTITY_CAPTURE_LOCK_BUSY',
  'ordinary mixed write first: capture cannot attest while its actor lock is held');
reset role;
select dblink_exec('ordinary_writer', 'rollback');

set local role authenticated;
insert into flow_identity_state select 'capture', api.cmd_dataset_flow_identity_capture_attest_guarded(
  (select value from flow_identity_state where key='request'));
select is((select value->>'ok' from flow_identity_state where key='capture'), 'true',
          'capture succeeds after the ordinary writer releases its transaction');
reset role;
insert into flow_identity_state values ('seal', pg_temp.flow_identity_preflight());
set local role authenticated;
insert into flow_identity_state select 'preflight', api.cmd_dataset_flow_identity_scope_preflight_guarded(
  (select value from flow_identity_state where key='seal'));
select is((select value->>'status' from flow_identity_state where key='preflight'), 'sealed',
          'real preflight seals the receipt and holds the actor lock');
reset role;

-- This peer sees no committed scope. The actor lock, independently of an
-- active-scope SELECT, must still reject the business write.
select dblink_exec('ordinary_writer', $peer$
  begin;
  set local session_replication_role = replica;
  insert into public.processes (id,version,user_id,json,json_ordered)
  values ('fa000000-ffff-4000-8000-000000000002','01.00.000',
          'f1000000-0000-4000-8000-000000000001','{}','{}');
  set local session_replication_role = origin;
$peer$);
select is(dblink_exec('ordinary_writer', $peer$
  update public.processes set extracted_md='# fresh', search_text=array['fresh']
  where id='fa000000-ffff-4000-8000-000000000002'$peer$), 'UPDATE 1',
  'seal first: the peer can still write both derived columns');
select throws_ok($test$select dblink_exec('ordinary_writer', $peer$
  update public.processes set rule_verification=true, search_text=array['mixed']
  where id='fa000000-ffff-4000-8000-000000000002'$peer$)$test$,
  '55P03','FLOW_IDENTITY_ACTIVE_SCOPE_ACTOR_FENCE_BUSY',
  'seal first: peer business change fails before the uncommitted scope is visible');
select dblink_exec('ordinary_writer', 'rollback');
select dblink_disconnect('ordinary_writer');

savepoint outputs;
select lives_ok($$update public.processes set extracted_md='# fresh', search_text=array['fresh']
  where id=pg_temp.flow_identity_id('process')$$,
  'sealed Process permits combined worker output');
select lives_ok($$update public.flows set extracted_md='# fresh', search_text=array['fresh']
  where id=pg_temp.flow_identity_id('source_flow')$$,
  'sealed Flow permits combined worker output');
select lives_ok($$update public.processes
  set json_ordered=(' ' || json_ordered::text)::json, search_text=array['same body']
  where id=pg_temp.flow_identity_id('process')$$,
  'sealed Process preserves canonical JSON equality when only spelling changes');
select lives_ok($$update public.processes set
  embedding_ft = array_fill(0::real, array[1024])::extensions.vector(1024),
  embedding_ft_at = clock_timestamp() where id=pg_temp.flow_identity_id('process')$$,
  'sealed Process permits the vector and its timestamp to be written together');
rollback to outputs;
select throws_ok($$update public.processes set json_ordered='{}', search_text=array['mixed']
  where id=pg_temp.flow_identity_id('process')$$,
  '55000','FLOW_IDENTITY_ACTIVE_SCOPE_PROCESS_FENCE','mixed Process body write is fenced');
select throws_ok($$update public.flows set user_id=pg_temp.flow_identity_id('other'), extracted_md='# mixed'
  where id=pg_temp.flow_identity_id('source_flow')$$,
  '55000','FLOW_IDENTITY_ACTIVE_SCOPE_FLOW_FENCE','mixed Flow owner write is fenced');
select throws_ok($$update public.flows set team_id=team_id, search_text=array['mixed']
  where id=pg_temp.flow_identity_id('source_flow')$$,
  '55000','FLOW_IDENTITY_ACTIVE_SCOPE_FLOW_FENCE',
  'actual modified_at from the timestamp writer makes a no-op business SET non-neutral');
select throws_ok($$insert into public.processes (id,version,user_id,json_ordered)
  values (gen_random_uuid(),'01.00.000',pg_temp.flow_identity_id('owner'),
          pg_temp.flow_identity_process_payload(false)::json)$$,
  '55000','FLOW_IDENTITY_ACTIVE_SCOPE_PROCESS_FENCE','a new Process cannot introduce a captured reference');

-- An identity permit must be checked before JSON/version synchronization.
-- Keep the list of later hooks eligible on a worker SET list explicit: staging
-- touches only worker outputs, and the remaining hooks check or lock rows.
-- Any new hook that changes protected inputs on this path must run before the
-- identity fence. A new later hook requires review of its write set.
select is(array(
  select tgrelid::regclass::text || '.' || tgname from pg_trigger
  where tgrelid in ('public.processes'::regclass, 'public.flows'::regclass)
    and (tgtype & 19) = 19 and not tgisinternal and tgenabled in ('O', 'A')
    and tgname > case tgrelid when 'public.flows'::regclass
      then 'flows_z_identity_active_fence'::name
      else 'dataset_flow_identity_process_active_fence'::name end
    and (tgattr = ''::int2vector or exists (
      select 1 from pg_attribute where attrelid=tgrelid and attnum=any(tgattr)
        and attname in ('extracted_md','search_text','embedding_ft','embedding_ft_at')
    ))
  order by 1
), array['flows.protect_example_dataset_write', 'flows.review_dataset_content_guard_v1',
         'processes.process_derivative_rebuild_stage_embedding',
         'processes.process_derivative_rebuild_stage_markdown',
         'processes.protect_example_dataset_write', 'processes.review_dataset_content_guard_v1',
         'processes.zz_model_bundle_write_fence', 'processes.zzz_guard_process_result_lifecycle'],
  'all later BEFORE hooks eligible on worker columns have reviewed write sets');

create function pg_temp.change_process_state() returns trigger language plpgsql as $$
begin
  new.state_code := -1;
  return new;
end
$$;
create trigger aa_test_process_state before update of search_text on public.processes
for each row execute function pg_temp.change_process_state();
select throws_ok($$update public.processes set search_text=array['trigger mutation']
  where id=pg_temp.flow_identity_id('process')$$,
  '55000','FLOW_IDENTITY_ACTIVE_SCOPE_PROCESS_FENCE',
  'Process fence inspects a business change made by a preceding trigger');
drop trigger aa_test_process_state on public.processes;

insert into flow_identity_state(key, value)
select 'process_request', request || jsonb_build_object(
  'process_request_sha256',
    util.dataset_flow_identity_restricted_sha256_v2(request)
)
from (
  select jsonb_build_object(
    'schema_version', 'dataset-flow-identity-process-rewrite.v2',
    'request_id', 'fa000000-0000-4000-8000-000000000002',
    'scope_proof_sha256', preflight.value->>'scope_proof_sha256',
    'ordinal', 1,
    'process_intent_proof_sha256', ledger.process_intent_proof_sha256
  ) as request
  from flow_identity_state as preflight
  join util.dataset_flow_identity_process_ledger as ledger
    on ledger.scope_id = (preflight.value->>'scope_id')::uuid
    and ledger.ordinal = 1
  where preflight.key = 'preflight'
) as prepared;

set local role authenticated;
insert into flow_identity_state select 'rewrite', api.cmd_dataset_flow_identity_process_rewrite_guarded(
  (select (value->>'scope_id')::uuid from flow_identity_state where key='preflight'),
  (select value from flow_identity_state where key='process_request'),
  (select value->'execution_permit' from flow_identity_state where key='preflight'));
select is((select value->>'ok' from flow_identity_state where key='rewrite'), 'true',
          'bound rewrite succeeds before JSON/version synchronization');
reset role;
select is((select count(*) from util.dataset_flow_identity_mutation_permits where transaction_id=txid_current()),
          0::bigint,'the rewrite consumed its transaction-local row permit');
select is((select json from public.processes where id=pg_temp.flow_identity_id('process')),
          (select json_ordered::jsonb from public.processes where id=pg_temp.flow_identity_id('process')),
          'JSON sync persisted the authorized ordered body');
select is((select json #>> '{processDataSet,exchanges,exchange,0,referenceToFlowDataSet,@refObjectId}'
           from public.processes where id=pg_temp.flow_identity_id('process')),
          pg_temp.flow_identity_id('target_flow')::text,
          'the authorized rewrite persisted the captured target reference');
select throws_ok($$update public.processes set json_ordered='{}'
  where id=pg_temp.flow_identity_id('process')$$,
  '55000','FLOW_IDENTITY_ACTIVE_SCOPE_PROCESS_FENCE',
  'captured Process stays fenced after its authorized rewrite removed the source reference');

-- JSON accepts this escape, but JSONB cannot represent the NUL character.
-- A successful real UPDATE proves that the hot path did not parse the body.
-- Isolate the identity triggers: unrelated public expression indexes cast
-- the ordered JSON at INSERT time and cannot store this diagnostic value.
create temp table processes (like public.processes);
create temp table flows (like public.flows);
insert into pg_temp.processes(id,version,json,json_ordered) values
  ('fa000000-ffff-4000-8000-000000000003','01.00.000','{}','{"v":"\u0000"}');
insert into pg_temp.flows(id,version,json,json_ordered) values
  ('fa000000-ffff-4000-8000-000000000004','01.00.000','{}','{"v":"\u0000"}');
create trigger dataset_flow_identity_process_active_fence before update on pg_temp.processes
for each row execute function private.dataset_flow_identity_active_fence();
create trigger flows_z_identity_active_fence before update on pg_temp.flows
for each row execute function private.dataset_flow_identity_active_fence();
select lives_ok($$update pg_temp.processes set search_text=array['no reparse']
  where id='fa000000-ffff-4000-8000-000000000003'$$,
  'unchanged ordered Process JSON is not parsed on search writeback');
select lives_ok($$update pg_temp.flows set search_text=array['no reparse']
  where id='fa000000-ffff-4000-8000-000000000004'$$,
  'unchanged Flow is not converted to JSONB on search writeback');

select * from finish();
rollback;
