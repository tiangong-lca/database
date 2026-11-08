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
