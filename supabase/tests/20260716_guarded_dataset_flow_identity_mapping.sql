begin;

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
set local search_path = extensions, public, auth;

select no_plan();

\ir fixtures/flow_identity_scope.sql

grant select on private.command_audit_log to authenticated;
grant select on util.dataset_derivative_rebuild_requests to authenticated;
grant select on util.dataset_flow_identity_process_ledger to authenticated;
grant select on util.dataset_flow_identity_scopes to authenticated;
grant select on util.dataset_flow_identity_capture_receipts to authenticated;
-- Request builders run in the authenticated section to exercise the public
-- surface.  These private helper grants exist only inside this rolled-back
-- pgTAP transaction; production migration grants remain unchanged.
grant usage on schema private, util to authenticated;
grant execute on function private.dataset_alias_canonical_jsonb_v1(jsonb)
  to authenticated;
grant execute on function private.dataset_alias_js_object_key_sort_key_v1(text)
  to authenticated;
grant execute on function util.dataset_flow_identity_sha256(jsonb)
  to authenticated;
grant execute on function util.dataset_flow_identity_restricted_sha256_v2(jsonb)
  to authenticated;
grant execute on function private.dataset_flow_identity_safe_json_v2(jsonb)
  to authenticated;
grant execute on function private.dataset_flow_identity_exact_keys(jsonb, text[])
  to authenticated;
grant execute on function private.dataset_flow_identity_short_description_v2(jsonb)
  to authenticated;
grant execute on function private.dataset_flow_identity_row_sha256(
  uuid, text, uuid, integer, timestamp with time zone, text
) to authenticated;
grant execute on function private.dataset_flow_identity_exchanges(jsonb)
  to authenticated;
grant execute on function private.dataset_flow_identity_reference(jsonb)
  to authenticated;
grant execute on function private.dataset_flow_identity_collision_ledger(
  jsonb, jsonb
) to authenticated;
grant execute on function util.dataset_derivative_rebuild_snapshot(
  public.processes
) to authenticated;
grant execute on function util.dataset_derivative_rebuild_sha256(text)
  to authenticated;
grant execute on function util.read_dataset_derivative_rebuild_batch_any(
  uuid, uuid
) to authenticated;
grant execute on function util.read_dataset_flow_identity_derivative_set(
  uuid, uuid
) to authenticated;

create or replace function pg_temp.complete_flow_identity_derivative(
  p_request_id uuid,
  p_suffix text
) returns void
language plpgsql
as $$
declare
  v_request util.dataset_derivative_rebuild_requests%rowtype;
  v_markdown text;
  v_markdown_sha256 text;
  v_markdown_id bigint;
  v_embedding extensions.vector(1024);
  v_embedding_id bigint;
  v_snapshot jsonb;
begin
  select request.* into strict v_request
  from util.dataset_derivative_rebuild_requests as request
  where request.id = p_request_id;

  v_markdown := 'flow identity derivative ' || p_suffix;
  v_markdown_sha256 := util.dataset_derivative_rebuild_sha256(v_markdown);
  v_embedding := (
    '[' || array_to_string(array_fill('0'::text, array[1024]), ',') || ']'
  )::extensions.vector;

  insert into util.dataset_derivative_rebuild_proposals (
    request_id, proposal_kind, extracted_md, extracted_md_sha256, status
  ) values (
    p_request_id, 'markdown', v_markdown, v_markdown_sha256, 'accepted'
  ) returning id into v_markdown_id;

  insert into util.dataset_derivative_rebuild_proposals (
    request_id, proposal_kind, embedding_ft, embedding_ft_sha256,
    embedding_ft_at, source_extracted_md_sha256, status
  ) values (
    p_request_id, 'embedding', v_embedding,
    util.dataset_derivative_rebuild_sha256(v_embedding::text),
    clock_timestamp() + interval '1 second', v_markdown_sha256, 'captured'
  ) returning id into v_embedding_id;

  update util.dataset_derivative_rebuild_requests
  set
    markdown_proposal_id = v_markdown_id,
    accepted_extracted_md_sha256 = v_markdown_sha256,
    markdown_request_id = -9100000,
    markdown_dispatched_at = clock_timestamp() - interval '3 seconds',
    markdown_response_status = 200,
    markdown_response_received_at = clock_timestamp() - interval '2 seconds',
    embedding_queue_msg_id = -8100000,
    embedding_queued_at = clock_timestamp() - interval '1 second'
  where id = p_request_id;

  perform util.commit_dataset_derivative_rebuild_proposal(
    p_request_id, v_markdown_id, v_embedding_id
  );

  v_snapshot := util.dataset_derivative_rebuild_snapshot(
    v_request.target_table, v_request.target_id, v_request.target_version
  );
  update util.dataset_derivative_rebuild_requests
  set
    status = 'completed',
    phase = 'completed',
    completed_snapshot_sha256 = v_snapshot->>'snapshot_sha256',
    completed_at = clock_timestamp(),
    terminal_at = clock_timestamp(),
    drained_at = clock_timestamp()
  where id = p_request_id;

  perform util.record_dataset_derivative_rebuild_terminal(p_request_id);
end
$$;

create or replace function pg_temp.flow_identity_lookup()
returns jsonb
language sql
stable
as $$
  select jsonb_set(
    pg_temp.flow_identity_preflight(),
    '{schema_version}', '"dataset-flow-identity-scope-lookup.v1"'::jsonb,
    false
  )
    - 'maximum_wrapper_invocations'
    - 'maximum_process_posts'
    - 'maximum_finalize_posts'
    - 'maximum_cli_apply_spawns'
    - 'approval_reusable'
    - 'automatic_retry'
$$;

create or replace function pg_temp.flow_identity_recovery_request(
  p_scope_id uuid,
  p_reason text,
  p_nonce uuid
) returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_temp, public, util
as $$
declare
  v_scope util.dataset_flow_identity_scopes%rowtype;
  v_status jsonb;
  v_completed integer;
begin
  select scope.* into strict v_scope
  from util.dataset_flow_identity_scopes as scope
  where scope.id = p_scope_id and scope.actor_user_id = auth.uid();
  v_status := api.cmd_dataset_flow_identity_scope_read(p_scope_id);
  if v_status->>'status' in ('failed', 'live_drift')
    or v_status->>'whole_scope_proof_sha256' !~ '^[a-f0-9]{64}$' then
    raise exception 'test recovery status proof failed: %', v_status;
  end if;
  v_completed := (v_status->>'completed_process_count')::integer;
  return jsonb_build_object(
    'schema_version', 'dataset-flow-identity-scope-recovery.v1',
    'request_id', p_nonce,
    'approved_at_utc', clock_timestamp(),
    'environment', v_scope.environment,
    'project_ref', v_scope.project_ref,
    'actor', jsonb_build_object(
      'user_id', v_scope.actor_user_id,
      'email', v_scope.actor_email
    ),
    'target_visibility', v_scope.target_visibility,
    'user_state_claim', v_scope.user_state_claim,
    'operation_id', v_scope.operation_id,
    'plan_sha256', v_scope.plan_sha256,
    'freeze_sha256', v_scope.freeze_sha256,
    'original_execution_approval_identity_sha256',
      v_scope.approval_identity_sha256,
    'scope_proof_sha256', v_scope.scope_proof_sha256,
    'observed_scope_status', v_scope.status,
    'observed_completed_process_count', v_completed,
    'observed_next_ordinal', (v_status->>'next_ordinal')::integer,
    'observed_whole_scope_proof_sha256',
      v_status->>'whole_scope_proof_sha256',
    'recovery_mode', case when v_completed = v_scope.process_count
      then 'finalize_only' else 'resume_and_finalize' end,
    'recovery_reason', p_reason,
    'toolchain_evidence_sha256', v_scope.toolchain_evidence_sha256,
    'maximum_wrapper_invocations', 1,
    'maximum_process_posts', v_scope.process_count - v_completed,
    'maximum_finalize_posts', 1,
    'maximum_cli_apply_spawns', 1,
    'approval_reusable', false,
    'automatic_retry', false,
    'recovery_approval_request_sha256',
      util.dataset_flow_identity_restricted_sha256_v2(jsonb_build_object(
        'nonce', p_nonce, 'domain', 'artifact-request'
      )),
    'recovery_approval_text_sha256',
      util.dataset_flow_identity_restricted_sha256_v2(jsonb_build_object(
        'nonce', p_nonce, 'domain', 'approval-text'
      )),
    'recovery_approval_identity_sha256',
      util.dataset_flow_identity_restricted_sha256_v2(jsonb_build_object(
        'nonce', p_nonce, 'domain', 'approval-identity'
      ))
  );
end;
$$;

create or replace function pg_temp.flow_identity_recover(
  p_scope_id uuid,
  p_reason text
) returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_temp, public
as $$
begin
  return api.cmd_dataset_flow_identity_scope_recover_guarded(
    p_scope_id,
    pg_temp.flow_identity_recovery_request(
      p_scope_id, p_reason, gen_random_uuid()
    )
  );
end;
$$;

create or replace function pg_temp.flow_identity_private_counts()
returns jsonb
language sql
stable
security definer
set search_path = public, util
as $$
  select jsonb_build_object(
    'scope_count', (select count(*)
      from util.dataset_flow_identity_scopes),
    'invocation_count', (select count(*)
      from util.dataset_flow_identity_wrapper_invocations),
    'audit_count', (select count(*) from private.command_audit_log)
  )
$$;

create or replace function pg_temp.flow_identity_invocation(
  p_invocation_id uuid
) returns jsonb
language sql
stable
security definer
set search_path = util
as $$
  select to_jsonb(invocation)
  from util.dataset_flow_identity_wrapper_invocations as invocation
  where invocation.id = p_invocation_id
$$;

create or replace function pg_temp.flow_identity_business_state(
  p_scope_id uuid
) returns jsonb
language sql
stable
security definer
set search_path = pg_temp, public, util
as $$
  select jsonb_build_object(
    'process_rows_sha256', util.dataset_flow_identity_sha256(coalesce((
      select jsonb_agg(to_jsonb(process) order by process.id)
      from public.processes as process
      where process.id in (
        pg_temp.flow_identity_id('process'),
        pg_temp.flow_identity_id('process_2')
      )
    ), '[]'::jsonb)),
    'flow_guard_rows_sha256', util.dataset_flow_identity_sha256(coalesce((
      select jsonb_agg(to_jsonb(flow) order by flow.id)
      from public.flows as flow
      where flow.id in (
        pg_temp.flow_identity_id('source_flow'),
        pg_temp.flow_identity_id('target_flow'),
        pg_temp.flow_identity_id('pending_flow')
      )
    ), '[]'::jsonb)),
    'flowproperty_guard_row_sha256',
      util.dataset_flow_identity_sha256(coalesce((
        select to_jsonb(flowproperty)
        from public.flowproperties as flowproperty
        where flowproperty.id = pg_temp.flow_identity_id('flowproperty')
          and btrim(flowproperty.version::text) = '01.00.000'
      ), '{}'::jsonb)),
    'unitgroup_guard_row_sha256',
      util.dataset_flow_identity_sha256(coalesce((
        select to_jsonb(unitgroup)
        from public.unitgroups as unitgroup
        where unitgroup.id = pg_temp.flow_identity_id('unitgroup')
          and btrim(unitgroup.version::text) = '01.00.000'
      ), '{}'::jsonb)),
    'ledger_rows_sha256', util.dataset_flow_identity_sha256(coalesce((
      select jsonb_agg(to_jsonb(ledger) order by ledger.ordinal)
      from util.dataset_flow_identity_process_ledger as ledger
      where ledger.scope_id = p_scope_id
    ), '[]'::jsonb)),
    'audit_rows_sha256', util.dataset_flow_identity_sha256(coalesce((
      select jsonb_agg(to_jsonb(audit) order by audit.id)
      from private.command_audit_log as audit
      where audit.payload->>'scope_id' = p_scope_id::text
    ), '[]'::jsonb)),
    'derivative_rows_sha256', util.dataset_flow_identity_sha256(coalesce((
      select jsonb_agg(to_jsonb(child) order by child.id)
      from util.dataset_derivative_rebuild_requests as child
      join util.dataset_flow_identity_scopes as scope
        on scope.id = p_scope_id
        and child.actor_user_id = scope.actor_user_id
        and child.plan_sha256 = scope.plan_sha256
        and child.operation_id = scope.operation_id
      where child.target_table = 'processes'
        and exists (
          select 1
          from util.dataset_flow_identity_process_ledger as ledger
          where ledger.scope_id = scope.id
            and child.target_id = ledger.process_id
            and child.target_version = ledger.process_version
            and child.reason_code = 'FLOW_IDENTITY_SCOPE:'
              || scope.id::text || ':' || ledger.ordinal::text
        )
    ), '[]'::jsonb)),
    'mutation_permit_rows_sha256',
      util.dataset_flow_identity_sha256(coalesce((
        select jsonb_agg(to_jsonb(mutation) order by mutation.ordinal)
        from util.dataset_flow_identity_mutation_permits as mutation
        where mutation.scope_id = p_scope_id
      ), '[]'::jsonb)),
    'scope_row_sha256', util.dataset_flow_identity_sha256(coalesce((
      select to_jsonb(scope)
      from util.dataset_flow_identity_scopes as scope
      where scope.id = p_scope_id
    ), '{}'::jsonb))
  )
