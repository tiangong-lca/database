-- Database #958: certificate-bound admission must not rebuild the global JSON manifest.
-- No timeout, exposed RPC, certificate validation or queue contract changes.
CREATE OR REPLACE FUNCTION "private"."lcia_result_build_request_envelope"("p_name" "text", "p_processes" "jsonb", "p_coverage_mode" "text", "p_default_impact_category" "text", "p_lcia_method_set" "jsonb", "p_idempotency_key" "text", "p_audit" "jsonb", "p_eligibility_context" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'private', 'api', 'public', 'util', 'extensions', 'pg_temp'
    AS $$
declare
  v_actor uuid := auth.uid();
  v_coverage_mode text := lower(trim(coalesce(p_coverage_mode, 'global_eligible')));
  v_build_id uuid;
  v_idempotency_key text;
  v_current_manifest jsonb;
  v_input_manifest jsonb;
  v_input_manifest_hash text;
  v_eligible_input_count integer;
  v_included_input_count integer;
  v_invalid_count integer := 0;
  v_duplicate_count integer := 0;
  v_request_hash text;
  v_worker_payload jsonb;
  v_worker_job jsonb;
begin
  if v_actor is null then
    return api.lcia_result_error('auth_required', 401, 'Authentication required');
  end if;

  if not api.lcia_result_is_manager() then
    return api.lcia_result_error('not_data_product_manager', 403, 'Data product manager role is required');
  end if;

  if v_coverage_mode not in ('subset', 'global_eligible') then
    return api.lcia_result_error('invalid_coverage_mode', 400, 'coverage_mode must be subset or global_eligible');
  end if;

  if v_coverage_mode = 'global_eligible'
     and p_processes is not null
     and jsonb_array_length(p_processes) > 0 then
    return api.lcia_result_error('invalid_coverage_mode', 400, 'global_eligible builds are resolved from the current published input predicate');
  end if;

  if jsonb_typeof(coalesce(p_lcia_method_set, '[]'::jsonb)) <> 'array' then
    return api.lcia_result_error('invalid_lcia_method_set', 400, 'lcia_method_set must be a JSON array');
  end if;

  if p_processes is not null and jsonb_typeof(p_processes) <> 'array' then
    return api.lcia_result_error('invalid_process_selection', 400, 'process selection must be a JSON array');
  end if;

  -- V2 already owns an immutable certificate scope. Only the legacy caller
  -- resolves the live global manifest; keep selection validation below shared.
  if p_eligibility_context is not null and v_coverage_mode <> 'subset' then
    return api.lcia_result_error('invalid_coverage_mode', 400, 'Frozen eligibility context requires an explicit subset');
  end if;
  v_current_manifest := coalesce(p_eligibility_context, api.lcia_result_current_eligible_manifest());
  v_eligible_input_count := (v_current_manifest->>'eligibleInputCount')::integer;

  if v_coverage_mode = 'global_eligible' then
    v_input_manifest := v_current_manifest->'inputManifest';
    v_input_manifest_hash := v_current_manifest->>'inputManifestHash';
    v_included_input_count := v_eligible_input_count;
  else
    with requested as (
      select
        (item.value->>'id')::uuid as process_id,
        coalesce(item.value->>'version', item.value->>'process_version')::character(9) as process_version,
        item.ordinality::integer as ordinal
      from jsonb_array_elements(coalesce(p_processes, '[]'::jsonb)) with ordinality as item(value, ordinality)
    ),
    duplicate_rows as (
      select process_id, process_version, count(*)::integer as duplicate_count
      from requested
      group by process_id, process_version
      having count(*) > 1
    ),
    resolved as (
      select
        r.process_id,
        r.process_version,
        r.ordinal,
        p.state_code
      from requested as r
      left join public.processes as p
        on p.id = r.process_id
       and p.version = r.process_version
    ),
    aggregated as (
      select
        count(*) filter (where state_code between 100 and 199)::integer as included_count,
        count(*) filter (where state_code is null or state_code not between 100 and 199)::integer as invalid_count,
        coalesce((select sum(duplicate_count - 1)::integer from duplicate_rows), 0) as duplicate_count,
        md5(
          coalesce(
            string_agg(
              process_id::text || ':' || process_version,
              ','
              order by process_id, process_version
            ) filter (where state_code between 100 and 199),
            ''
          ) || '|published:100-199:v1'
        ) as manifest_hash,
        coalesce(
          jsonb_agg(
            jsonb_build_object(
              'id', process_id,
              'version', process_version,
              'stateCode', state_code
            )
            order by ordinal
          ) filter (where state_code between 100 and 199),
          '[]'::jsonb
        ) as selected_processes
      from resolved
    )
    select
      included_count,
      invalid_count,
      duplicate_count,
      manifest_hash,
      jsonb_build_object(
        'predicateVersion', 'published-state-code-100-199:v1',
        'selectionMode', 'manual',
        'processes', selected_processes
      )
    into
      v_included_input_count,
      v_invalid_count,
      v_duplicate_count,
      v_input_manifest_hash,
      v_input_manifest
    from aggregated;

    if v_duplicate_count > 0 then
      return api.lcia_result_error('invalid_process_selection', 400, 'process selection contains duplicate inputs');
    end if;

    if v_invalid_count > 0 then
      return api.lcia_result_error('input_not_eligible', 400, 'All LCIA result package inputs must be published process rows');
    end if;
  end if;

  if coalesce(v_included_input_count, 0) = 0 then
    return api.lcia_result_error('input_empty', 400, 'LCIA result package build requires at least one eligible process');
  end if;

  v_idempotency_key := 'lcia_result.package_build:' || coalesce(
    nullif(trim(coalesce(p_idempotency_key, '')), ''),
    gen_random_uuid()::text
  );

  if nullif(trim(coalesce(p_idempotency_key, '')), '') is not null then
    v_build_id := (
      substr(md5(v_actor::text || ':' || p_idempotency_key), 1, 8) || '-' ||
      substr(md5(v_actor::text || ':' || p_idempotency_key), 9, 4) || '-' ||
      substr(md5(v_actor::text || ':' || p_idempotency_key), 13, 4) || '-' ||
      substr(md5(v_actor::text || ':' || p_idempotency_key), 17, 4) || '-' ||
      substr(md5(v_actor::text || ':' || p_idempotency_key), 21, 12)
    )::uuid;
  else
    v_build_id := gen_random_uuid();
  end if;

  v_request_hash := md5(
    v_input_manifest_hash || '|' ||
    coalesce(p_default_impact_category, '') || '|' ||
    coalesce(p_lcia_method_set::text, '[]')
  );

  v_worker_payload := jsonb_build_object(
    'type', 'lcia_result_package_build',
    'build_id', v_build_id,
    'requested_by', v_actor,
    'name', nullif(trim(coalesce(p_name, '')), ''),
    'coverage_mode', v_coverage_mode,
    'input_status_filter', v_current_manifest->'inputStatusFilter',
    'eligibility_definition', v_current_manifest - 'eligibleInputCount' - 'includedInputCount' - 'inputManifestHash' - 'inputManifest',
    'eligibility_resolved_at', now(),
    'eligible_input_count', v_eligible_input_count,
    'included_input_count', v_included_input_count,
    'input_manifest_hash', v_input_manifest_hash,
    'input_manifest', v_input_manifest,
    'lcia_method_set', coalesce(p_lcia_method_set, '[]'::jsonb),
    'default_impact_category', nullif(trim(coalesce(p_default_impact_category, '')), ''),
    'postprocess_manifest', jsonb_build_object(
      'postprocess_mode', 'skipped',
      'postprocess_reason', 'MVP does not aggregate process results'
    )
  );

  v_worker_job := jsonb_build_object(
    'jobKind', 'lcia_result.package_build',
    'payload', v_worker_payload,
    'payloadSchemaVersion', 'lcia_result.package_build.request.v1',
    'subjectType', 'lcia_result_build',
    'subjectId', v_build_id,
    'subjectVersion', null,
    'requestedBy', v_actor,
    'requesterType', 'operator',
    'idempotencyKey', v_idempotency_key,
    'requestHash', v_request_hash,
    'queueKey', v_build_id,
    'visibility', 'operator'
  );

  insert into private.command_audit_log (
    command,
    actor_user_id,
    target_table,
    target_id,
    target_version,
    payload
  )
  values (
    'cmd_lcia_result_build_request',
    v_actor,
    'worker_jobs',
    v_build_id,
    null,
    coalesce(p_audit, '{}'::jsonb) || jsonb_build_object(
      'coverageMode', v_coverage_mode,
      'eligibleInputCount', v_eligible_input_count,
      'includedInputCount', v_included_input_count,
      'inputManifestHash', v_input_manifest_hash
    )
  );

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'buildId', v_build_id,
      'coverageMode', v_coverage_mode,
      'eligibleInputCount', v_eligible_input_count,
      'includedInputCount', v_included_input_count,
      'inputManifestHash', v_input_manifest_hash,
      'workerJob', v_worker_job
    ),
    'reused', false
  );
