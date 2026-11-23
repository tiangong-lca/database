-- Run before resetting a disposable local migration replay. Both backends commit.
\set ON_ERROR_STOP on
select :'HOST' = '127.0.0.1' and :'PORT' = :'fixture_port'
  and current_database() = 'postgres'
  and not exists (select from auth.users)
  and not exists (select from public.processes)
  and not exists (select from public.flows)
  and not exists (select from vault.secrets where name in ('project_url','project_secret_key'))
  as blank_local \gset
\if :blank_local
\else
  do $$begin raise exception 'Expected an empty disposable loopback database'; end$$;
\endif
set statement_timeout = '20s';
set search_path = extensions, public, auth;
create extension if not exists dblink with schema extensions;
create function pg_temp.check_that(ok boolean, label text) returns void language plpgsql as $$
begin
  if ok is not true then raise exception 'FAIL %', label; end if;
  raise notice 'PASS %', label;
end $$;
grant execute on function pg_temp.check_that(boolean,text) to authenticated;
create function pg_temp.check_error(statement text, code text, message text)
returns void language plpgsql as $$
begin
  begin
    execute statement;
  exception when others then
    if sqlstate <> code or sqlerrm <> message then raise; end if;
    raise notice 'PASS % %', code, message;
    return;
  end;
  raise exception 'expected % % for %', code, message, statement;
end $$;
create function pg_temp.peer_rpc(query text) returns jsonb language sql as $$
  select result from extensions.dblink('peer',query) as r(result jsonb)
$$;