$$;

create or replace function pg_temp.flow_identity_atomic_state(
  p_scope_id uuid,
  p_invocation_id uuid
) returns jsonb
language sql
stable
security definer
set search_path = pg_temp, public, util
as $$
  select jsonb_build_object(
    'business', pg_temp.flow_identity_business_state(p_scope_id),
    'flow_rows_sha256', util.dataset_flow_identity_sha256(coalesce((
      select jsonb_agg(to_jsonb(flow) order by flow.id)
      from public.flows as flow
      where flow.id in (
        pg_temp.flow_identity_id('source_flow'),
        pg_temp.flow_identity_id('target_flow'),
        pg_temp.flow_identity_id('pending_flow')
      )
    ), '[]'::jsonb)),
    'flowproperty_row_sha256',
      util.dataset_flow_identity_sha256(coalesce((
        select to_jsonb(flowproperty)
        from public.flowproperties as flowproperty
        where flowproperty.id = pg_temp.flow_identity_id('flowproperty')
          and btrim(flowproperty.version::text) = '01.00.000'
      ), '{}'::jsonb)),
    'unitgroup_row_sha256', util.dataset_flow_identity_sha256(coalesce((
      select to_jsonb(unitgroup)
      from public.unitgroups as unitgroup
      where unitgroup.id = pg_temp.flow_identity_id('unitgroup')
        and btrim(unitgroup.version::text) = '01.00.000'
    ), '{}'::jsonb)),
    'invocation_row_sha256', util.dataset_flow_identity_sha256(coalesce((
      select to_jsonb(invocation)
      from util.dataset_flow_identity_wrapper_invocations as invocation
      where invocation.id = p_invocation_id
    ), '{}'::jsonb))
  )
$$;

create or replace function pg_temp.flow_identity_drift_probe(
  p_phase text,
  p_kind text,
  p_authorization jsonb
) returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_temp, public, util
as $$
declare
  v_scope_id uuid := (
    select (value->>'scope_id')::uuid
    from pg_temp.flow_identity_state where key = 'preflight'
  );
  v_invocation_id uuid := (p_authorization->>'invocation_id')::uuid;
  v_before jsonb;
  v_injected jsonb;
  v_during jsonb;
  v_after jsonb;
  v_result jsonb;
  v_payload jsonb;
  v_scope_status text;
  v_derivative_request_id uuid;
  v_derivative_status text;
  v_derivative_terminal_at timestamp with time zone;
begin
  if p_phase not in ('process', 'finalize')
    or p_kind not in (
      'process', 'source', 'target', 'flowproperty', 'unitgroup', 'occurrence'
    ) then
    raise exception 'unsupported drift probe: %/%', p_phase, p_kind;
  end if;
  v_before := pg_temp.flow_identity_atomic_state(
    v_scope_id, v_invocation_id
  );
  select scope.status into strict v_scope_status
  from util.dataset_flow_identity_scopes as scope
  where scope.id = v_scope_id;
  begin
    -- Active fences make these drifts impossible to ordinary callers.  The
    -- definer-only test probe temporarily removes this scope from the active
    -- fence set solely to prove that the process/finalize revalidators still
    -- fail closed if a row ever drifts.
    update util.dataset_flow_identity_scopes
    set status = 'failed'
    where id = v_scope_id;
    if p_phase = 'finalize' and p_kind in ('process', 'occurrence') then
      select child.id, child.status, child.terminal_at
      into strict v_derivative_request_id, v_derivative_status,
        v_derivative_terminal_at
      from util.dataset_derivative_rebuild_requests as child
      where child.target_table = 'processes'
        and child.target_id = pg_temp.flow_identity_id('process')
        and child.target_version = '01.00.000';
      update util.dataset_derivative_rebuild_requests
      set status = 'stale', terminal_at = clock_timestamp()
      where id = v_derivative_request_id;
    end if;
    case p_kind
      when 'process' then
        select jsonb_set(
          process.json_ordered::jsonb,
          '{processDataSet,exchanges,exchange,0,generalComment,#text}',
          '"drifted"'::jsonb,
          false
        ) into strict v_payload
        from public.processes as process
        where process.id = pg_temp.flow_identity_id('process')
          and btrim(process.version::text) = '01.00.000';
        update public.processes as process
        set json = v_payload,
          json_ordered = v_payload::json
        where process.id = pg_temp.flow_identity_id('process')
          and btrim(process.version::text) = '01.00.000';
      when 'source' then
        update public.flows as flow
        set modified_at = flow.modified_at + interval '1 microsecond'
        where flow.id = pg_temp.flow_identity_id('source_flow')
          and btrim(flow.version::text) = '01.00.000';
      when 'target' then
        update public.flows as flow
        set modified_at = flow.modified_at + interval '1 microsecond'
        where flow.id = pg_temp.flow_identity_id('target_flow')
          and btrim(flow.version::text) = '01.00.000';
      when 'flowproperty' then
        update public.flowproperties as flowproperty
        set modified_at = flowproperty.modified_at + interval '1 microsecond'
        where flowproperty.id = pg_temp.flow_identity_id('flowproperty')
          and btrim(flowproperty.version::text) = '01.00.000';
      when 'unitgroup' then
        update public.unitgroups as unitgroup
        set modified_at = unitgroup.modified_at + interval '1 microsecond'
        where unitgroup.id = pg_temp.flow_identity_id('unitgroup')
          and btrim(unitgroup.version::text) = '01.00.000';
      when 'occurrence' then
        select jsonb_set(
          process.json_ordered::jsonb,
          '{processDataSet,exchanges,exchange,2,exchangeDirection}',
          '"Output"'::jsonb,
          false
        ) into strict v_payload
        from public.processes as process
        where process.id = pg_temp.flow_identity_id('process')
          and btrim(process.version::text) = '01.00.000';
        update public.processes as process
        set json = v_payload,
          json_ordered = v_payload::json
        where process.id = pg_temp.flow_identity_id('process')
          and btrim(process.version::text) = '01.00.000';
    end case;
    if v_derivative_request_id is not null then
      update util.dataset_derivative_rebuild_requests
      set status = v_derivative_status,
        terminal_at = v_derivative_terminal_at
      where id = v_derivative_request_id;
    end if;
    update util.dataset_flow_identity_scopes
    set status = v_scope_status
    where id = v_scope_id;
    v_injected := pg_temp.flow_identity_business_state(v_scope_id);
    if p_phase = 'process' then
      v_result := api.cmd_dataset_flow_identity_process_rewrite_guarded(
        v_scope_id,
        (select value from pg_temp.flow_identity_state
          where key = 'process_request'),
        p_authorization
      );
    else
      v_result := api.cmd_dataset_flow_identity_scope_finalize_guarded(
        v_scope_id,
        (select value from pg_temp.flow_identity_state
          where key = 'finalize_request'),
        p_authorization
      );
    end if;
    v_during := pg_temp.flow_identity_business_state(v_scope_id);
    raise exception using errcode = 'P7001',
      message = 'FLOW_IDENTITY_TEST_DRIFT_PROBE_ROLLBACK';
  exception when sqlstate 'P7001' then
    null;
  end;
  v_after := pg_temp.flow_identity_atomic_state(v_scope_id, v_invocation_id);
  return jsonb_build_object(
    'phase', p_phase,
    'kind', p_kind,
    'result', v_result,
    'business_unchanged_during_rejection', v_injected = v_during,
    'probe_rolled_back_exactly', v_before = v_after
  );
end;
$$;

create or replace function pg_temp.flow_identity_post_primary_fault()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.command = 'cmd_dataset_flow_identity_process_rewrite_guarded'
    and old.payload->>'schema_version'
      = 'dataset-flow-identity-process-rewrite.v1'
    and new.payload->>'schema_version'
      = 'dataset-flow-identity-process-rewrite.v2' then
    raise exception using errcode = 'P0001',
      message = 'FLOW_IDENTITY_TEST_POST_PRIMARY_FAULT';
  end if;
  return new;
end;
$$;

create or replace function pg_temp.flow_identity_orphan_derivative_probe(
  p_scope_id uuid
) returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_temp, public, util
as $$
declare
  v_before jsonb := pg_temp.flow_identity_business_state(p_scope_id);
  v_during jsonb;
  v_after jsonb;
  v_orphan_id uuid := gen_random_uuid();
  v_orphan_batch_id uuid := gen_random_uuid();
begin
  begin
    insert into util.dataset_derivative_rebuild_requests
    select (jsonb_populate_record(
      null::util.dataset_derivative_rebuild_requests,
      to_jsonb(child) || jsonb_build_object(
        'id', v_orphan_id,
        'batch_id', v_orphan_batch_id,
        'batch_ordinal', 1,
        'batch_target_count', 1,
        'action_id', child.action_id || ':orphan-proof',
        'plan_request_sha256', util.dataset_flow_identity_sha256(
          jsonb_build_object('orphan_id', v_orphan_id, 'domain', 'plan')
        ),
        'action_request_sha256', util.dataset_flow_identity_sha256(
          jsonb_build_object('orphan_id', v_orphan_id, 'domain', 'action')
        ),
        'status', 'stale',
        'terminal_at', clock_timestamp(),
        'last_error', jsonb_build_object('code', 'TEST_ORPHAN_CAUSAL_CHILD')
      )
    )).*
    from util.dataset_derivative_rebuild_requests as child
    join util.dataset_flow_identity_process_ledger as ledger
      on ledger.scope_id = p_scope_id
      and ledger.ordinal = 1
      and child.batch_id = ledger.derivative_batch_id;
    v_during := pg_temp.flow_identity_business_state(p_scope_id);
    raise exception using errcode = 'P7002',
      message = 'FLOW_IDENTITY_TEST_ORPHAN_DERIVATIVE_ROLLBACK';
  exception when sqlstate 'P7002' then
    null;
  end;
  v_after := pg_temp.flow_identity_business_state(p_scope_id);
  return jsonb_build_object(
    'orphan_causal_child_captured', v_before <> v_during,
    'probe_rolled_back_exactly', v_before = v_after
  );
end;
$$;

create or replace function pg_temp.flow_identity_cancel_request(
  p_request_id uuid,
  p_reason text
) returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'schema_version', 'dataset-flow-identity-scope-cancel.v2',
    'request_id', p_request_id,
    'receipt_id', state.value->>'receipt_id',
    'receipt_proof_sha256', state.value->>'receipt_proof_sha256',
    'operation_id', state.value->>'operation_id',
    'plan_sha256', state.value->>'plan_sha256',
    'scope_proof_sha256', state.value->>'scope_proof_sha256',
    'reason', p_reason,
    'evidence_sha256', repeat('3', 64)
  )
  from flow_identity_state as state
  where state.key = 'preflight'
