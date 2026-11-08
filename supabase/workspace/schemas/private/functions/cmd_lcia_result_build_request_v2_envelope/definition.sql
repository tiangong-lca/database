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