exception
  when invalid_text_representation then
    return api.lcia_result_error('invalid_process_selection', 400, 'process ids and versions must be valid');
end;
$$;

ALTER FUNCTION "private"."lcia_result_build_request_envelope"("p_name" "text", "p_processes" "jsonb", "p_coverage_mode" "text", "p_default_impact_category" "text", "p_lcia_method_set" "jsonb", "p_idempotency_key" "text", "p_audit" "jsonb", "p_eligibility_context" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."lcia_result_build_request_envelope"("p_name" "text", "p_processes" "jsonb", "p_coverage_mode" "text", "p_default_impact_category" "text", "p_lcia_method_set" "jsonb", "p_idempotency_key" "text", "p_audit" "jsonb", "p_eligibility_context" "jsonb") FROM PUBLIC;

REVOKE ALL ON FUNCTION private.lcia_result_build_request_envelope(text,jsonb,text,text,jsonb,text,jsonb,jsonb) FROM anon, authenticated, service_role, api_internal_executor;

CREATE OR REPLACE FUNCTION "private"."cmd_lcia_result_build_request_legacy"("p_name" "text", "p_processes" "jsonb" DEFAULT NULL::"jsonb", "p_coverage_mode" "text" DEFAULT 'global_eligible'::"text", "p_default_impact_category" "text" DEFAULT NULL::"text", "p_lcia_method_set" "jsonb" DEFAULT '[]'::"jsonb", "p_idempotency_key" "text" DEFAULT NULL::"text", "p_audit" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'private', 'api', 'public', 'util', 'extensions', 'pg_temp'
    AS $$
begin
  return private.lcia_result_build_request_envelope(
    p_name, p_processes, p_coverage_mode, p_default_impact_category,
    p_lcia_method_set, p_idempotency_key, p_audit, null
  );
end;
$$;
ALTER FUNCTION "private"."cmd_lcia_result_build_request_legacy"("p_name" "text", "p_processes" "jsonb", "p_coverage_mode" "text", "p_default_impact_category" "text", "p_lcia_method_set" "jsonb", "p_idempotency_key" "text", "p_audit" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."cmd_lcia_result_build_request_legacy"("p_name" "text", "p_processes" "jsonb", "p_coverage_mode" "text", "p_default_impact_category" "text", "p_lcia_method_set" "jsonb", "p_idempotency_key" "text", "p_audit" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."cmd_lcia_result_build_request_legacy"("p_name" "text", "p_processes" "jsonb", "p_coverage_mode" "text", "p_default_impact_category" "text", "p_lcia_method_set" "jsonb", "p_idempotency_key" "text", "p_audit" "jsonb") TO "api_internal_executor";

CREATE OR REPLACE FUNCTION "private"."cmd_lcia_result_build_request_v2_envelope"("p_name" "text", "p_processes" "jsonb", "p_coverage_mode" "text", "p_default_impact_category" "text", "p_lcia_method_set" "jsonb", "p_idempotency_key" "text", "p_closure_check_id" "uuid", "p_requested_scope_hash" "text", "p_policy_fingerprint" "text", "p_audit" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'private', 'api', 'public', 'util', 'extensions', 'pg_temp'
    AS $$
declare v_actor uuid := auth.uid(); v_check private.lcia_scope_closure_checks%rowtype; v_result jsonb; v_effective jsonb; v_payload jsonb; v_eligibility_context jsonb; v_previous_metadata jsonb;
begin
  if v_actor is null then return api.lcia_scope_closure_error('auth_required',401,'Authentication required'); end if;
  select * into v_check from private.lcia_scope_closure_checks where id=p_closure_check_id and requested_by=v_actor;
  if v_check.id is null then return api.lcia_scope_closure_error('closure_check_not_found',404,'Closure check not found'); end if;
  if v_check.certificate_status='stale' then return api.lcia_scope_closure_error('closure_check_stale',409,'Closure certificate is stale'); end if;
  if v_check.certificate_status='revoked' then return api.lcia_scope_closure_error('closure_check_revoked',409,'Closure certificate is revoked'); end if;
  if v_check.status<>'passed' or v_check.scan_completeness<>'complete' or v_check.certificate_status<>'valid' or v_check.certificate_hash is null then return api.lcia_scope_closure_error('closure_check_not_usable',409,'A valid complete closure certificate is required'); end if;
  if v_check.requested_scope_hash<>trim(coalesce(p_requested_scope_hash,'')) then return api.lcia_scope_closure_error('closure_check_scope_mismatch',409,'Requested scope does not match the closure certificate'); end if;
  if v_check.policy_fingerprint<>trim(coalesce(p_policy_fingerprint,'')) then return api.lcia_scope_closure_error('closure_check_policy_mismatch',409,'Policy does not match the closure certificate'); end if;
  v_effective:=coalesce(v_check.effective_scope_manifest,v_check.requested_scope_manifest);
  -- Counts and predicate describe the certified effective scope, not an
  -- unrelated live global universe. Freshness/snapshot checks remain upstream.
  v_eligibility_context := jsonb_build_object(
    'predicateVersion', v_effective->>'eligibilityPredicateVersion',
    'selectionMode', 'closure_certificate',
    'inputStatusFilter', jsonb_build_object('state_code', jsonb_build_object('eq', 100)),
    'eligibleInputCount', jsonb_array_length(v_effective->'processes')
  );
  v_result:=private.lcia_result_build_request_envelope(p_name,v_effective->'processes','subset',p_default_impact_category,v_effective->'lciaMethods',p_idempotency_key,coalesce(p_audit,'{}'::jsonb)||jsonb_build_object('closureCheckId',v_check.id,'requestedScopeHash',v_check.requested_scope_hash,'policyFingerprint',v_check.policy_fingerprint,'certificateHash',v_check.certificate_hash),v_eligibility_context);
  if coalesce((v_result->>'ok')::boolean, false) is not true then return v_result; end if;
  v_payload:=(v_result->'data'->'workerJob'->'payload') || jsonb_build_object('eligibility_resolved_at',v_check.finished_at,'coverage_mode',v_effective->>'coverageMode','input_manifest',jsonb_build_object('predicateVersion',v_effective->>'eligibilityPredicateVersion','selectionMode','closure_certificate','processes',v_effective->'processes'),'input_manifest_hash',private.lcia_scope_closure_sha256(jsonb_build_object('processes',v_effective->'processes')),'lcia_method_set',v_effective->'lciaMethods','closure_check_id',v_check.id,'closure_certificate_hash',v_check.certificate_hash,'effective_scope_hash',v_check.effective_scope_hash,'data_snapshot_token',v_check.data_snapshot_token,'snapshot_id',v_check.snapshot_id,'snapshot_hash',v_check.snapshot_hash,'closure_bundle_hash',v_check.closure_bundle_hash,'report_artifact_manifest_hash',v_check.report_artifact_manifest_hash);
  -- Preserve descriptive metadata of an already admitted exact-bound job.
  -- Old jobs used submission time / global counts; new jobs use frozen scope.
  -- The enqueue layer still compares the complete resulting payload, including
  -- every certificate/snapshot/scope field, and never mutates the existing job.
  select (select jsonb_object_agg(key,value) from jsonb_each(j.payload_json)
          where key in ('eligibility_resolved_at','eligibility_definition',
                        'eligible_input_count','input_status_filter'))
  into v_previous_metadata
  from private.worker_jobs j
  where j.job_kind='lcia_result.package_build'
    and j.requested_by=v_actor
    and j.subject_id=(v_result->'data'->>'buildId')::uuid
    and j.idempotency_key=v_result->'data'->'workerJob'->>'idempotencyKey'
    and j.payload_schema_version='lcia_result.package_build.request.v2'
    and j.payload_json->>'closure_check_id'=v_check.id::text
    and j.payload_json->>'closure_certificate_hash'=v_check.certificate_hash
    and j.status in ('queued','running','waiting','stale','blocked')
  order by j.created_at desc limit 1;
  v_payload := v_payload || coalesce(v_previous_metadata,'{}'::jsonb);
  return jsonb_set(v_result,'{data,workerJob,payload}',v_payload,true) || jsonb_build_object('closureCheckId',v_check.id,'effectiveScopeHash',v_check.effective_scope_hash,'certificateHash',v_check.certificate_hash);
end;
$$;

ALTER FUNCTION "private"."cmd_lcia_result_build_request_v2_envelope"("p_name" "text", "p_processes" "jsonb", "p_coverage_mode" "text", "p_default_impact_category" "text", "p_lcia_method_set" "jsonb", "p_idempotency_key" "text", "p_closure_check_id" "uuid", "p_requested_scope_hash" "text", "p_policy_fingerprint" "text", "p_audit" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."cmd_lcia_result_build_request_v2_envelope"("p_name" "text", "p_processes" "jsonb", "p_coverage_mode" "text", "p_default_impact_category" "text", "p_lcia_method_set" "jsonb", "p_idempotency_key" "text", "p_closure_check_id" "uuid", "p_requested_scope_hash" "text", "p_policy_fingerprint" "text", "p_audit" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."cmd_lcia_result_build_request_v2_envelope"("p_name" "text", "p_processes" "jsonb", "p_coverage_mode" "text", "p_default_impact_category" "text", "p_lcia_method_set" "jsonb", "p_idempotency_key" "text", "p_closure_check_id" "uuid", "p_requested_scope_hash" "text", "p_policy_fingerprint" "text", "p_audit" "jsonb") TO "api_internal_executor";