$$;

create or replace function pg_temp.flow_identity_bad_capture()
returns jsonb
language sql
stable
as $$
  select jsonb_set(
    pg_temp.flow_identity_capture() || jsonb_build_object(
      'request_id', 'fb000000-0000-4000-8000-000000000099',
      'operation_id', 'flow-identity-bad-later-template'
    ),
    '{process_intents,0,rewrites,0,internal_id}', '"999"'::jsonb, false
  )
$$;

select has_function(
    'api', 'cmd_dataset_flow_identity_scope_preflight_guarded',
    array['jsonb'],
  'scope preflight RPC exists'
);
select has_function(
    'api', 'cmd_dataset_flow_identity_process_rewrite_guarded',
    array['uuid', 'jsonb', 'jsonb'],
  'one-process rewrite RPC exists'
);
select has_function(
  'api', 'cmd_dataset_flow_identity_scope_read', array['uuid'],
  'scope read RPC exists'
);
select has_function(
    'api', 'cmd_dataset_flow_identity_scope_finalize_guarded',
    array['uuid', 'jsonb', 'jsonb'],
  'scope finalize RPC exists'
);
select has_function(
    'api', 'cmd_dataset_flow_identity_scope_recover_guarded',
    array['uuid', 'jsonb'],
  'fresh approved recovery RPC exists'
);
select has_function(
    'api', 'cmd_dataset_flow_identity_scope_lookup', array['jsonb'],
  'read-only lost-response scope lookup RPC exists'
);
select has_function(
    'api', 'cmd_dataset_flow_identity_scope_cancel_guarded',
    array['uuid', 'jsonb'],
  'zero-write scope cancel RPC exists'
);
select has_function(
    'api', 'cmd_dataset_flow_identity_capture_attest_guarded',
    array['jsonb'],
  'v2 database capture/attestation RPC exists'
);
select function_privs_are(
  'api', 'cmd_dataset_flow_identity_scope_preflight_guarded',
  array['jsonb'], 'authenticated', array['EXECUTE'],
  'preflight is authenticated-only'
);
select function_privs_are(
  'api', 'cmd_dataset_flow_identity_process_rewrite_guarded',
  array['uuid', 'jsonb', 'jsonb'], 'authenticated', array['EXECUTE'],
  'process mutation is authenticated-only'
);
select function_privs_are(
  'api', 'cmd_dataset_flow_identity_scope_read',
  array['uuid'], 'authenticated', array['EXECUTE'],
  'scope read is authenticated-only'
);
select function_privs_are(
  'api', 'cmd_dataset_flow_identity_scope_finalize_guarded',
  array['uuid', 'jsonb', 'jsonb'], 'authenticated', array['EXECUTE'],
  'finalize is authenticated-only'
);
select function_privs_are(
  'api', 'cmd_dataset_flow_identity_scope_recover_guarded',
  array['uuid', 'jsonb'], 'authenticated', array['EXECUTE'],
  'recovery admission is authenticated-only'
);
select function_privs_are(
  'api', 'cmd_dataset_flow_identity_scope_lookup',
  array['jsonb'], 'authenticated', array['EXECUTE'],
  'scope lookup is authenticated-only'
);
select function_privs_are(
  'api', 'cmd_dataset_flow_identity_scope_cancel_guarded',
  array['uuid', 'jsonb'], 'authenticated', array['EXECUTE'],
  'zero-write cancel is authenticated-only'
);
select function_privs_are(
  'api', 'cmd_dataset_flow_identity_capture_attest_guarded',
  array['jsonb'], 'authenticated', array['EXECUTE'],
  'capture attestation is authenticated-only'
);
select is(
  util.dataset_flow_identity_sha256(
    '{"z":"天工","a":[1,1.0,-0.0,0.000001,100000000000000000000],"é":"值","😀":"emoji"}'::jsonb
  ),
  '9335d798454451154be24dc993efb6730888061d4b0a87e288c6e4df75af93df',
  'canonical hash has a fixed CLI-independent Unicode/numeric golden vector'
);
select is(
  util.dataset_flow_identity_source_universe(
    pg_temp.flow_identity_id('owner'),
    pg_temp.flow_identity_source_universe(),
    util.dataset_flow_identity_sha256(pg_temp.flow_identity_source_universe())
  )->>'ok',
  'true',
  'source universe proves the exact live 305-row owner-draft elementary set'
);
select is(
  util.dataset_flow_identity_source_universe(
    pg_temp.flow_identity_id('owner'),
    pg_temp.flow_identity_source_universe() - 304,
    util.dataset_flow_identity_sha256(pg_temp.flow_identity_source_universe() - 304)
  )->>'ok',
  'false',
  'source universe rejects one omitted row'
);
select is(
  util.dataset_flow_identity_source_universe(
    pg_temp.flow_identity_id('owner'),
    (pg_temp.flow_identity_source_universe() - 304)
      || jsonb_build_array(pg_temp.flow_identity_source_universe()->0),
    util.dataset_flow_identity_sha256(
      (pg_temp.flow_identity_source_universe() - 304)
        || jsonb_build_array(pg_temp.flow_identity_source_universe()->0)
    )
  )->>'ok',
  'false',
  'source universe rejects a duplicate that preserves cardinality'
);
select is(
  util.dataset_flow_identity_source_universe(
    pg_temp.flow_identity_id('owner'),
    jsonb_set(
      pg_temp.flow_identity_source_universe(), '{304,id}',
      '"ffffffff-ffff-4fff-8fff-ffffffffffff"'::jsonb, false
    ),
    util.dataset_flow_identity_sha256(jsonb_set(
      pg_temp.flow_identity_source_universe(), '{304,id}',
      '"ffffffff-ffff-4fff-8fff-ffffffffffff"'::jsonb, false
    ))
  )->>'ok',
  'false',
  'source universe rejects a phantom identity that preserves cardinality'
);
select is(
  util.dataset_flow_identity_validate_support_set(
    pg_temp.flow_identity_id('owner'),
    pg_temp.flow_identity_support_snapshots(),
    util.dataset_flow_identity_sha256(pg_temp.flow_identity_support_snapshots())
  )->>'ok',
  'true',
  'full FP/UG support snapshot set reproves owner/state/time/payload/row hashes'
);
select is(
  util.dataset_flow_identity_validate_flow_guard(
    pg_temp.flow_identity_id('owner'),
    jsonb_set(pg_temp.flow_guard(true), '{reference,@uri}',
      to_jsonb('../flows/' || pg_temp.flow_identity_id('target_flow')::text
        || '_01.00.000.json'), false),
    true, pg_temp.flow_identity_support_snapshots()
  )->>'ok',
  'false',
  'target guard rejects a non-canonical .json URI'
);
select is(
  util.dataset_flow_identity_validate_flow_guard(
    pg_temp.flow_identity_id('owner'),
    jsonb_set(pg_temp.flow_guard(true), '{reference,@refObjectId}',
      to_jsonb(pg_temp.flow_identity_id('source_flow')::text), false),
    true, pg_temp.flow_identity_support_snapshots()
  )->>'ok',
  'false',
  'target guard rejects a reference with the wrong target id'
);
select is(
  util.dataset_flow_identity_validate_flow_guard(
    pg_temp.flow_identity_id('owner'),
    jsonb_set(pg_temp.flow_guard(true), '{reference,@version}',
      '"02.00.000"'::jsonb, false),
    true, pg_temp.flow_identity_support_snapshots()
  )->>'ok',
  'false',
  'target guard rejects a reference with the wrong target version'
);
select is(
  util.dataset_flow_identity_protected_closure(
    pg_temp.flow_identity_id('owner'),
    jsonb_set(
      jsonb_set(
        pg_temp.flow_identity_protected_closure(), '{orphans,0,source_id}',
        to_jsonb(pg_temp.flow_identity_id('source_flow')::text), false
      ),
      '{orphan_set_sha256}',
      to_jsonb(util.dataset_flow_identity_sha256(
        jsonb_set(
          pg_temp.flow_identity_protected_closure()->'orphans',
          '{0,source_id}',
          to_jsonb(pg_temp.flow_identity_id('source_flow')::text), false
        )
      )), false
    )
  )->>'ok',
  'false',
  'an alleged orphan with a live process reference is rejected'
);
select ok(
  pg_get_functiondef(
    'private.dataset_flow_identity_whole_scope_proof_v2(uuid,uuid,uuid,boolean)'::regprocedure
  ) like '%read_dataset_flow_identity_derivative_set%',
  'whole-scope verifier uses one set-based derivative proof'
);
select ok(
  pg_get_functiondef(
    'api.cmd_dataset_flow_identity_scope_finalize_guarded(uuid,jsonb,jsonb)'::regprocedure
  ) not like '%read_dataset_derivative_rebuild_batch_any%',
  'installed finalize contains no per-child derivative reader'
);
select ok(
  pg_get_functiondef(
    'api.cmd_dataset_flow_identity_scope_preflight_guarded(jsonb)'::regprocedure
  ) not ilike '%lock table%',
  'preflight takes no table-level SHARE locks'
);
select is(
  private.dataset_flow_identity_collision_ledger(
    private.dataset_flow_identity_exchanges(
      pg_temp.flow_identity_process_payload(true)
    ),
    pg_temp.flow_identity_rewrites()
  ) #> '{entries,0,mapping_ids}',
  jsonb_build_array(
    pg_temp.flow_identity_mapping()->>'mapping_id', null
  ),
  'collision ledger uses mapping id for rewritten row and JSON null for existing target row'
);
select is(
  util.dataset_flow_identity_protected_closure(
    pg_temp.flow_identity_id('owner'),
    pg_temp.flow_identity_protected_closure()
  )->>'ok',
  'true',
  'protected closure proves exact process/index/internal-id/direction occurrence'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub', pg_temp.flow_identity_id('owner')::text, true
);
select set_config(
  'request.jwt.claim.email', 'flow-owner@example.com', true
);

select is(
  api.cmd_dataset_flow_identity_capture_attest_guarded(
    pg_temp.flow_identity_bad_capture()
  )->>'code',
  'FLOW_IDENTITY_CAPTURE_FAILED',
  'a bad semantic process intent fails during DB-owned capture materialization'
);
select is(
  (select count(*)::integer
   from util.dataset_flow_identity_capture_receipts
   where operation_id = 'flow-identity-bad-later-template'),
  0,
  'bad semantic intent causes zero durable receipt or primary writes'
);

insert into flow_identity_state(key, value)
select 'capture', api.cmd_dataset_flow_identity_capture_attest_guarded(
  pg_temp.flow_identity_capture()
);
select is(
  (select value->>'ok' from flow_identity_state where key = 'capture'),
  'true',
  'fresh semantic capture returns a DB-owned immutable receipt'
);
select is(
  api.cmd_dataset_flow_identity_capture_attest_guarded(
    pg_temp.flow_identity_capture()
  )->>'replay',
  'true',
  'exact capture replay returns the same immutable receipt'
);

insert into flow_identity_state(key, value)
select 'preflight',
  api.cmd_dataset_flow_identity_scope_preflight_guarded(
    pg_temp.flow_identity_preflight()
  );

select is(
  (select value->>'ok' from flow_identity_state where key = 'preflight'),
  'true',
  'fresh exact scope preflight succeeds'
);
select is(
  (select value->>'status' from flow_identity_state where key = 'preflight'),
  'sealed',
  'preflight returns sealed status'
);
select is(
  (select value->>'receipt_id' from flow_identity_state where key = 'preflight'),
  (select value->>'receipt_id' from flow_identity_state where key = 'capture'),
  'sealed scope response exactly binds the DB capture receipt'
);
insert into flow_identity_state(key, value)
select 'lookup_before', pg_temp.flow_identity_private_counts();
insert into flow_identity_state(key, value)
select 'lookup_result',
  api.cmd_dataset_flow_identity_scope_lookup(pg_temp.flow_identity_lookup());
