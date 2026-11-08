begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,api,private;
select no_plan();
\ir fixtures/calculation-admission.sql

select ok(not has_function_privilege('authenticated',
  'private.lcia_result_build_request_envelope(text,jsonb,text,text,jsonb,text,jsonb,jsonb)',
  'execute'), 'browser cannot supply a forged frozen eligibility context');
select ok(not has_function_privilege('service_role',
  'private.lcia_result_build_request_envelope(text,jsonb,text,text,jsonb,text,jsonb,jsonb)',
  'execute'), 'service cannot call the owner-only envelope helper');

-- A structural performance oracle: even an empty/small live table cannot hide
-- accidentally restoring the expensive global-manifest call in V2.
create or replace function api.lcia_result_current_eligible_manifest()
returns jsonb language plpgsql stable security definer
set search_path=api,private,public,util,extensions,pg_temp as $$
begin raise exception 'unexpected global manifest reconstruction'; end $$;

set local role authenticated;
create temporary table admission_build_response as
select pg_temp.admission_submit('admission958-build') response;
reset role;
select is((select response->>'ok' from admission_build_response),'true',
  '5741-process / 25-method frozen build submits without reading the global manifest');
select is((select (response#>>'{data,eligibleInputCount}')::int from admission_build_response),
  :admission_scale, 'V2 eligibility count describes the certified scope');
select is((select (response#>>'{data,includedInputCount}')::int from admission_build_response),
  :admission_scale, 'all certified processes are included');
create temporary table admission_build_before as
select * from private.worker_jobs where id=(select (response#>>'{data,workerJobId}')::uuid
  from admission_build_response);
select is((select jsonb_array_length(payload_json#>'{input_manifest,processes}')
  from admission_build_before),:admission_scale,'queued manifest retains every frozen process');
select is((select jsonb_array_length(payload_json->'lcia_method_set') from admission_build_before),
  25,'queued payload retains all certified LCIA methods');
select ok((select payload_json->'effective_scope'=c.effective_scope_manifest
  and payload_ref#>>'{closureCertificate,snapshotId}'=c.snapshot_id::text
  and payload_json->>'closure_certificate_hash'=c.certificate_hash
  and (payload_json->>'eligibility_resolved_at')::timestamptz=c.finished_at
  from admission_build_before j cross join private.lcia_scope_closure_checks c
  where c.id=(select id from admission_parameters)),
  'queued scope, snapshot, certificate and stable timestamp bind to the certificate');
set local role authenticated;
select is(pg_temp.admission_submit('admission958-build')#>>'{data,workerJobId}',
  (select response#>>'{data,workerJobId}' from admission_build_response),
  'identical retry returns the same canonical worker job');
reset role;
select is((select count(*) from private.worker_jobs j join admission_build_before b on b.id=j.id),
  1::bigint,'retry does not enqueue another worker job');
select is((select count(*) from private.worker_job_events where job_id=(select id from admission_build_before)
  and event_type='enqueued'),1::bigint,'retry creates no second enqueue event');
select is((select to_jsonb(j) from private.worker_jobs j where id=(select id from admission_build_before)),
  (select to_jsonb(b) from admission_build_before b),'retry leaves the canonical payload and lease unchanged');
set local role authenticated;
select is((select api.cmd_lcia_result_build_request_v2('changed build name',null,
  'global_eligible',null,'[]','admission958-build',id,requested_scope_hash,
  policy_fingerprint,'{}')->>'code' from admission_parameters),
  'build_enqueue_conflict','same key with changed execution payload remains a conflict');
reset role;
select is((select to_jsonb(j) from private.worker_jobs j where id=(select id from admission_build_before)),
  (select to_jsonb(b) from admission_build_before b),'conflicting retry cannot mutate the admitted job');

create temporary table admission_side_effects as
select (select count(*) from private.worker_jobs) jobs,
  (select count(*) from private.worker_job_events) events,
  (select count(*) from private.command_audit_log) audits;
set local role authenticated;
select is(pg_temp.admission_submit('admission958-wrong-scope','wrong')->>'code',
  'closure_check_scope_mismatch','scope mismatch is rejected');
select is(pg_temp.admission_submit('admission958-wrong-policy',null,'wrong')->>'code',
  'closure_check_policy_mismatch','policy mismatch is rejected');
select set_config('request.jwt.claim.sub','c9580000-0000-4000-8000-000000000002',true);
select is(pg_temp.admission_submit('admission958-other-owner')->>'code',
  'closure_check_not_found','another manager cannot use this certificate');
select set_config('request.jwt.claim.sub','',true);
select is(pg_temp.admission_submit('admission958-anonymous')->>'code','auth_required',
  'missing actor is rejected');
select set_config('request.jwt.claim.sub','c9580000-0000-4000-8000-000000000001',true);
reset role;

savepoint manager_denial;
delete from private.roles where user_id='c9580000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.admission_submit('admission958-demoted')->>'code' as denial_code \gset

reset role;
rollback to manager_denial;
select is(:'denial_code'::text,'not_data_product_manager','live manager permission remains required');

savepoint stale_denial;
update private.lcia_scope_closure_checks set certificate_status='stale'
where id=(select id from admission_parameters);
set local role authenticated;
select pg_temp.admission_submit('admission958-stale')->>'code' as denial_code \gset

reset role;
rollback to stale_denial;
select is(:'denial_code'::text,'closure_check_not_usable','stale certificate is rejected');

savepoint revoked_denial;
update private.lcia_scope_closure_checks set certificate_status='revoked'
where id=(select id from admission_parameters);
set local role authenticated;
select pg_temp.admission_submit('admission958-revoked')->>'code' as denial_code \gset

reset role;
rollback to revoked_denial;
select is(:'denial_code'::text,'closure_check_not_usable','revoked certificate is rejected');

savepoint expired_denial;
update private.worker_job_artifacts set lifecycle_state='expired'
where id='c9580000-0000-4000-8000-000000000201';
set local role authenticated;
select pg_temp.admission_submit('admission958-expired')->>'code' as denial_code \gset

reset role;
rollback to expired_denial;
select is(:'denial_code'::text,'closure_certificate_expired','expired report evidence is rejected');

savepoint snapshot_denial;
update private.lca_network_snapshots set status='failed'
where id=(select snapshot_id from private.lcia_scope_closure_checks where id=(select id from admission_parameters));
set local role authenticated;
select pg_temp.admission_submit('admission958-bad-snapshot')->>'code' as denial_code \gset

reset role;
rollback to snapshot_denial;
select is(:'denial_code'::text,'closure_snapshot_binding_invalid','unready numerical snapshot is rejected');

savepoint membership_denial;
update private.lcia_scope_closure_checks set requested_scope_manifest=
  jsonb_set(requested_scope_manifest,'{certificateFreshnessPolicy}','"current-membership-required-v1"')
where id=(select id from admission_parameters);
create or replace function private.lcia_scope_closure_current_release_matches(p_snapshot_token text)
returns boolean language sql stable security definer as $$select false$$;
set local role authenticated;
select pg_temp.admission_submit('admission958-membership-stale')->>'code' as denial_code \gset

reset role;
rollback to membership_denial;
select is(:'denial_code'::text,'closure_check_stale','current-membership freshness still runs when the certificate policy requires it');

savepoint eligibility_denial;
alter table public.processes disable trigger user;
update public.processes set state_code=0 where id='c9581000-0000-4000-8000-000000000001';
alter table public.processes enable trigger user;
set local role authenticated;
select pg_temp.admission_submit('admission958-ineligible')->>'code' as denial_code \gset

reset role;
rollback to eligibility_denial;
select is(:'denial_code'::text,'input_not_eligible','exact selected-row eligibility remains checked');

-- The unchanged legacy routes still resolve their live eligibility universe.
select throws_ok($$select private.cmd_lcia_result_build_request_legacy('legacy',null,
  'global_eligible',null,'[]','admission958-legacy','{}')$$,
  'P0001','unexpected global manifest reconstruction','legacy global behavior is preserved');
select throws_ok($$select private.cmd_lcia_result_build_request_legacy('legacy',
  '[{"id":"c9581000-0000-4000-8000-000000000001","version":"01.00.000"}]',
  'subset',null,'[]','admission958-legacy-subset','{}')$$,
  'P0001','unexpected global manifest reconstruction','legacy manual behavior is preserved');

create function pg_temp.admission_fail_enqueue() returns trigger language plpgsql as $$
begin
  if new.job_kind='lcia_result.package_build' then
    raise exception 'synthetic submission timeout' using errcode='57014';
  end if;
  return new;
end$$;
create trigger admission958_fail_enqueue before insert on private.worker_jobs
for each row execute function pg_temp.admission_fail_enqueue();
-- query_canceled is intentionally excluded from PL/pgSQL OTHERS (including
-- pgTAP throws_ok); catch that class explicitly around the real invocation.
create function pg_temp.admission_timeout_probe() returns text language plpgsql as $$
begin
  perform pg_temp.admission_submit('admission958-timeout');
  return 'unexpected success';
exception when query_canceled then return sqlstate;
end$$;
grant execute on function pg_temp.admission_timeout_probe() to authenticated;
set local role authenticated;
select is(pg_temp.admission_timeout_probe(),'57014',
  'injected late timeout aborts the whole submission');
reset role;
select is((select count(*) from private.worker_jobs),(select jobs from admission_side_effects),
  'denials and timeout leave no partial job');
select is((select count(*) from private.worker_job_events),(select events from admission_side_effects),
  'denials and timeout leave no enqueue event');
select is((select count(*) from private.command_audit_log),(select audits from admission_side_effects),
  'denials and timeout leave no partial command audit');

select * from finish();
rollback;