begin;
\ir ../fixtures/flow_identity_scope.sql
\set outsider 'fa110000-0000-4000-8000-000000000001'
\set unrelated_flow 'fa110000-0000-4000-8000-000000000002'
-- Only the first exchange is relevant to this extra draft.
select (pg_temp.flow_identity_process_payload(false, :'outsider') #- '{processDataSet,exchanges,exchange,2}'
        #- '{processDataSet,exchanges,exchange,1}') as old_body,
       (pg_temp.flow_identity_process_payload(true, :'outsider') #- '{processDataSet,exchanges,exchange,2}'
        #- '{processDataSet,exchanges,exchange,1}') as new_body \gset
insert into public.processes(id, version, user_id, state_code, json_ordered)
values (:'outsider','01.00.000',pg_temp.flow_identity_id('owner'),0,:'old_body');
insert into public.flows(id, version, user_id, state_code, json_ordered)
values (:'unrelated_flow','01.00.000',pg_temp.flow_identity_id('owner'),0,
        pg_temp.flow_identity_flow_payload(:'unrelated_flow','Unrelated')::json);
insert into private.teams(id,json,rank,is_public)
values ('00000000-0000-0000-0000-000000000000','{"name":"System"}',0,false) on conflict (id) do nothing;
insert into private.roles(user_id, team_id, role)
values (pg_temp.flow_identity_id('owner'),'00000000-0000-0000-0000-000000000000','data_product_manager');
commit;

select pg_temp.flow_identity_id('owner') as owner \gset
set request.jwt.claim.sub = :'owner';
set request.jwt.claim.role = 'authenticated';
set request.jwt.claim.email = 'flow-owner@example.com';
select dblink_connect('peer','host=db port=5432 dbname=postgres user=postgres password=postgres');
select dblink_exec('peer', format(
  'set statement_timeout=%L; set request.jwt.claim.sub=%L; set request.jwt.claim.role=%L;
   set request.jwt.claim.email=%L; set role authenticated',
  '15s', :'owner','authenticated','flow-owner@example.com'));
select pid as peer_pid from dblink('peer','select pg_backend_pid()') as r(pid int) \gset

-- Keep the page save open while the other backend commits the Flow deletion.
begin;
set local role authenticated;
select pg_temp.check_that((api.cmd_dataset_save_draft(
  'processes', :'outsider','01.00.000', :'new_body')->>'ok')::boolean, 'ordinary save');
reset role;
select pg_temp.check_that((pg_temp.peer_rpc(format(
  'select api.cmd_dataset_delete(%L,%L,%L)','flows',:'unrelated_flow','01.00.000'))->>'ok')::boolean,
  'overlapping same-owner deletion committed');
commit;
select pg_temp.check_that(
  (select json = :'new_body'::jsonb from public.processes where id=:'outsider')
  and not exists (select from public.flows where id=:'unrelated_flow')
  and not exists (select from util.dataset_flow_identity_capture_receipts)
  and not exists (select from util.dataset_flow_identity_scopes),
  'both ordinary changes persisted without a capture receipt or migration scope');

-- Capture a valid two-process manifest before a third draft adds the source.
select pg_temp.flow_identity_capture() as capture_request \gset
set role authenticated;
insert into flow_identity_state values
  ('capture',api.cmd_dataset_flow_identity_capture_attest_guarded(:'capture_request'));
reset role;
select pg_temp.check_that((value->>'ok')::boolean,'captured current manifest')
from flow_identity_state where key='capture';
select pg_temp.flow_identity_preflight() as seal_request \gset
begin;
set local role authenticated;
select pg_temp.check_that((api.cmd_dataset_save_draft(
  'processes', :'outsider','01.00.000', :'old_body')->>'ok')::boolean, 'third draft added source');
reset role;
select dblink_send_query('peer', format(
  'select api.cmd_dataset_flow_identity_scope_preflight_guarded(%L)', :'seal_request'));
-- Observe the actual lock wait, then let the same in-flight seal continue after commit.
select set_config('test.peer_pid', :'peer_pid', true);
do $$
declare deadline timestamptz := clock_timestamp() + interval '3 seconds';
begin
  while not pg_backend_pid() = any(pg_blocking_pids(current_setting('test.peer_pid')::int)) loop
    if clock_timestamp() >= deadline then raise exception 'sealing did not wait for writer'; end if;
    perform pg_sleep(0.01);
  end loop;
end $$;
commit;
select pg_temp.check_that(
  (select result->>'code' from dblink_get_result('peer') as r(result jsonb))
    = 'FLOW_IDENTITY_PREFLIGHT_LIVE_DRIFT',
  'waiting seal rechecked the committed reference and rejected the stale manifest');
select * from dblink_get_result('peer') as r(result jsonb);
select pg_temp.check_that(not exists (select from util.dataset_flow_identity_scopes),
  'stale manifest created no scope');

-- Freeze one valid manager publication before the migration takes the owner key.
\set result_id 'fa110000-0000-4000-8000-000000000004'
select (pg_temp.flow_identity_process_payload(true, :'result_id') #- '{processDataSet,exchanges}')::text
  as content \gset
select jsonb_build_object('table','processes','id',:'result_id','version','01.00.000',
  'contentText',:'content','contentSha256',encode(digest(:'content','sha256'),'hex'),
  'sourceKind','manager_attestation','source', jsonb_build_object(
    'candidateSetHash',repeat('a',64),'sourceManifestHash',repeat('b',64)),
  'audit',jsonb_build_object('reason','owner-lock regression')) as prepare \gset
set role authenticated;
select api.qry_result_process_publish_prepare_v1(:'prepare')#>>'{data,preparationHash}' as prepared \gset
reset role;
select jsonb_set(:'prepare','{source}',(:'prepare'::jsonb->'source') || jsonb_build_object(
  'executablePlanHash',repeat('c',64),'approvalHash',repeat('d',64))) || jsonb_build_object(
  'idempotencyKey','owner-lock-test','expectedPreparationHash',:'prepared') as publication \gset
select format('select api.cmd_result_process_publish_v1(%L)', :'publication') as publish_sql \gset

-- Restore the valid manifest and seal. The peer cannot see this scope yet.
set role authenticated;
select pg_temp.check_that((api.cmd_dataset_save_draft(
  'processes', :'outsider','01.00.000', :'new_body')->>'ok')::boolean, 'restored outside draft');
begin;
insert into flow_identity_state values
  ('preflight',api.cmd_dataset_flow_identity_scope_preflight_guarded(:'seal_request'));
reset role;
select pg_temp.check_that(value->>'status'='sealed','migration sealed')
from flow_identity_state where key='preflight';
select pg_temp.check_that(pg_temp.peer_rpc(:'publish_sql')->>'code'='result_publication_busy',
  'exclusive seal returned retryable publication busy');
select pg_temp.check_that(not exists (select from public.processes where id=:'result_id')
  and not exists (select from private.result_process_publications where dataset_id=:'result_id')
  and not exists (select from private.command_audit_log where target_id=:'result_id'),
  'publication busy left no row, receipt or audit');
select dblink_exec('peer','reset role');
select pg_temp.check_that(dblink_exec('peer',format(
  'update public.processes set search_text=array[%L] where id=%L','derived',:'outsider'))='UPDATE 1',
  'derived write committed during the exclusive transaction');
select pg_temp.check_error(format('select extensions.dblink_exec(%L,%L)','peer',format(
  'update public.processes set rule_verification=true, search_text=array[%L] where id=%L',
  'mixed',:'outsider')),'55P03','FLOW_IDENTITY_ACTIVE_SCOPE_ACTOR_FENCE_BUSY');
commit;

-- The exclusive transaction has ended. Scope guards must now decide each write.
select pg_temp.check_error(format('update public.processes set json_ordered=%L where id=%L',
  :'old_body',:'outsider'),'55000','FLOW_IDENTITY_ACTIVE_SCOPE_PROCESS_FENCE');
select pg_temp.check_error($q$update public.processes set user_id=pg_temp.flow_identity_id('other')
  where id=pg_temp.flow_identity_id('process')$q$,'55000','FLOW_IDENTITY_ACTIVE_SCOPE_PROCESS_FENCE');
select pg_temp.check_error($q$update public.flows set user_id=pg_temp.flow_identity_id('owner')
  where id=pg_temp.flow_identity_id('target_flow')$q$,'55000','FLOW_IDENTITY_ACTIVE_SCOPE_FLOW_FENCE');
select pg_temp.check_error($q$delete from public.flowproperties
  where id=pg_temp.flow_identity_id('flowproperty')$q$,'55000','FLOW_IDENTITY_ACTIVE_SCOPE_SUPPORT_FENCE');
select pg_temp.check_error($q$delete from public.unitgroups
  where id=pg_temp.flow_identity_id('unitgroup')$q$,'55000','FLOW_IDENTITY_ACTIVE_SCOPE_SUPPORT_FENCE');

-- A transfer takes both owner keys. The frozen publication can retry during
-- this ordinary transaction and replay its receipt after the transfer rolls back.
begin;
update public.processes set user_id=pg_temp.flow_identity_id('other') where id=:'outsider';
select pg_temp.flow_identity_id('other') as other_owner \gset
select pg_temp.check_that(not old_free and not new_free, 'transfer protects both owner keys')
from dblink('peer', format('select pg_try_advisory_xact_lock(hashtextextended(%L,0)),
  pg_try_advisory_xact_lock(hashtextextended(%L,0))',
  'dataset-flow-identity-actor:' || :'owner','dataset-flow-identity-actor:' || :'other_owner'))
  as r(old_free boolean,new_free boolean);
select dblink_exec('peer','set role authenticated');
select pg_temp.peer_rpc(:'publish_sql') as published \gset
select pg_temp.check_that(:'published'::jsonb->>'ok'='true' and :'published'::jsonb->>'reused'='false',
  'same frozen publication committed alongside the ordinary writer');
rollback;
select pg_temp.peer_rpc(:'publish_sql') as replay \gset
select pg_temp.check_that(:'replay'::jsonb->>'reused'='true'
  and :'published'::jsonb#>>'{data,receiptId}' = :'replay'::jsonb#>>'{data,receiptId}',
  'publication retry reused the same receipt');
select dblink_exec('peer','reset role');

-- The real rewrite owns the exclusive key and consumes exactly one permit.
select value->>'scope_id' as scope, value->'execution_permit' as permit,
       value->>'scope_proof_sha256' as scope_proof from flow_identity_state where key='preflight' \gset
select jsonb_build_object('schema_version','dataset-flow-identity-process-rewrite.v2',
  'request_id','fa110000-0000-4000-8000-000000000003','scope_proof_sha256',:'scope_proof',
  'ordinal',1,'process_intent_proof_sha256',process_intent_proof_sha256) as intent
from util.dataset_flow_identity_process_ledger where scope_id=:'scope' and ordinal=1 \gset
select :'intent'::jsonb || jsonb_build_object('process_request_sha256',
  util.dataset_flow_identity_restricted_sha256_v2(:'intent')) as rewrite_request \gset
begin;
set local role authenticated;
select api.cmd_dataset_flow_identity_process_rewrite_guarded(
  :'scope',:'rewrite_request',:'permit') as rewrite \gset
select pg_temp.check_that((:'rewrite'::jsonb->>'ok')::boolean,'authorized rewrite');
reset role;
select pg_temp.check_error(format('select extensions.dblink_exec(%L,%L)','peer',format(
  'update public.processes set rule_verification=true where id=%L',:'outsider')),
  '55P03','FLOW_IDENTITY_ACTIVE_SCOPE_ACTOR_FENCE_BUSY');
commit;
select pg_temp.check_that(
  (select json = pg_temp.flow_identity_process_payload(true) from public.processes
   where id=pg_temp.flow_identity_id('process'))
  and not exists (select from util.dataset_flow_identity_mutation_permits),
  'rewritten body committed and permit consumed');
select pg_temp.check_error($q$update public.processes set rule_verification=true
  where id=pg_temp.flow_identity_id('process')$q$,'55000','FLOW_IDENTITY_ACTIVE_SCOPE_PROCESS_FENCE');
-- Finalization must also acquire the exclusive owner key before checking completion.
select jsonb_build_object('schema_version','dataset-flow-identity-scope-finalize.v2',
  'request_id','fa110000-0000-4000-8000-000000000005','scope_proof_sha256',:'scope_proof',
  'expected',jsonb_build_object('process_count',process_count,'rewrite_count',rewrite_count,
    'completed_process_count',process_count)) as finalize_request
from util.dataset_flow_identity_scopes where id=:'scope' \gset
begin;
update public.processes set rule_verification=true where id=:'outsider';
select dblink_exec('peer','set role authenticated');
select pg_temp.check_that(pg_temp.peer_rpc(format(
  'select api.cmd_dataset_flow_identity_scope_finalize_guarded(%L,%L,%L)',
  :'scope', :'finalize_request', :'rewrite'::jsonb->'execution_permit'))->>'code'
    = 'FLOW_IDENTITY_FINALIZE_LOCK_BUSY', 'final check excludes overlapping ordinary writes');
rollback;
select dblink_disconnect('peer');