insert into flow_identity_state(key, value)
select 'lookup_after', pg_temp.flow_identity_private_counts();
select is(
  (select jsonb_build_object(
    'ok', value->>'ok',
    'read_only', value->>'read_only',
    'scope_id', value->>'scope_id',
    'scope_proof_sha256', value->>'scope_proof_sha256',
    'permit_is_null', value->'execution_permit' = 'null'::jsonb
  ) from flow_identity_state where key = 'lookup_result'),
  (select jsonb_build_object(
    'ok', 'true', 'read_only', 'true',
    'scope_id', value->>'scope_id',
    'scope_proof_sha256', value->>'scope_proof_sha256',
    'permit_is_null', true
  ) from flow_identity_state where key = 'preflight'),
  'exact scope lookup recovers sanitized preflight proof without a permit'
);
select is(
  (select value from flow_identity_state where key = 'lookup_after'),
  (select value from flow_identity_state where key = 'lookup_before'),
  'scope lookup changes no scope, invocation, or audit row count'
);
select is(
  api.cmd_dataset_flow_identity_scope_lookup(jsonb_set(
    pg_temp.flow_identity_lookup(),
    '{freeze_sha256}', to_jsonb(repeat('0', 64)), false
  ))->>'code',
  'FLOW_IDENTITY_SCOPE_LOOKUP_NOT_FOUND',
  'one-field lookup mismatch returns the same non-leaking not-found result'
);
select is(
  (select jsonb_build_object(
    'replay', replay.value->>'replay',
    'permit_is_null', replay.value->'execution_permit' = 'null'::jsonb
  )
  from api.cmd_dataset_flow_identity_scope_preflight_guarded(
    pg_temp.flow_identity_preflight()
  ) as replay(value)),
  jsonb_build_object('replay', 'true', 'permit_is_null', true),
  'exact preflight replay is proof-only and cannot mint a second permit'
);
select is(
  api.cmd_dataset_flow_identity_scope_preflight_guarded(
    jsonb_set(
      pg_temp.flow_identity_preflight(),
      '{freeze_sha256}', to_jsonb(repeat('0', 64)), false
    )
  )->>'code',
  'FLOW_IDENTITY_PREFLIGHT_OPERATION_REUSE_MISMATCH',
  'tampered sealed artifact fails closed before scope reuse'
);
select is(
  (select jsonb_build_object(
    'derivative_batch_id_is_null',
      result #> '{processes,0,derivative_batch_id}' = 'null'::jsonb,
    'derivative_request_id_is_null',
      result #> '{processes,0,derivative_request_id}' = 'null'::jsonb,
    'derivative_status_is_null',
      result #> '{processes,0,derivative_status}' = 'null'::jsonb
  )
  from api.cmd_dataset_flow_identity_scope_read(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight')
  ) as result),
  jsonb_build_object(
    'derivative_batch_id_is_null', true,
    'derivative_request_id_is_null', true,
    'derivative_status_is_null', true
  ),
  'sealed pending process has exact NULL derivative batch/request/status fields'
);

insert into flow_identity_state(key, value)
select 'cancel_request', pg_temp.flow_identity_cancel_request(
  'fa000000-0000-4000-8000-000000000010'::uuid,
  'abandon untouched test scope'
);
insert into flow_identity_state(key, value)
select 'cancel_result',
  api.cmd_dataset_flow_identity_scope_cancel_guarded(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight'),
    (select value from flow_identity_state where key = 'cancel_request')
  );
select is(
  (select value->>'status' from flow_identity_state where key = 'cancel_result'),
  'cancelled',
  'an untouched sealed scope can be cancelled without a primary write'
);
select is(
  (
    select jsonb_build_object(
      'replay', replay.value->>'replay',
      'audit_count', (
        select count(*)::integer
        from private.command_audit_log as audit
        where audit.command = 'cmd_dataset_flow_identity_scope_cancel_guarded'
          and audit.payload->>'scope_id' = preflight.value->>'scope_id'
      )
    )
    from flow_identity_state as preflight
    cross join lateral api.cmd_dataset_flow_identity_scope_cancel_guarded(
      (preflight.value->>'scope_id')::uuid,
      (select value from flow_identity_state where key = 'cancel_request')
    ) as replay(value)
    where preflight.key = 'preflight'
  ),
  jsonb_build_object('replay', 'true', 'audit_count', 1),
  'exact cancel replay is read-only and retains one authoritative audit'
);
select is(
  api.cmd_dataset_flow_identity_scope_cancel_guarded(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight'),
    jsonb_set(
      (select value from flow_identity_state where key = 'cancel_request'),
      '{reason}', '"different abandon reason"'::jsonb, false
    )
  )->>'code',
  'FLOW_IDENTITY_CANCEL_REPLAY_MISMATCH',
  'a cancelled scope rejects a different request instead of writing again'
);
reset role;
select lives_ok(
  $$update public.processes
      set json_ordered = json_ordered
    where id = pg_temp.flow_identity_id('process')
      and version = '01.00.000'$$,
  'zero-write cancel releases the owner process fence'
);
set local role authenticated;

update flow_identity_state
set value = api.cmd_dataset_flow_identity_capture_attest_guarded(
  pg_temp.flow_identity_capture() || jsonb_build_object(
    'request_id', 'fb000000-0000-4000-8000-000000000011',
    'operation_id', 'flow-identity-test-operation-after-cancel'
  )
)
where key = 'capture';
select is(
  api.cmd_dataset_flow_identity_scope_preflight_guarded(
    pg_temp.flow_identity_preflight() || jsonb_build_object(
      'request_id', 'fa000000-0000-4000-8000-000000000011',
      'operation_id', 'flow-identity-test-operation-after-cancel',
      'plan_sha256', repeat('2', 64),
      'execution_approval_request_sha256', repeat('c', 64),
      'execution_approval_text_sha256', repeat('3', 64),
      'execution_approval_identity_sha256', repeat('4', 64)
    )
  )->>'code',
  'FLOW_IDENTITY_PREFLIGHT_APPROVAL_REUSE_MISMATCH',
  'fresh preflight rejects historical approval hash reuse across domains'
);
insert into flow_identity_state(key, value)
select 'preflight_request_2',
  pg_temp.flow_identity_preflight() || jsonb_build_object(
    'request_id', 'fa000000-0000-4000-8000-000000000011',
    'operation_id', 'flow-identity-test-operation-after-cancel',
    'plan_sha256', repeat('2', 64),
    'execution_approval_request_sha256', repeat('1', 64),
    'execution_approval_text_sha256', repeat('3', 64),
    'execution_approval_identity_sha256', repeat('4', 64)
  );
update flow_identity_state
set value = api.cmd_dataset_flow_identity_scope_preflight_guarded(
  (select value from flow_identity_state where key = 'preflight_request_2')
)
where key = 'preflight';
select is(
  (select jsonb_build_object(
    'capture_ok', capture.value->>'ok',
    'preflight_status', preflight.value->>'status'
  )
  from flow_identity_state as capture
  cross join flow_identity_state as preflight
  where capture.key = 'capture' and preflight.key = 'preflight'),
  jsonb_build_object('capture_ok', 'true', 'preflight_status', 'sealed'),
  'a fresh receipt and plan can seal after zero-write cancellation'
);

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

insert into flow_identity_state(key, value)
select 'process_request_2', request || jsonb_build_object(
  'process_request_sha256',
    util.dataset_flow_identity_restricted_sha256_v2(request)
)
from (
  select jsonb_build_object(
    'schema_version', 'dataset-flow-identity-process-rewrite.v2',
    'request_id', 'fa000000-0000-4000-8000-000000000004',
    'scope_proof_sha256', preflight.value->>'scope_proof_sha256',
    'ordinal', 2,
    'process_intent_proof_sha256', ledger.process_intent_proof_sha256
  ) as request
  from flow_identity_state as preflight
  join util.dataset_flow_identity_process_ledger as ledger
    on ledger.scope_id = (preflight.value->>'scope_id')::uuid
    and ledger.ordinal = 2
  where preflight.key = 'preflight'
) as prepared;

