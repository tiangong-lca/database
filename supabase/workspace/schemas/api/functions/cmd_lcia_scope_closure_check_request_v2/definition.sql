CREATE OR REPLACE FUNCTION "api"."cmd_lcia_scope_closure_check_request_v2"("p_requested_scope" "jsonb", "p_request_idempotency_token" "text", "p_audit" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'api', 'private', 'public', 'util', 'extensions', 'pg_temp'
    SET "statement_timeout" TO '60s'
    AS $$
declare
  v_actor uuid := auth.uid();
  v_calculation_fingerprint text;
  v_payload_hash text := private.lcia_scope_closure_sha256(p_requested_scope);
  v_scope jsonb;
  v_policy jsonb;
  v_requested_scope_hash text;
  v_policy_fingerprint text;
  v_expected_validator text;
  v_snapshot_manifest jsonb;
  v_snapshot_token text;
  v_request_fingerprint text;
  v_request_key text;
  v_result jsonb;
  v_check private.lcia_scope_closure_checks%rowtype;
  v_job private.worker_jobs%rowtype;
  v_execution private.lcia_scope_closure_scan_executions%rowtype;
  v_publication private.lca_release_publications%rowtype;
  v_run private.lca_release_runs%rowtype;
  v_dataset_manifest jsonb;
  v_candidate_manifest_hash text;
  v_publication_epoch bigint := 0;
  v_missing_root_count integer;
begin
  if v_actor is null then
    return api.lcia_scope_closure_error(
      'auth_required', 401, 'Authentication required'
    );
  end if;
  if not api.lcia_scope_closure_is_manager() then
    return api.lcia_scope_closure_error(
      'not_data_product_manager', 403, 'Data product manager role is required'
    );
  end if;
  if coalesce(nullif(trim(p_request_idempotency_token), ''), '') = '' then
    return api.lcia_scope_closure_error(
      'invalid_closure_request', 400, 'Idempotency token is required'
    );
  end if;

  -- A retry is the original operation, even after a new calculation contract activates.
  perform pg_advisory_xact_lock(hashtextextended(v_actor::text || ':' || trim(p_request_idempotency_token), 873));
  select * into v_check from private.lcia_scope_closure_checks
    where requested_by=v_actor and request_idempotency_token=trim(p_request_idempotency_token)
    order by created_at, id limit 1 for update;
  if v_check.id is not null then
    if v_check.request_payload_hash is not null and v_check.request_payload_hash is distinct from v_payload_hash then
      return api.lcia_scope_closure_error('idempotency_payload_conflict',409,'Idempotency token belongs to another request');
    end if;
    select * into v_job from private.worker_jobs where id=v_check.worker_job_id;
    return jsonb_build_object('ok',true,'data',jsonb_build_object(
      'closureCheckId',v_check.id,'requestedScopeHash',v_check.requested_scope_hash,
      'policyFingerprint',v_check.policy_fingerprint,'dataSnapshotToken',v_check.data_snapshot_token,
      'scanExecutionId',v_check.scan_execution_id,'calculationFingerprint',v_check.calculation_fingerprint,
      'workerJob',private.worker_job_payload(v_job,false),'reused',true));
  end if;
  select fingerprint into v_calculation_fingerprint
    from private.lca_active_calculation_contract where singleton for share;

  -- Admission can normalize more than once, then freeze the source.
  -- Hold the publication selector stable through all reads, including the
  -- no-current-publication case. Concurrent checks share this lock.
  lock table private.lca_release_publications in share mode;
  v_scope := private.lcia_scope_closure_normalize_request(p_requested_scope);

  if v_scope->>'eligibilityPredicateVersion' = 'current-public-release-manifest:v2' then
    select *
    into v_publication
    from private.lca_release_publications
    where is_current = true and status = 'current'
    order by published_at desc
    limit 1;

    if v_publication.id is null then
      return api.lcia_scope_closure_error(
        'closure_snapshot_source_changed',
        409,
        'The current release changed while the closure snapshot was being frozen; retry the check'
      );
    end if;
    select *
    into v_run
    from private.lca_release_runs
    where id = v_publication.release_run_id;
    if v_run.id is null or v_run.release_manifest_hash is null then
      return api.lcia_scope_closure_error(
        'closure_evidence_unavailable',
        503,
        'Current public release manifest is unavailable'
      );
    end if;
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'datasetType', d.dataset_type,
        'datasetId', d.dataset_uuid,
        'datasetVersion', d.dataset_version,
        'role', d.dataset_role,
        'sourceProcessId', d.source_process_uuid,
        'sourceProcessVersion', d.source_process_version,
        'versionSignificantHash', d.version_significant_hash,
        'semanticHash', d.semantic_hash,
        'canonicalContentHash', d.canonical_content_hash
      )
      order by d.dataset_type, d.dataset_uuid, d.dataset_version, d.dataset_role
    ), '[]'::jsonb)
    into v_dataset_manifest
    from private.lca_release_dataset_versions d
    where d.release_run_id = v_run.id;

    if jsonb_array_length(v_dataset_manifest) = 0 then
      return api.lcia_scope_closure_error(
        'closure_evidence_unavailable',
        503,
        'Current public release dataset manifest is empty'
      );
    end if;

    v_snapshot_manifest := jsonb_build_object(
      'schemaVersion', 'lcia.scope-closure-data-snapshot.v2',
      'requestedScope', v_scope,
      'currentPublicRelease', jsonb_build_object(
        'publicationId', v_publication.id,
        'releaseRunId', v_run.id,
        'releaseVersion', v_run.release_version,
        'publishedAt', v_publication.published_at,
        'releaseManifestHash', v_run.release_manifest_hash
      ),
      'datasets', v_dataset_manifest
    );
    v_publication_epoch := extract(epoch from v_publication.published_at)::bigint;
  else
    if v_scope->>'certificateFreshnessPolicy' = 'current-membership-required-v1' then
      return api.lcia_scope_closure_error(
        'current_release_required',
        409,
        'Current-membership freshness requires a current formal release'
      );
    end if;

    v_dataset_manifest :=
      private.lcia_scope_closure_candidate_dataset_manifest();
    if jsonb_array_length(v_dataset_manifest) = 0 then
      return api.lcia_scope_closure_error(
        'closure_evidence_unavailable',
        503,
        'Candidate public-state dataset manifest is empty'
      );
    end if;

    with roots as (
      select 'processes'::text as dataset_type,
        (item.value->>'id')::uuid as dataset_id,
        item.value->>'version' as dataset_version
      from jsonb_array_elements(v_scope->'processes') item(value)
      union all
      select 'lciamethods',
        (item.value->>'id')::uuid,
        item.value->>'version'
      from jsonb_array_elements(v_scope->'lciaMethods') item(value)
    ),
    frozen as (
      select item.value->>'datasetType' as dataset_type,
        (item.value->>'datasetId')::uuid as dataset_id,
        item.value->>'datasetVersion' as dataset_version
      from jsonb_array_elements(v_dataset_manifest) item(value)
    )
    select count(*)
    into v_missing_root_count
    from roots r
    left join frozen f using (dataset_type, dataset_id, dataset_version)
    where f.dataset_id is null;

    if v_missing_root_count <> 0 then
      return api.lcia_scope_closure_error(
        'closure_snapshot_source_changed',
        409,
        'Candidate data changed while the closure snapshot was being frozen; retry the check'
      );
    end if;

    v_candidate_manifest_hash := private.lcia_scope_closure_sha256(
      jsonb_build_object(
        'eligibilityPredicateVersion',
          v_scope->>'eligibilityPredicateVersion',
        'datasets', v_dataset_manifest
      )
    );
    v_snapshot_manifest := jsonb_build_object(
      'schemaVersion', 'lcia.scope-closure-data-snapshot.v2',
      'requestedScope', v_scope,
      -- Required only for deployed Worker v2 compatibility.  candidateData
      -- below is the authoritative source description.
      'currentPublicRelease', jsonb_build_object(
        'publicationId', '00000000-0000-0000-0000-000000000000',
        'releaseRunId', '00000000-0000-0000-0000-000000000000',
        'releaseVersion', 'candidate-public-state-v1',
        'publishedAt', '1970-01-01T00:00:00Z',
        'releaseManifestHash', v_candidate_manifest_hash
      ),
      'candidateData', jsonb_build_object(
        'sourceKind', 'candidate-public-state',
        'eligibilityPredicateVersion',
          v_scope->>'eligibilityPredicateVersion',
        'datasetManifestHash', v_candidate_manifest_hash,
        'workerV2CompatibilityProjection', true
      ),
      'datasets', v_dataset_manifest
    );
  end if;

  v_snapshot_token := private.lcia_scope_closure_sha256(v_snapshot_manifest);
  v_requested_scope_hash := private.lcia_scope_closure_sha256(v_scope);
  v_policy := jsonb_build_object(
    'scopePolicy', v_scope - 'processes' - 'lciaMethods' - 'processManifestHash',
    'visibilityScope', 'data_product_manager.v1'
  );
  v_policy_fingerprint := private.lcia_scope_closure_sha256(v_policy);
  select expected_validator_scanner_fingerprint
  into v_expected_validator
  from private.lcia_scope_closure_config
  where singleton;
  if v_expected_validator is null then
    return api.lcia_scope_closure_error(
      'closure_evidence_unavailable',
      503,
      'Closure validator configuration is unavailable'
    );
  end if;

  v_request_fingerprint := encode(extensions.digest(
    v_requested_scope_hash || '|' || v_policy_fingerprint || '|'
      || v_expected_validator || '|' || v_snapshot_token
      || case when v_calculation_fingerprint is null then '' else '|calculation:' || v_calculation_fingerprint end,
    'sha256'
  ), 'hex');
  v_request_key := encode(extensions.digest(
    v_actor::text || '|' || trim(p_request_idempotency_token) || '|'
      || v_request_fingerprint,
    'sha256'
  ), 'hex');

  select *
  into v_check
  from private.lcia_scope_closure_checks
  where requested_by = v_actor and request_key = v_request_key
  for update;
  if v_check.id is not null then
    select * into v_job from private.worker_jobs where id = v_check.worker_job_id;
    return jsonb_build_object(
      'ok', true,
      'data', jsonb_build_object(
        'closureCheckId', v_check.id,
        'requestedScopeHash', v_check.requested_scope_hash,
        'policyFingerprint', v_check.policy_fingerprint,
        'dataSnapshotToken', v_check.data_snapshot_token,
        'scanExecutionId', v_check.scan_execution_id,
        'workerJob', private.worker_job_payload(v_job, false),
        'reused', true
      )
    );
  end if;

  v_result := private.cmd_lcia_scope_closure_check_request_v2_untracked(
    p_requested_scope,
    p_request_idempotency_token,
    p_audit
  );
  if coalesce((v_result->>'ok')::boolean, false) is not true then
    return v_result;
  end if;
  select *
  into v_check
  from private.lcia_scope_closure_checks
  where id = nullif(v_result->'data'->>'closureCheckId', '')::uuid
  for update;
  if v_check.id is null then
    return api.lcia_scope_closure_error(
      'closure_check_not_found', 404, 'Closure check not found'
    );
  end if;
  if coalesce((v_result->'data'->>'reused')::boolean, false)
     and v_check.request_key <> v_request_key
     and v_check.data_snapshot_token <> v_snapshot_token then
    return api.lcia_scope_closure_error(
      'idempotency_token_bound_to_different_snapshot',
      409,
      'Idempotency token is already bound to a different data snapshot'
    );
  end if;

  insert into private.lcia_scope_closure_data_snapshots(
    data_snapshot_token,
    root_manifest,
    root_manifest_hash,
    publication_epoch
  ) values (
    v_snapshot_token,
    v_snapshot_manifest,
    private.lcia_scope_closure_sha256(v_snapshot_manifest),
    v_publication_epoch
  )
  on conflict (data_snapshot_token) do nothing;

  update private.lcia_scope_closure_checks
  set data_snapshot_token = v_snapshot_token,
      requested_scope_manifest = v_scope,
      requested_scope_hash = v_requested_scope_hash,
      policy_fingerprint = v_policy_fingerprint,
      request_fingerprint = v_request_fingerprint,
      request_key = v_request_key,
      calculation_fingerprint = v_calculation_fingerprint,
      request_payload_hash = v_payload_hash,
      updated_at = now()
  where id = v_check.id
  returning * into v_check;

  perform pg_advisory_xact_lock(hashtextextended(v_request_fingerprint, 873));
  select *
  into v_execution
  from private.lcia_scope_closure_scan_executions
  where request_fingerprint = v_request_fingerprint
  for update;
  if v_execution.id is null then
    insert into private.lcia_scope_closure_scan_executions(
      request_fingerprint,
      requested_scope_hash,
      policy_fingerprint,
      data_snapshot_token,
      validator_scanner_fingerprint,
      calculation_fingerprint
    ) values (
      v_request_fingerprint,
      v_requested_scope_hash,
      v_policy_fingerprint,
      v_snapshot_token,
      v_expected_validator,
      v_calculation_fingerprint
    )
    returning * into v_execution;
  end if;

  update private.lcia_scope_closure_checks
  set scan_execution_id = v_execution.id,
      updated_at = now()
  where id = v_check.id
  returning * into v_check;

  update private.worker_jobs
  set request_hash = v_request_fingerprint,
      concurrency_key = v_request_key,
      payload_json = payload_json || jsonb_build_object(
        'coverage_mode', v_scope->>'coverageMode',
        'input_manifest', jsonb_build_object(
          'predicateVersion', v_scope->>'eligibilityPredicateVersion',
          'selectionMode', 'closure_certificate',
          'processes', v_scope->'processes'
        ),
        'input_manifest_hash',
          private.lcia_scope_closure_sha256(
            jsonb_build_object('processes', v_scope->'processes')
          ),
        'lcia_method_set', v_scope->'lciaMethods',
        'request_fingerprint', v_request_fingerprint,
        'calculation_fingerprint', v_calculation_fingerprint,
        'scan_execution_id', v_execution.id,
        'data_snapshot_token', v_snapshot_token
      ),
      updated_at = now()
  where id = v_check.worker_job_id
  returning * into v_job;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'closureCheckId', v_check.id,
      'requestedScopeHash', v_check.requested_scope_hash,
      'policyFingerprint', v_check.policy_fingerprint,
      'dataSnapshotToken', v_snapshot_token,
      'scanExecutionId', v_execution.id,
      'calculationFingerprint', v_calculation_fingerprint,
      'workerJob', private.worker_job_payload(v_job, false),
      'reused', false
    )
  );
exception
  when sqlstate '22023' then
    return api.lcia_scope_closure_error(
      'invalid_closure_scope', 400, sqlerrm
    );
end;
$$;

ALTER FUNCTION "api"."cmd_lcia_scope_closure_check_request_v2"("p_requested_scope" "jsonb", "p_request_idempotency_token" "text", "p_audit" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."cmd_lcia_scope_closure_check_request_v2"("p_requested_scope" "jsonb", "p_request_idempotency_token" "text", "p_audit" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."cmd_lcia_scope_closure_check_request_v2"("p_requested_scope" "jsonb", "p_request_idempotency_token" "text", "p_audit" "jsonb") TO "api_internal_executor";

GRANT ALL ON FUNCTION "api"."cmd_lcia_scope_closure_check_request_v2"("p_requested_scope" "jsonb", "p_request_idempotency_token" "text", "p_audit" "jsonb") TO "authenticated";