select is(
  (select (value #>> '{execution_permit,generation}')::integer
   from flow_identity_state where key = 'preflight'),
  0,
  'fresh preflight starts the one-wrapper permit at generation zero'
);

-- This fixture is transaction-local, so the second connection cannot see its
-- uncommitted rows.  It can still own the exact scope advisory lock and prove
-- that a concurrent same-scope process call fails before touching the permit,
-- ledger, primary JSON, audit, or derivative child.
reset role;
select extensions.dblink_connect(
  'flow_identity_scope_lock',
  'host=db port=5432 dbname=' || current_database()
    || ' user=postgres password=postgres'
);
select extensions.dblink_exec('flow_identity_scope_lock', 'begin');
select extensions.dblink_exec(
  'flow_identity_scope_lock',
  format(
    'do $lock$ begin perform pg_advisory_xact_lock(hashtextextended(%L, 0)); end $lock$',
    'dataset-flow-identity:' || (
      select value->>'scope_id'
      from flow_identity_state where key = 'preflight'
    )
  )
);
set local role authenticated;
select is(
  api.cmd_dataset_flow_identity_process_rewrite_guarded(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight'),
    (select value from flow_identity_state where key = 'process_request'),
    (select value->'execution_permit'
      from flow_identity_state where key = 'preflight')
  )->>'code',
  'FLOW_IDENTITY_PROCESS_SCOPE_BUSY',
  'a real second connection serializes a concurrent same-scope process call'
);
select is(
  pg_temp.flow_identity_invocation((
    select (value #>> '{execution_permit,invocation_id}')::uuid
    from flow_identity_state where key = 'preflight'
  ))->>'generation',
  '0',
  'scope-lock rejection does not consume or rotate the live permit'
);
reset role;
select extensions.dblink_exec('flow_identity_scope_lock', 'rollback');
select extensions.dblink_disconnect('flow_identity_scope_lock');
set local role authenticated;

select is(
  api.cmd_dataset_flow_identity_process_rewrite_guarded(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight'),
    (select value from flow_identity_state where key = 'process_request'),
    jsonb_set(
      (select value->'execution_permit'
       from flow_identity_state where key = 'preflight'),
      '{generation}', '0.5'::jsonb, false
    )
  )->>'code',
  'FLOW_IDENTITY_WRAPPER_PERMIT_REQUIRED',
  'fractional permit generation is rejected without consuming the live permit'
);
select is(
  pg_temp.flow_identity_invocation((
    select (value #>> '{execution_permit,invocation_id}')::uuid
    from flow_identity_state where key = 'preflight'
  ))->>'generation',
  '0',
  'malformed authorization leaves generation zero available for the wrapper'
);

insert into flow_identity_state(key, value)
select 'process_drift_' || probe.kind,
  pg_temp.flow_identity_drift_probe(
    'process', probe.kind,
    (select value->'execution_permit'
      from flow_identity_state where key = 'preflight')
  )
from unnest(array[
  'process', 'source', 'target', 'flowproperty', 'unitgroup', 'occurrence'
]) with ordinality as probe(kind, ordinal);

select is(
  jsonb_build_object(
    'code', state.value #>> '{result,code}',
    'business_unchanged_during_rejection',
      (state.value->>'business_unchanged_during_rejection')::boolean,
    'probe_rolled_back_exactly',
      (state.value->>'probe_rolled_back_exactly')::boolean
  ),
  jsonb_build_object(
    'code', case split_part(state.key, 'process_drift_', 2)
      when 'process' then 'FLOW_IDENTITY_PROCESS_BASELINE_DRIFT'
      when 'occurrence' then 'FLOW_IDENTITY_PROCESS_BASELINE_DRIFT'
      else 'FLOW_IDENTITY_PROCESS_MAPPING_DRIFT' end,
    'business_unchanged_during_rejection', true,
    'probe_rolled_back_exactly', true
  ),
  split_part(state.key, 'process_drift_', 2)
    || ' drift fails closed before a process transaction and writes no business state'
)
from flow_identity_state as state
where state.key like 'process_drift_%'
order by state.key;

insert into flow_identity_state(key, value)
select 'post_primary_fault_before', pg_temp.flow_identity_atomic_state(
  (preflight.value->>'scope_id')::uuid,
  (preflight.value #>> '{execution_permit,invocation_id}')::uuid
)
from flow_identity_state as preflight
where preflight.key = 'preflight';

reset role;
create trigger dataset_flow_identity_test_post_primary_fault
before update on private.command_audit_log
for each row execute function pg_temp.flow_identity_post_primary_fault();
set local role authenticated;

select throws_ok(
  $$select api.cmd_dataset_flow_identity_process_rewrite_guarded(
      (select (value->>'scope_id')::uuid
        from flow_identity_state where key = 'preflight'),
      (select value from flow_identity_state where key = 'process_request'),
      (select value->'execution_permit'
        from flow_identity_state where key = 'preflight')
    )$$,
  'P0001',
  'FLOW_IDENTITY_TEST_POST_PRIMARY_FAULT',
  'a post-primary audit-promotion fault aborts the whole guarded RPC'
);
select is(
  pg_temp.flow_identity_atomic_state(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight'),
    (select (value #>> '{execution_permit,invocation_id}')::uuid
      from flow_identity_state where key = 'preflight')
  ),
  (select value from flow_identity_state
    where key = 'post_primary_fault_before'),
  'post-primary fault rolls back process JSON, ledger, audit, derivative child, permit, scope, and active fence'
);

reset role;
drop trigger dataset_flow_identity_test_post_primary_fault
  on private.command_audit_log;
set local role authenticated;

insert into flow_identity_state(key, value)
select 'process_result',
  api.cmd_dataset_flow_identity_process_rewrite_guarded(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight'),
    value,
    (select value->'execution_permit'
      from flow_identity_state where key = 'preflight')
  )
from flow_identity_state where key = 'process_request';

select is(
  (select value->>'ok' from flow_identity_state where key = 'process_result'),
  'true',
  'one-process guarded rewrite succeeds'
);
select is(
  (select value->>'replay' from flow_identity_state where key = 'process_result'),
  'false',
  'first one-process call is not a replay'
);
select is(
  (select value->>'completed_process_count'
   from flow_identity_state where key = 'process_result'),
  '1',
  'process success returns the exact post-commit completed count'
);
select is(
  (select jsonb_build_object(
    'permit_generation_before', result.value->>'permit_generation_before',
    'returned_generation', result.value #>> '{execution_permit,generation}',
    'same_invocation', result.value->>'invocation_id' =
      preflight.value #>> '{execution_permit,invocation_id}',
    'token_changed', result.value #>> '{execution_permit,token}' <>
      preflight.value #>> '{execution_permit,token}',
    'stored_generation', invocation.value->>'generation',
    'stored_hash_matches', invocation.value->>'token_sha256' =
      pg_catalog.encode(extensions.digest(pg_catalog.convert_to(
        result.value #>> '{execution_permit,token}', 'UTF8'
      ), 'sha256'), 'hex')
  )
  from flow_identity_state as result
  join flow_identity_state as preflight on preflight.key = 'preflight'
  cross join lateral pg_temp.flow_identity_invocation(
    (result.value->>'invocation_id')::uuid
  ) as invocation(value)
  where result.key = 'process_result'),
  jsonb_build_object(
    'permit_generation_before', '0',
    'returned_generation', '1',
    'same_invocation', true,
    'token_changed', true,
    'stored_generation', '1',
    'stored_hash_matches', true
  ),
  'ordinal one atomically rotates generation zero to one and persists only its token hash'
);
select is(
  (select json #>>
    '{processDataSet,exchanges,exchange,0,referenceToFlowDataSet,@refObjectId}'
    from public.processes
    where id = pg_temp.flow_identity_id('process')),
  pg_temp.flow_identity_id('target_flow')::text,
  'approved source reference is rewritten to exact public identity'
);
select is(
  (select json #>> '{processDataSet,exchanges,exchange,0,meanAmount}'
    from public.processes
    where id = pg_temp.flow_identity_id('process')),
  '5',
  'amount remains byte-semantically unchanged'
);
select is(
  (select json #>> '{processDataSet,exchanges,exchange,0,generalComment,#text}'
    from public.processes
    where id = pg_temp.flow_identity_id('process')),
  'preserve me',
  'comment remains unchanged'
);
select is(
  (select json #>>
    '{processDataSet,exchanges,exchange,2,referenceToFlowDataSet,@refObjectId}'
    from public.processes
    where id = pg_temp.flow_identity_id('process')),
  pg_temp.flow_identity_id('pending_flow')::text,
  'pending reference remains unchanged'
);
select is(
  (select jsonb_array_length(json #> '{processDataSet,exchanges,exchange}')
    from public.processes
    where id = pg_temp.flow_identity_id('process')),
  3,
  'exchange count and converged rows are preserved'
);
select is(
  (select count(*)::integer from private.command_audit_log
    where command = 'cmd_dataset_flow_identity_process_rewrite_guarded'
      and target_id = pg_temp.flow_identity_id('process')),
  1,
  'one unique primary audit is recorded'
);
select is(
  (select count(*)::integer
    from util.dataset_derivative_rebuild_requests as child
    where child.batch_id = (
      select (value->>'derivative_batch_id')::uuid
      from flow_identity_state where key = 'process_result'
    )),
  1,
  'one protected derivative child is admitted atomically'
);
select is(
  api.cmd_dataset_flow_identity_scope_cancel_guarded(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight'),
    pg_temp.flow_identity_cancel_request(
      'fa000000-0000-4000-8000-000000000012'::uuid,
      'must not abandon after primary commit'
    )
  )->>'code',
  'FLOW_IDENTITY_CANCEL_REQUIRES_ZERO_WRITE_SEAL',
  'cancel rejects a scope after its first primary transaction commits'
);
select is(
  (select jsonb_build_object(
    'scope_status', scope.status,
    'ledger_status', ledger.status,
    'ledger_active', ledger.active,
    'primary_audit_count', (
      select count(*)::integer from private.command_audit_log as audit
      where audit.command = 'cmd_dataset_flow_identity_process_rewrite_guarded'
        and audit.payload->>'scope_id' = scope.id::text
    )
  )
  from util.dataset_flow_identity_scopes as scope
  join util.dataset_flow_identity_process_ledger as ledger
    on ledger.scope_id = scope.id and ledger.ordinal = 1
  where scope.id = (
    select (value->>'scope_id')::uuid
    from flow_identity_state where key = 'preflight'
  )),
  jsonb_build_object(
    'scope_status', 'running',
    'ledger_status', 'completed',
    'ledger_active', true,
    'primary_audit_count', 1
  ),
  'rejected post-primary cancel preserves scope, ledger, fence, and audit proof'
);
select is(
  util.read_dataset_derivative_rebuild_batch_any(
    pg_temp.flow_identity_id('owner'),
    (select (value->>'derivative_batch_id')::uuid
      from flow_identity_state where key = 'process_result')
  )->>'target_count',
  '1',
  'dynamic derivative reader accepts a one-target Step 3 batch'
);
select is(
  api.cmd_dataset_flow_identity_process_rewrite_guarded(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight'),
    (select value from flow_identity_state where key = 'process_request_2'),
    (select value->'execution_permit'
      from flow_identity_state where key = 'preflight')
  )->>'code',
  'FLOW_IDENTITY_WRAPPER_PERMIT_REQUIRED',
  'ordinal two rejects the stale generation-zero permit after ordinal one commits'
);
select is(
  (select jsonb_build_object(
    'invocation_generation', invocation.value->>'generation',
    'successful_process_posts', invocation.value->>'successful_process_posts',
    'ordinal_two_status', ledger.status,
    'ordinal_two_audit_is_null', ledger.audit_id is null
  )
  from flow_identity_state as preflight
  cross join lateral pg_temp.flow_identity_invocation(
    (preflight.value #>> '{execution_permit,invocation_id}')::uuid
  ) as invocation(value)
  join util.dataset_flow_identity_process_ledger as ledger
    on ledger.scope_id = (preflight.value->>'scope_id')::uuid
    and ledger.ordinal = 2
  where preflight.key = 'preflight'),
  jsonb_build_object(
    'invocation_generation', '1',
    'successful_process_posts', '1',
    'ordinal_two_status', 'pending',
    'ordinal_two_audit_is_null', true
  ),
  'stale permit rejection leaves ordinal two and generation one unchanged'
);

insert into flow_identity_state(key, value)
select 'process_result_2',
  api.cmd_dataset_flow_identity_process_rewrite_guarded(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight'),
    value,
    (select value->'execution_permit'
      from flow_identity_state where key = 'process_result')
  )
from flow_identity_state where key = 'process_request_2';
select is(
  (select jsonb_build_object(
    'ok', second.value->>'ok',
    'completed_process_count', second.value->>'completed_process_count',
    'next_ordinal_is_null', second.value->'next_ordinal' = 'null'::jsonb,
    'primary_complete', second.value->>'primary_complete',
    'permit_generation_before', second.value->>'permit_generation_before',
    'returned_generation', second.value #>> '{execution_permit,generation}',
    'token_changed', second.value #>> '{execution_permit,token}' <>
      first.value #>> '{execution_permit,token}',
    'stored_generation', invocation.value->>'generation',
    'stored_process_posts', invocation.value->>'successful_process_posts',
    'stored_hash_matches', invocation.value->>'token_sha256' =
      pg_catalog.encode(extensions.digest(pg_catalog.convert_to(
        second.value #>> '{execution_permit,token}', 'UTF8'
      ), 'sha256'), 'hex')
  )
  from flow_identity_state as second
  join flow_identity_state as first on first.key = 'process_result'
  cross join lateral pg_temp.flow_identity_invocation(
    (second.value->>'invocation_id')::uuid
  ) as invocation(value)
  where second.key = 'process_result_2'),
  jsonb_build_object(
    'ok', 'true',
    'completed_process_count', '2',
    'next_ordinal_is_null', true,
    'primary_complete', 'true',
    'permit_generation_before', '1',
    'returned_generation', '2',
    'token_changed', true,
    'stored_generation', '2',
    'stored_process_posts', '2',
    'stored_hash_matches', true
  ),
  'ordinal two atomically rotates generation one to two on the same invocation'
);
select is(
  (select json #>>
    '{processDataSet,exchanges,exchange,0,referenceToFlowDataSet,@refObjectId}'
   from public.processes
   where id = pg_temp.flow_identity_id('process_2')),
  pg_temp.flow_identity_id('target_flow')::text,
  'ordinal two rewrites its exact owner-draft process reference'
);
select is(
  api.cmd_dataset_flow_identity_process_rewrite_guarded(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight'),
    (select value from flow_identity_state where key = 'process_request_2'),
    (select value->'execution_permit'
      from flow_identity_state where key = 'process_result')
  )->>'code',
  'FLOW_IDENTITY_WRAPPER_PERMIT_REQUIRED',
  'ordinal two rejects its stale generation-one permit after rotation'
);
select is(
  api.cmd_dataset_flow_identity_process_rewrite_guarded(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight'),
    (select value from flow_identity_state where key = 'process_request_2'),
    (select value->'execution_permit'
      from flow_identity_state where key = 'process_result_2')
  )->>'code',
  'FLOW_IDENTITY_WRAPPER_PERMIT_REQUIRED',
  'current generation-two permit has no process capacity after two approved posts'
);
select is(
  pg_temp.flow_identity_invocation((
    select (value #>> '{execution_permit,invocation_id}')::uuid
    from flow_identity_state where key = 'process_result_2'
  ))->>'status',
  'active',
  'an exhausted process permit remains non-process-capable until recovery supersedes it'
);
select is(
  (select count(*)::integer
   from private.command_audit_log as audit
   where audit.command = 'cmd_dataset_flow_identity_process_rewrite_guarded'
     and audit.payload->>'scope_id' = (
       select value->>'scope_id'
       from flow_identity_state where key = 'preflight'
     )),
  2,
  'two ordered process transactions produce exactly two primary audits'
);
select is(
  (select count(*)::integer
   from util.dataset_derivative_rebuild_requests as child
   join util.dataset_flow_identity_process_ledger as ledger
     on child.batch_id = ledger.derivative_batch_id
   where ledger.scope_id = (
     select (value->>'scope_id')::uuid
     from flow_identity_state where key = 'preflight'
   )),
  2,
  'two ordered process transactions admit exactly two causal derivative children'
);
select is(
  pg_temp.flow_identity_orphan_derivative_probe((
    select (value->>'scope_id')::uuid
    from flow_identity_state where key = 'preflight'
  )),
  jsonb_build_object(
    'orphan_causal_child_captured', true,
    'probe_rolled_back_exactly', true
  ),
  'atomic snapshot includes a same-actor/reason/target orphan causal child without a ledger batch link'
);
select is(
  (select count(*)::integer from private.command_audit_log
    where command = 'cmd_dataset_flow_identity_process_rewrite_guarded'
      and target_id = pg_temp.flow_identity_id('process')),
  1,
  'exact replay does not create a second audit or write'
);
select is(
  api.cmd_dataset_flow_identity_scope_read(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight')
  )->>'status',
  'derivatives_pending',
  'scope read resumes from durable derivative-pending state'
);
select is(
  api.cmd_dataset_flow_identity_scope_read(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight')
  )->>'protected_closure_current',
  'true',
  'scope read reproves protected occurrence closure'
);

insert into flow_identity_state(key, value)
select 'finalize_request', jsonb_build_object(
  'schema_version', 'dataset-flow-identity-scope-finalize.v2',
  'request_id', 'fa000000-0000-4000-8000-000000000003',
  'scope_proof_sha256', preflight.value->>'scope_proof_sha256',
  'expected', jsonb_build_object(
    'process_count', 2,
    'rewrite_count', 2,
    'completed_process_count', 2
  )
)
from flow_identity_state as preflight
where preflight.key = 'preflight'
;

insert into flow_identity_state(key, value)
select 'finalize_drift_' || probe.kind,
  pg_temp.flow_identity_drift_probe(
    'finalize', probe.kind,
    (select value->'execution_permit'
      from flow_identity_state where key = 'process_result_2')
  )
from unnest(array[
  'process', 'source', 'target', 'flowproperty', 'unitgroup', 'occurrence'
]) with ordinality as probe(kind, ordinal);

select is(
  jsonb_build_object(
    'code', state.value #>> '{result,code}',
    'guard_current', case split_part(state.key, 'finalize_drift_', 2)
      when 'process' then
        (state.value #>> '{result,whole_scope_proof,primary_current}')::boolean
      when 'source' then
        (state.value #>>
          '{result,whole_scope_proof,source_guards_current}')::boolean
      when 'target' then
        (state.value #>>
          '{result,whole_scope_proof,target_guards_current}')::boolean
      when 'flowproperty' then
        (state.value #>>
          '{result,whole_scope_proof,support_guards_current}')::boolean
      when 'unitgroup' then
        (state.value #>>
          '{result,whole_scope_proof,support_guards_current}')::boolean
      when 'occurrence' then
        (state.value #>>
          '{result,whole_scope_proof,protected_closure_current}')::boolean
      end,
    'occurrence_closure_current',
      (state.value #>>
        '{result,whole_scope_proof,occurrence_closure_current}')::boolean,
    'business_unchanged_during_rejection',
      (state.value->>'business_unchanged_during_rejection')::boolean,
    'probe_rolled_back_exactly',
      (state.value->>'probe_rolled_back_exactly')::boolean
  ),
  jsonb_build_object(
    'code', 'FLOW_IDENTITY_PRIMARY_OR_GUARD_DRIFT',
    'guard_current', false,
    'occurrence_closure_current',
      split_part(state.key, 'finalize_drift_', 2) <> 'occurrence',
    'business_unchanged_during_rejection', true,
    'probe_rolled_back_exactly', true
  ),
  split_part(state.key, 'finalize_drift_', 2)
    || ' drift fails closed before finalize and writes no business state'
)
from flow_identity_state as state
where state.key like 'finalize_drift_%'
order by state.key;

insert into flow_identity_state(key, value)
select 'recovery_request_1', pg_temp.flow_identity_recovery_request(
  (value->>'scope_id')::uuid,
  'wrapper_exited_without_permit',
  'fa000000-0000-4000-8000-000000000020'::uuid
)
from flow_identity_state where key = 'preflight';
insert into flow_identity_state(key, value)
select 'recovery_result_1',
  api.cmd_dataset_flow_identity_scope_recover_guarded(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight'),
    value
  )
from flow_identity_state where key = 'recovery_request_1';
select is(
  (select jsonb_build_object(
    'ok', value->>'ok',
    'replay', value->>'replay',
    'permit_schema', value #>> '{execution_permit,schema_version}',
    'wire_hash_bound', value->>'recovery_wire_request_sha256' =
      pg_temp.flow_identity_invocation(
        (value->>'invocation_id')::uuid
      )->>'admission_request_sha256'
  )
  from flow_identity_state
  where key = 'recovery_result_1'),
  jsonb_build_object(
    'ok', 'true', 'replay', 'false',
    'permit_schema', 'dataset-flow-identity-execution-permit.v1',
    'wire_hash_bound', true
  ),
  'fresh exact recovery consumes one approval and returns one memory-only permit'
);
select is(
  (select jsonb_build_object(
    'replay', replay.value->>'replay',
    'permit_is_null', replay.value->'execution_permit' = 'null'::jsonb
  )
  from api.cmd_dataset_flow_identity_scope_recover_guarded(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight'),
    (select value from flow_identity_state where key = 'recovery_request_1')
  ) as replay(value)),
  jsonb_build_object('replay', 'true', 'permit_is_null', true),
  'exact recovery replay returns the same proof but never another permit'
);
select is(
  api.cmd_dataset_flow_identity_scope_recover_guarded(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight'),
    jsonb_set(
      pg_temp.flow_identity_recovery_request(
        (select (value->>'scope_id')::uuid
          from flow_identity_state where key = 'preflight'),
        'wrapper_exited_without_permit',
        'fa000000-0000-4000-8000-000000000022'::uuid
      ),
      '{recovery_approval_request_sha256}',
      (select to_jsonb(value->>'recovery_approval_text_sha256')
       from flow_identity_state where key = 'recovery_request_1'),
      false
    )
  )->>'code',
  'FLOW_IDENTITY_RECOVERY_APPROVAL_REUSE_MISMATCH',
  'recovery rejects actor approval hash reuse across request/text domains'
);
insert into flow_identity_state(key, value)
select 'recovery_request_2', pg_temp.flow_identity_recovery_request(
  (value->>'scope_id')::uuid,
  'wrapper_exited_without_permit',
  'fa000000-0000-4000-8000-000000000021'::uuid
)
from flow_identity_state where key = 'preflight';
insert into flow_identity_state(key, value)
select 'recovery_result_2',
  api.cmd_dataset_flow_identity_scope_recover_guarded(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight'),
    value
  )
from flow_identity_state where key = 'recovery_request_2';
select is(
  api.cmd_dataset_flow_identity_scope_finalize_guarded(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight'),
    (select value from flow_identity_state where key = 'finalize_request'),
    (select value->'execution_permit'
      from flow_identity_state where key = 'recovery_result_1')
  )->>'code',
  'FLOW_IDENTITY_WRAPPER_PERMIT_REQUIRED',
  'a newer recovery atomically invalidates the prior wrapper permit'
);

insert into flow_identity_state(key, value)
select 'finalize_result',
  api.cmd_dataset_flow_identity_scope_finalize_guarded(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight'),
    (select value from flow_identity_state where key = 'finalize_request'),
    (select value->'execution_permit'
      from flow_identity_state where key = 'recovery_result_2')
  );

select is(
  (select value->>'status'
    from flow_identity_state where key = 'finalize_result'),
  'derivatives_pending',
  'finalize proves primary/protected closure but waits for causal derivatives'
);
select is(
  (select state_code from public.flows
    where id = pg_temp.flow_identity_id('source_flow')),
  0,
  'source flow remains an owner draft and is never mutated'
);
select is(
  (select state_code from public.flows
    where id = pg_temp.flow_identity_id('target_flow')),
  100,
  'public target remains published and read-only'
);

-- A terminal derivative failure must not make the committed process
-- transaction replayable.  It yields an exact derivative-only compensation
-- target; admission still requires a separate plan/freeze/approval outside
-- this scope.
reset role;
select pg_temp.complete_flow_identity_derivative(
  (select child.id
   from util.dataset_derivative_rebuild_requests as child
   where child.batch_id = (
     select (value->>'derivative_batch_id')::uuid
     from flow_identity_state where key = 'process_result_2'
   )),
  'second ordered process'
);
update util.dataset_derivative_rebuild_requests
set
  status = 'failed',
  phase = 'failed',
  terminal_at = clock_timestamp(),
  drained_at = clock_timestamp(),
  failure_release_not_before = clock_timestamp(),
  last_error = jsonb_build_object('code', 'TEST_TERMINAL_FAILURE')
where batch_id = (
  select (value->>'derivative_batch_id')::uuid
  from flow_identity_state where key = 'process_result'
);
set local role authenticated;

insert into flow_identity_state(key, value)
select 'failed_scope_read', api.cmd_dataset_flow_identity_scope_read(
  (select (value->>'scope_id')::uuid
    from flow_identity_state where key = 'preflight')
);
select is(
  (select value->>'status'
    from flow_identity_state where key = 'failed_scope_read'),
  'derivatives_pending',
  'terminal derivative failure leaves the primary scope recoverable'
);
select is(
  (select value->>'compensation_required'
    from flow_identity_state where key = 'failed_scope_read'),
  'true',
  'scope read explicitly requires a separately approved compensation'
);
select is(
  (select value->>'code'
    from flow_identity_state where key = 'failed_scope_read'),
  'FLOW_IDENTITY_DERIVATIVE_COMPENSATION_REQUIRED',
  'failed scope read emits the exact CLI compensation code'
);
select is(
  (select jsonb_build_object(
      'original_status', value #>> '{compensation_targets,0,original_status}',
      'original_code', value #>> '{compensation_targets,0,original_code}'
    ) from flow_identity_state where key = 'failed_scope_read'),
  jsonb_build_object(
    'original_status', 'failed',
    'original_code', 'TEST_TERMINAL_FAILURE'
  ),
  'failed scope read binds exact original status and error code'
);
select is(
  (select jsonb_agg(keys.object_key order by keys.object_key)
   from flow_identity_state state
   cross join lateral jsonb_object_keys(
     state.value #> '{compensation_targets,0}'
   ) as keys(object_key)
   where state.key = 'failed_scope_read'),
  to_jsonb(array[
    'automatic_retry', 'components', 'current_json_ordered_sha256',
    'current_modified_at', 'current_snapshot_sha256',
    'desired_payload_sha256', 'id', 'latest_compensation_plan_sha256',
    'latest_compensation_request_id', 'latest_compensation_status',
    'operation_id_prefix', 'ordinal', 'original_batch_id', 'original_code',
    'original_error', 'original_request_id', 'original_status', 'reason_code',
    'requires_new_plan_freeze_approval', 'table', 'version'
  ]::text[]),
  'scope-read compensation target has the exact CLI response keys'
);
select is(
  (select value #>> '{compensation_targets,0,current_snapshot_sha256}'
    from flow_identity_state where key = 'failed_scope_read'),
  (select util.dataset_derivative_rebuild_snapshot(process)->>'snapshot_sha256'
    from public.processes as process
    where process.id = pg_temp.flow_identity_id('process')),
  'scope read returns the exact current derivative snapshot hash'
);

insert into flow_identity_state(key, value)
select 'failed_finalize',
  api.cmd_dataset_flow_identity_scope_finalize_guarded(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight'),
    (select value from flow_identity_state where key = 'finalize_request'),
    pg_temp.flow_identity_recover(
      (select (value->>'scope_id')::uuid
        from flow_identity_state where key = 'preflight'),
      'finalize_response_ambiguous'
    )->'execution_permit'
  );
select is(
  (select value->>'code'
    from flow_identity_state where key = 'failed_finalize'),
  'FLOW_IDENTITY_DERIVATIVE_COMPENSATION_REQUIRED',
  'finalize reports compensation instead of terminally failing the scope'
);
select is(
  (select jsonb_build_object(
      'original_status', value #>> '{compensation_targets,0,original_status}',
      'original_code', value #>> '{compensation_targets,0,original_code}'
    ) from flow_identity_state where key = 'failed_finalize'),
  jsonb_build_object(
    'original_status', 'failed',
    'original_code', 'TEST_TERMINAL_FAILURE'
  ),
  'failed finalize compensation binds original status and error code'
);
select is(
  (select jsonb_agg(keys.object_key order by keys.object_key)
   from flow_identity_state state
   cross join lateral jsonb_object_keys(
     state.value #> '{compensation_targets,0}'
   ) as keys(object_key)
   where state.key = 'failed_finalize'),
  to_jsonb(array[
    'automatic_retry', 'components', 'current_json_ordered_sha256',
    'current_modified_at', 'current_snapshot_sha256',
    'desired_payload_sha256', 'id', 'latest_compensation_plan_sha256',
    'latest_compensation_request_id', 'latest_compensation_status',
    'operation_id_prefix', 'ordinal', 'original_batch_id', 'original_code',
    'original_status', 'reason_code', 'requires_new_plan_freeze_approval',
    'table', 'version'
  ]::text[]),
  'finalize compensation target has the exact CLI response keys'
);

reset role;
update util.dataset_derivative_rebuild_requests
set status = 'stale', phase = 'failed',
  last_error = jsonb_build_object('code', 'TEST_TERMINAL_STALE')
where batch_id = (
  select (value->>'derivative_batch_id')::uuid
  from flow_identity_state where key = 'process_result'
);
set local role authenticated;
insert into flow_identity_state(key, value)
select 'stale_scope_read', api.cmd_dataset_flow_identity_scope_read(
  (select (value->>'scope_id')::uuid
    from flow_identity_state where key = 'preflight')
);
select is(
  (select value->>'code'
    from flow_identity_state where key = 'stale_scope_read'),
  'FLOW_IDENTITY_DERIVATIVE_COMPENSATION_REQUIRED',
  'stale scope read emits the exact CLI compensation code'
);
select is(
  (select jsonb_build_object(
      'original_status', value #>> '{compensation_targets,0,original_status}',
      'original_code', value #>> '{compensation_targets,0,original_code}'
    ) from flow_identity_state where key = 'stale_scope_read'),
  jsonb_build_object(
    'original_status', 'stale',
    'original_code', 'TEST_TERMINAL_STALE'
  ),
  'stale scope read binds exact original status and error code'
);
insert into flow_identity_state(key, value)
select 'stale_finalize',
  api.cmd_dataset_flow_identity_scope_finalize_guarded(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight'),
    (select value from flow_identity_state where key = 'finalize_request'),
    pg_temp.flow_identity_recover(
      (select (value->>'scope_id')::uuid
        from flow_identity_state where key = 'preflight'),
      'finalize_response_ambiguous'
    )->'execution_permit'
  );
select is(
  (select jsonb_build_object(
      'original_status', value #>> '{compensation_targets,0,original_status}',
      'original_code', value #>> '{compensation_targets,0,original_code}'
    ) from flow_identity_state where key = 'stale_finalize'),
  jsonb_build_object(
    'original_status', 'stale',
    'original_code', 'TEST_TERMINAL_STALE'
  ),
  'stale finalize compensation binds original status and error code'
);
reset role;
update util.dataset_derivative_rebuild_requests
set status = 'failed', phase = 'failed',
  last_error = jsonb_build_object('code', 'TEST_TERMINAL_FAILURE')
where batch_id = (
  select (value->>'derivative_batch_id')::uuid
  from flow_identity_state where key = 'process_result'
);
set local role authenticated;

insert into flow_identity_state(key, value)
select 'compensation_plan', jsonb_build_object(
  'schema_version', 'dataset-derivative-rebuild-plan.v1',
  'plan_sha256', repeat('c', 64),
  'operation_id', 'FLOW_IDENTITY_SCOPE_COMPENSATION:'
    || (preflight.value->>'scope_id') || ':1:attempt-1',
  'target_visibility', 'owner_draft',
  'actions', jsonb_build_array(jsonb_build_object(
    'action_id', 'FLOW_IDENTITY_SCOPE_COMPENSATION:'
      || (preflight.value->>'scope_id') || ':1:attempt-1',
    'action', 'rebuild_derivatives',
    'table', 'processes',
    'id', pg_temp.flow_identity_id('process'),
    'version', '01.00.000',
    'expected_state_code', 0,
    'expected_snapshot_sha256', snapshot.value->>'snapshot_sha256',
    'components', jsonb_build_array('extracted_md', 'embedding_ft'),
    'reason_code', 'FLOW_IDENTITY_SCOPE_COMPENSATION:'
      || (preflight.value->>'scope_id') || ':1'
  ))
)
from flow_identity_state as preflight
cross join public.processes as process
cross join lateral (
  select util.dataset_derivative_rebuild_snapshot(process) as value
) as snapshot
where preflight.key = 'preflight'
  and process.id = pg_temp.flow_identity_id('process');

insert into flow_identity_state(key, value)
select 'compensation_result',
  api.cmd_dataset_derivative_rebuild_plan_guarded(value)
from flow_identity_state where key = 'compensation_plan';
select is(
  (select value->>'ok'
    from flow_identity_state where key = 'compensation_result'),
  'true',
  'a separately frozen derivative-only compensation can be admitted'
);
select is(
  util.read_dataset_derivative_rebuild_batch_any(
    pg_temp.flow_identity_id('owner'),
    (select (value->>'request_id')::uuid
      from flow_identity_state where key = 'compensation_result')
  )->>'reference_kind',
  'request',
  'dynamic causal reader accepts the exact single compensation request id'
);

insert into flow_identity_state(key, value)
select 'compensation_finalize',
  api.cmd_dataset_flow_identity_scope_finalize_guarded(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight'),
    (select value from flow_identity_state where key = 'finalize_request'),
    pg_temp.flow_identity_recover(
      (select (value->>'scope_id')::uuid
        from flow_identity_state where key = 'preflight'),
      'derivatives_became_ready_after_wrapper_exit'
    )->'execution_permit'
  );
select is(
  (select value->>'code'
    from flow_identity_state where key = 'compensation_finalize'),
  'FLOW_IDENTITY_DERIVATIVES_PENDING',
  'finalize follows the exact compensation request without replaying primary'
);
select is(
  util.read_dataset_flow_identity_derivative_set(
    pg_temp.flow_identity_id('owner'),
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight')
  ) #>> '{targets,0,effective_reference_kind}',
  'separate_compensation',
  'finalize binds the separately approved compensation as effective proof'
);

reset role;
select pg_temp.complete_flow_identity_derivative(
  (select (value->>'request_id')::uuid
    from flow_identity_state where key = 'compensation_result'),
  'first compensation'
);
set local role authenticated;

insert into flow_identity_state(key, value)
select 'completed_finalize',
  api.cmd_dataset_flow_identity_scope_finalize_guarded(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight'),
    (select value from flow_identity_state where key = 'finalize_request'),
    pg_temp.flow_identity_recover(
      (select (value->>'scope_id')::uuid
        from flow_identity_state where key = 'preflight'),
      'derivatives_became_ready_after_wrapper_exit'
    )->'execution_permit'
  );
select is(
  (select value->>'status'
    from flow_identity_state where key = 'completed_finalize'),
  'completed',
  'completed separate compensation permits one real terminal finalize'
);

insert into flow_identity_state(key, value)
select 'completed_scope_history', to_jsonb(scope)
from util.dataset_flow_identity_scopes as scope
where scope.id = (
  select (value->>'scope_id')::uuid
  from flow_identity_state where key = 'preflight'
);
insert into flow_identity_state(key, value)
select 'completed_terminal_audit', to_jsonb(audit)
from private.command_audit_log as audit
where audit.command = 'cmd_dataset_flow_identity_scope_finalize_guarded'
  and audit.target_table is null
  and audit.payload->>'scope_id' = (
    select value->>'scope_id'
    from flow_identity_state where key = 'preflight'
  )
order by audit.id desc limit 1;

insert into flow_identity_state(key, value)
select 'completed_lookup', api.cmd_dataset_flow_identity_scope_lookup(
  jsonb_set(
    value, '{schema_version}',
    '"dataset-flow-identity-scope-lookup.v1"'::jsonb, false
  )
    - 'maximum_wrapper_invocations'
    - 'maximum_process_posts'
    - 'maximum_finalize_posts'
    - 'maximum_cli_apply_spawns'
    - 'approval_reusable'
    - 'automatic_retry'
)
from flow_identity_state where key = 'preflight_request_2';
select is(
  (select jsonb_build_object(
    'status', value->>'status',
    'permit_is_null', value->'execution_permit' = 'null'::jsonb
  ) from flow_identity_state where key = 'completed_lookup'),
  jsonb_build_object('status', 'completed', 'permit_is_null', true),
  'exact completed-scope lookup remains read-only and returns no permit'
);

select is(
  api.cmd_dataset_flow_identity_scope_finalize_guarded(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight'),
    (select value from flow_identity_state where key = 'finalize_request'),
    '{}'::jsonb
  )->>'code',
  'FLOW_IDENTITY_WRAPPER_PERMIT_REQUIRED',
  'completed finalize cannot replay without a fresh write-capable permit'
);
select is(
  (select to_jsonb(scope)
   from util.dataset_flow_identity_scopes as scope
   where scope.id = (
     select (value->>'scope_id')::uuid
     from flow_identity_state where key = 'preflight'
   )),
  (select value from flow_identity_state where key = 'completed_scope_history'),
  'completed finalize replay leaves the scope row byte-identical'
);
select is(
  (select to_jsonb(audit)
   from private.command_audit_log as audit
   where audit.command = 'cmd_dataset_flow_identity_scope_finalize_guarded'
     and audit.target_table is null
     and audit.payload->>'scope_id' = (
       select value->>'scope_id'
       from flow_identity_state where key = 'preflight'
     )
   order by audit.id desc limit 1),
  (select value from flow_identity_state where key = 'completed_terminal_audit'),
  'completed finalize replay leaves the terminal audit byte-identical'
);

-- Completed history remains immutable while live derivative proof can drift.
reset role;
update public.processes
set extracted_md = 'post-completion derivative drift'
where id = pg_temp.flow_identity_id('process');
set local role authenticated;
insert into flow_identity_state(key, value)
select 'completed_scope_derivative_drift',
  api.cmd_dataset_flow_identity_scope_read(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight')
  );
select is(
  (select value->>'status' from flow_identity_state
    where key = 'completed_scope_derivative_drift'),
  'derivatives_pending',
  'completed scope response downgrades when live derivative proof drifts'
);
select is(
  (select value->>'derivatives_current' from flow_identity_state
    where key = 'completed_scope_derivative_drift'),
  'false',
  'completed scope never reports derivatives current from persisted status'
);
select is(
  (select value #>> '{derivative_set_proof,status}'
    from flow_identity_state where key = 'completed_scope_derivative_drift'),
  'compensation_required',
  'scope read returns the complete live derivative-set failure proof'
);
select is(
  (select value->'derivative_set_proof' from flow_identity_state
    where key = 'completed_scope_derivative_drift'),
  util.read_dataset_flow_identity_derivative_set(
    pg_temp.flow_identity_id('owner'),
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight')
  ),
  'scope read nests the exact unmodified dynamic derivative-set proof'
);
select is(
  (select value->>'derivative_proof_set_sha256'
    from flow_identity_state where key = 'completed_scope_derivative_drift'),
  (select value #>> '{derivative_set_proof,proof_sha256}'
    from flow_identity_state where key = 'completed_scope_derivative_drift'),
  'scope-read proof SHA convenience field is derived from the nested proof'
);
select is(
  (select jsonb_build_object(
    'original_status', value #>> '{compensation_targets,0,original_status}',
    'original_code', value #>> '{compensation_targets,0,original_code}'
  ) from flow_identity_state where key = 'completed_scope_derivative_drift'),
  jsonb_build_object(
    'original_status', 'failed',
    'original_code', 'TEST_TERMINAL_FAILURE'
  ),
  'post-completion causal drift preserves the existing failed-child identity'
);
select is(
  (select scope.status
   from util.dataset_flow_identity_scopes scope
   join flow_identity_state preflight
     on scope.id = (preflight.value->>'scope_id')::uuid
   where preflight.key = 'preflight'),
  'completed',
  'read-time derivative drift never rewrites completed scope history'
);
select is(
  (select to_jsonb(scope)
   from util.dataset_flow_identity_scopes as scope
   where scope.id = (
     select (value->>'scope_id')::uuid
     from flow_identity_state where key = 'preflight'
   )),
  (select value from flow_identity_state where key = 'completed_scope_history'),
  'derivative drift does not mutate completed scope history'
);
select is(
  (select to_jsonb(audit)
   from private.command_audit_log as audit
   where audit.command = 'cmd_dataset_flow_identity_scope_finalize_guarded'
     and audit.target_table is null
     and audit.payload->>'scope_id' = (
       select value->>'scope_id'
       from flow_identity_state where key = 'preflight'
     )
   order by audit.id desc limit 1),
  (select value from flow_identity_state where key = 'completed_terminal_audit'),
  'derivative drift does not mutate completed terminal audit history'
);

insert into flow_identity_state(key, value)
select 'completed_drift_finalize',
  api.cmd_dataset_flow_identity_scope_finalize_guarded(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight'),
    (select value from flow_identity_state where key = 'finalize_request'),
    '{}'::jsonb
  );
select is(
  (select value->>'code'
   from flow_identity_state where key = 'completed_drift_finalize'),
  'FLOW_IDENTITY_WRAPPER_PERMIT_REQUIRED',
  'completed drift remains readable but cannot reopen finalize without a permit'
);
select is(
  (select to_jsonb(scope)
   from util.dataset_flow_identity_scopes as scope
   where scope.id = (
     select (value->>'scope_id')::uuid
     from flow_identity_state where key = 'preflight'
   )),
  (select value from flow_identity_state where key = 'completed_scope_history'),
  'drifted completed finalize leaves the scope row byte-identical'
);
select is(
  (select to_jsonb(audit)
   from private.command_audit_log as audit
   where audit.command = 'cmd_dataset_flow_identity_scope_finalize_guarded'
     and audit.target_table is null
     and audit.payload->>'scope_id' = (
       select value->>'scope_id'
       from flow_identity_state where key = 'preflight'
     )
   order by audit.id desc limit 1),
  (select value from flow_identity_state where key = 'completed_terminal_audit'),
  'drifted completed finalize leaves the terminal audit byte-identical'
);

-- A missing protected derivative child is a parseable compensation state,
-- not NULL status/phase ambiguity and not primary live drift.
reset role;
delete from util.dataset_derivative_rebuild_requests
where batch_id = (
    select (value->>'derivative_batch_id')::uuid
    from flow_identity_state where key = 'process_result'
  )
  or id = (
    select (value->>'request_id')::uuid
    from flow_identity_state where key = 'compensation_result'
  );
set local role authenticated;
insert into flow_identity_state(key, value)
select 'missing_child_read', api.cmd_dataset_flow_identity_scope_read(
  (select (value->>'scope_id')::uuid
    from flow_identity_state where key = 'preflight')
);
select is(
  (select jsonb_build_object(
    'status', value #>> '{derivative_set_proof,targets,0,status}',
    'request_status',
      value #>> '{derivative_set_proof,targets,0,request_status}',
    'phase', value #>> '{derivative_set_proof,targets,0,phase}',
    'effective_reference_id_is_null',
      value #> '{derivative_set_proof,targets,0,effective_reference_id}'
        = 'null'::jsonb,
    'lineage_ok', value #>> '{derivative_set_proof,targets,0,lineage_ok}',
    'causal_terminal_proof',
      value #>> '{derivative_set_proof,targets,0,causal_terminal_proof}'
  ) from flow_identity_state where key = 'missing_child_read'),
  jsonb_build_object(
    'status', 'failed',
    'request_status', 'missing',
    'phase', 'missing',
    'effective_reference_id_is_null', true,
    'lineage_ok', 'false',
    'causal_terminal_proof', 'false'
  ),
  'missing child exposes the exact nullable-reference sentinel proof'
);
select is(
  (select jsonb_build_object(
    'derivative_request_id_is_null',
      value #> '{processes,0,derivative_request_id}' = 'null'::jsonb,
    'derivative_status', value #>> '{processes,0,derivative_status}',
    'code', value->>'code',
    'compensation_required', value->>'compensation_required'
  ) from flow_identity_state where key = 'missing_child_read'),
  jsonb_build_object(
    'derivative_request_id_is_null', true,
    'derivative_status', 'missing',
    'code', 'FLOW_IDENTITY_DERIVATIVE_COMPENSATION_REQUIRED',
    'compensation_required', 'true'
  ),
  'scope process and status envelope expose the exact missing-child contract'
);
select is(
  (select jsonb_build_object(
    'count', jsonb_array_length(value->'compensation_targets'),
    'original_request_id_is_null',
      value #> '{compensation_targets,0,original_request_id}' = 'null'::jsonb,
    'original_status',
      value #>> '{compensation_targets,0,original_status}',
    'original_code', value #>> '{compensation_targets,0,original_code}'
  ) from flow_identity_state where key = 'missing_child_read'),
  jsonb_build_object(
    'count', 1,
    'original_request_id_is_null', true,
    'original_status', 'missing',
    'original_code', 'DERIVATIVE_BATCH_CHILD_MISSING'
  ),
  'missing child always emits one exact separately approvable compensation target'
);

insert into flow_identity_state(key, value)
select 'missing_child_finalize',
  api.cmd_dataset_flow_identity_scope_finalize_guarded(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight'),
    (select value from flow_identity_state where key = 'finalize_request'),
    '{}'::jsonb
  );
select is(
  (select value->>'code'
   from flow_identity_state where key = 'missing_child_finalize'),
  'FLOW_IDENTITY_WRAPPER_PERMIT_REQUIRED',
  'completed missing-child proof cannot reopen finalize without a permit'
);

insert into flow_identity_state(key, value)
select 'second_compensation_plan', jsonb_build_object(
  'schema_version', 'dataset-derivative-rebuild-plan.v1',
  'plan_sha256', repeat('d', 64),
  'operation_id', 'FLOW_IDENTITY_SCOPE_COMPENSATION:'
    || (preflight.value->>'scope_id') || ':1:attempt-2',
  'target_visibility', 'owner_draft',
  'actions', jsonb_build_array(jsonb_build_object(
    'action_id', 'FLOW_IDENTITY_SCOPE_COMPENSATION:'
      || (preflight.value->>'scope_id') || ':1:attempt-2',
    'action', 'rebuild_derivatives',
    'table', 'processes',
    'id', pg_temp.flow_identity_id('process'),
    'version', '01.00.000',
    'expected_state_code', 0,
    'expected_snapshot_sha256', snapshot.value->>'snapshot_sha256',
    'components', jsonb_build_array('extracted_md', 'embedding_ft'),
    'reason_code', 'FLOW_IDENTITY_SCOPE_COMPENSATION:'
      || (preflight.value->>'scope_id') || ':1'
  ))
)
from flow_identity_state as preflight
cross join public.processes as process
cross join lateral (
  select util.dataset_derivative_rebuild_snapshot(process) as value
) as snapshot
where preflight.key = 'preflight'
  and process.id = pg_temp.flow_identity_id('process');

insert into flow_identity_state(key, value)
select 'second_compensation_result',
  api.cmd_dataset_derivative_rebuild_plan_guarded(value)
from flow_identity_state where key = 'second_compensation_plan';
select is(
  (select value->>'ok'
    from flow_identity_state where key = 'second_compensation_result'),
  'true',
  'missing child can be recovered only by a new separately admitted compensation'
);
select is(
  util.read_dataset_flow_identity_derivative_set(
    pg_temp.flow_identity_id('owner'),
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight')
  ) #>> '{targets,0,effective_reference_kind}',
  'separate_compensation',
  'new compensation replaces the missing protected child as effective proof'
);

reset role;
select pg_temp.complete_flow_identity_derivative(
  (select (value->>'request_id')::uuid
    from flow_identity_state where key = 'second_compensation_result'),
  'second compensation'
);
set local role authenticated;
insert into flow_identity_state(key, value)
select 'recovered_completed_finalize',
  api.cmd_dataset_flow_identity_scope_finalize_guarded(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight'),
    (select value from flow_identity_state where key = 'finalize_request'),
    '{}'::jsonb
  );
select is(
  (select value->>'code'
   from flow_identity_state where key = 'recovered_completed_finalize'),
  'FLOW_IDENTITY_WRAPPER_PERMIT_REQUIRED',
  'recovered terminal proof remains read-only without a new permit'
);
select is(
  (select to_jsonb(scope)
   from util.dataset_flow_identity_scopes as scope
   where scope.id = (
     select (value->>'scope_id')::uuid
     from flow_identity_state where key = 'preflight'
   )),
  (select value from flow_identity_state where key = 'completed_scope_history'),
  'recovered completed finalize leaves original terminal scope byte-identical'
);
select is(
  (select to_jsonb(audit)
   from private.command_audit_log as audit
   where audit.command = 'cmd_dataset_flow_identity_scope_finalize_guarded'
     and audit.target_table is null
     and audit.payload->>'scope_id' = (
       select value->>'scope_id'
       from flow_identity_state where key = 'preflight'
     )
   order by audit.id desc limit 1),
  (select value from flow_identity_state where key = 'completed_terminal_audit'),
  'recovered completed finalize leaves original terminal audit byte-identical'
);

select set_config(
  'request.jwt.claim.sub', pg_temp.flow_identity_id('other')::text, true
);
select set_config(
  'request.jwt.claim.email', 'flow-other@example.com', true
);
select is(
  api.cmd_dataset_flow_identity_scope_lookup(jsonb_set(
    jsonb_set(
      pg_temp.flow_identity_lookup(),
      '{actor,user_id}',
      to_jsonb(pg_temp.flow_identity_id('other')::text), false
    ),
    '{actor,email}', '"flow-other@example.com"'::jsonb, false
  ))->>'code',
  'FLOW_IDENTITY_SCOPE_LOOKUP_NOT_FOUND',
  'foreign actor lookup returns the same non-leaking not-found result'
);
select is(
  api.cmd_dataset_flow_identity_scope_read(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight')
  )->>'code',
  'FLOW_IDENTITY_SCOPE_NOT_FOUND',
  'foreign actor cannot read another owner scope'
);
select is(
  api.cmd_dataset_flow_identity_scope_cancel_guarded(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight'),
    pg_temp.flow_identity_cancel_request(
      'fa000000-0000-4000-8000-000000000013'::uuid,
      'foreign actor must not abandon owner scope'
    )
  )->>'code',
  'FLOW_IDENTITY_SCOPE_NOT_FOUND',
  'foreign actor cannot cancel another owner scope'
);

select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.email', '', true);
select is(
  api.cmd_dataset_flow_identity_scope_preflight_guarded(
    '{}'::jsonb
  )->>'code',
  'AUTH_REQUIRED',
  'preflight requires an authenticated actor'
);
select is(
  api.cmd_dataset_flow_identity_scope_cancel_guarded(
    (select (value->>'scope_id')::uuid
      from flow_identity_state where key = 'preflight'),
    pg_temp.flow_identity_cancel_request(
      'fa000000-0000-4000-8000-000000000014'::uuid,
      'unauthenticated actor must not abandon scope'
    )
  )->>'code',
  'AUTH_REQUIRED',
  'cancel requires an authenticated actor'
);

reset role;

select * from finish();
rollback;
