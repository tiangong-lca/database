CREATE OR REPLACE FUNCTION "private"."cmd_lca_release_artifacts_finalize_service"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_release_manifest" "jsonb", "p_release_manifest_hash" "text", "p_artifacts" "jsonb", "p_audit" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'private', 'api', 'public', 'util', 'extensions', 'pg_temp'
    AS $_$
declare
  v_run private.lca_release_runs%rowtype;
  v_invalid_count integer;
  v_dataset_count integer;
  v_artifact_count integer;
begin
  if not private.lca_release_is_service_request() then
    return private.lca_release_error('service_role_required', 403, 'Internal service identity is required to finalize artifacts');
  end if;
  if jsonb_typeof(coalesce(p_release_manifest, 'null'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_artifacts, 'null'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_audit, 'null'::jsonb)) <> 'object' then
    return private.lca_release_error('invalid_payload', 400, 'Release manifest, artifacts, and audit have invalid JSON shapes');
  end if;
  if coalesce(p_publish_plan_hash, '') !~ '^[0-9a-f]{64}$'
     or coalesce(p_release_manifest_hash, '') !~ '^[0-9a-f]{64}$' then
    return private.lca_release_error('invalid_hash', 400, 'Plan and release manifest hashes must be lowercase SHA-256 values');
  end if;

  select * into v_run
  from private.lca_release_runs
  where id = p_release_run_id
  for update;

  if v_run.id is null then
    return private.lca_release_error('release_run_not_found', 404, 'Release run not found');
  end if;
  if v_run.publication_format<>'legacy-four-zip.v1' then
    return private.lca_release_error('final_result_versioned_api_required',409,'Use the explicit final Result release API');
  end if;
  if v_run.publish_plan_hash <> p_publish_plan_hash then
    return private.lca_release_error('publish_plan_hash_mismatch', 409, 'Artifact finalize plan hash does not match the prepared run');
  end if;
  if v_run.status <> 'prepared' then
    if v_run.status in ('ready_for_approval', 'approved', 'published', 'readback_verified')
       and v_run.release_manifest_hash = p_release_manifest_hash then
      with existing as (
        select profile_id, artifact_format, storage_bucket, object_key, sha256, byte_size, media_type
        from private.lca_release_artifacts
        where release_run_id = v_run.id
      ),
      supplied as (
        select
          artifact.value->>'profileId' as profile_id,
          artifact.value->>'format' as artifact_format,
          artifact.value->>'storageBucket' as storage_bucket,
          artifact.value->>'objectKey' as object_key,
          artifact.value->>'sha256' as sha256,
          (artifact.value->>'byteSize')::bigint as byte_size,
          artifact.value->>'mediaType' as media_type
        from jsonb_array_elements(p_artifacts) as artifact(value)
      )
      select count(*) into v_invalid_count
      from existing
      full join supplied using (profile_id, artifact_format)
      where existing.profile_id is null
         or supplied.profile_id is null
         or existing.storage_bucket is distinct from supplied.storage_bucket
         or existing.object_key is distinct from supplied.object_key
         or existing.sha256 is distinct from supplied.sha256
         or existing.byte_size is distinct from supplied.byte_size
         or existing.media_type is distinct from supplied.media_type;

      if v_invalid_count = 0 and jsonb_array_length(p_artifacts) = 4 then
        return jsonb_build_object(
          'ok', true,
          'reused', true,
          'data', jsonb_build_object(
            'releaseRunId', v_run.id,
            'status', v_run.status,
            'releaseManifestHash', v_run.release_manifest_hash
          )
        );
      end if;
      return private.lca_release_error('release_finalize_conflict', 409, 'Finalize retry artifact refs differ from durable content');
    end if;
    return private.lca_release_error('release_state_conflict', 409, 'Release run is not in prepared state');
  end if;

  if p_release_manifest->>'schemaVersion' is distinct from 'tiangong.release-manifest.v1'
     or p_release_manifest->>'releaseRunId' is distinct from v_run.id::text
     or p_release_manifest->>'releaseVersion' is distinct from v_run.release_version
     or p_release_manifest->>'profileLockHash' is distinct from v_run.profile_lock_hash
     or p_release_manifest->>'publishPlanHash' is distinct from v_run.publish_plan_hash
     or p_release_manifest->>'artifactSetHash' is distinct from v_run.artifact_set_hash
     or p_release_manifest->'scope'->>'coverageMode' is distinct from 'global_eligible'
     or p_release_manifest->'scope'->>'selectionManifestHash' is distinct from v_run.selection_manifest_hash
     or p_release_manifest->'calculationBundle'->>'bundleContentHash' is distinct from v_run.calculation_bundle_hash then
    return private.lca_release_error('release_manifest_mismatch', 409, 'Release manifest does not match the prepared run and exact hashes');
  end if;
  if jsonb_typeof(p_release_manifest->'datasets') is distinct from 'array'
     or jsonb_array_length(p_release_manifest->'datasets') = 0
     or jsonb_typeof(p_release_manifest->'packages') is distinct from 'array'
     or jsonb_array_length(p_release_manifest->'packages') <> 4
     or jsonb_array_length(p_artifacts) <> 4 then
    return private.lca_release_error('release_manifest_incomplete', 400, 'Release manifest requires datasets and four uploaded package artifacts');
  end if;
  if coalesce(
    p_release_manifest->'validation'->'tidas'->>'status' = 'passed'
    and p_release_manifest->'validation'->'ilcd'->>'status' = 'passed'
    and p_release_manifest->'validation'->'semanticRoundtrip'->>'status' = 'passed'
    and p_release_manifest->'validation'->'referenceClosure'->>'status' = 'passed'
    and p_release_manifest->'validation'->'numericParity'->>'status' = 'passed',
    false
  ) is not true then
    return private.lca_release_error('validation_not_passed', 400, 'All release validation gates must pass before artifact finalization');
  end if;

  with expected as (
    select
      package.value->>'profileId' as profile_id,
      package.value->>'format' as artifact_format,
      package.value->>'closureHash' as closure_hash,
      package.value->'artifact'->>'sha256' as sha256,
      (package.value->'artifact'->>'byteSize')::bigint as byte_size,
      package.value->'artifact'->>'mediaType' as media_type
    from jsonb_array_elements(p_release_manifest->'packages') as package(value)
  ),
  uploaded as (
    select
      artifact.value->>'profileId' as profile_id,
      artifact.value->>'format' as artifact_format,
      artifact.value->>'storageBucket' as storage_bucket,
      artifact.value->>'objectKey' as object_key,
      artifact.value->>'sha256' as sha256,
      (artifact.value->>'byteSize')::bigint as byte_size,
      artifact.value->>'mediaType' as media_type
    from jsonb_array_elements(p_artifacts) as artifact(value)
  )
  select count(*) into v_invalid_count
  from expected
  full join uploaded using (profile_id, artifact_format)
  where expected.profile_id is null
     or uploaded.profile_id is null
     or expected.profile_id not in (
          'unit-process-full-closure.v1',
          'standalone-lifecyclemodel-result-full-closure.v1'
        )
     or expected.artifact_format not in ('tidas', 'ilcd')
     or expected.sha256 !~ '^[0-9a-f]{64}$'
     or expected.closure_hash !~ '^[0-9a-f]{64}$'
     or expected.sha256 is distinct from uploaded.sha256
     or expected.byte_size is distinct from uploaded.byte_size
     or expected.media_type is distinct from uploaded.media_type
     or coalesce(length(trim(uploaded.storage_bucket)), 0) = 0
     or coalesce(length(trim(uploaded.object_key)), 0) = 0;

  if v_invalid_count <> 0 then
    return private.lca_release_error('artifact_set_mismatch', 409, 'Uploaded artifact refs do not exactly match the release manifest');
  end if;

  with dataset_rows as (
    select dataset.value
    from jsonb_array_elements(p_release_manifest->'datasets') as dataset(value)
  )
  select count(*) into v_invalid_count
  from dataset_rows
  where value->>'datasetType' not in (
          'process', 'lifecyclemodel', 'flow', 'flowproperty', 'unitgroup',
          'lciamethod', 'source', 'contact'
        )
     or value->>'role' not in ('unit_process', 'result_process', 'lifecycle_model', 'support')
     or (value->>'role' in ('unit_process', 'result_process') and value->>'datasetType' <> 'process')
     or (value->>'role' = 'lifecycle_model' and value->>'datasetType' <> 'lifecyclemodel')
     or value->>'version' !~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$'
     or (
       value->>'role' in ('unit_process', 'result_process', 'lifecycle_model')
       and (
         jsonb_typeof(value->'sourceProcess') is distinct from 'object'
         or coalesce(value->'sourceProcess'->>'id', '') = ''
         or value->'sourceProcess'->>'version' !~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$'
       )
     )
     or (
       value->>'role' = 'unit_process'
       and (
         value->'sourceProcess'->>'id' is distinct from value->>'uuid'
         or value->'sourceProcess'->>'version' is distinct from value->>'version'
       )
     )
     or (
       value->>'role' = 'support'
       and value ? 'sourceProcess'
     )
     or value->>'versionSignificantHash' !~ '^[0-9a-f]{64}$'
     or value->>'semanticHash' !~ '^[0-9a-f]{64}$'
     or value->>'canonicalContentHash' !~ '^[0-9a-f]{64}$'
     or jsonb_typeof(value->'artifact') is distinct from 'object';

  if v_invalid_count <> 0 then
    return private.lca_release_error('dataset_index_invalid', 400, 'Release dataset index contains invalid identities, versions, or hashes');
  end if;

  with process_datasets as (
    select
      dataset.value->>'role' as dataset_role,
      dataset.value->'sourceProcess'->>'id' as source_process_uuid,
      dataset.value->'sourceProcess'->>'version' as source_process_version
    from jsonb_array_elements(p_release_manifest->'datasets') as dataset(value)
    where dataset.value->>'role' in ('unit_process', 'lifecycle_model', 'result_process')
  ),
  invalid_source_sets as (
    select source_process_uuid, source_process_version
    from process_datasets
    group by source_process_uuid, source_process_version
    having count(*) filter (where dataset_role = 'unit_process') <> 1
       or count(*) filter (where dataset_role = 'lifecycle_model') <> 1
       or count(*) filter (where dataset_role = 'result_process') <> 1
  )
  select count(*) into v_invalid_count
  from invalid_source_sets;

  if v_invalid_count <> 0 then
    return private.lca_release_error(
      'dataset_source_process_set_invalid', 400,
      'Each source Process requires exactly one Unit Process, LifecycleModel, and Result Process identity'
    );
  end if;

  insert into private.lca_release_dataset_versions (
    release_run_id, dataset_type, dataset_role, dataset_uuid, dataset_version,
    source_process_uuid, source_process_version,
    version_significant_hash, semantic_hash, canonical_content_hash, artifact_ref
  )
  select
    v_run.id,
    dataset.value->>'datasetType',
    dataset.value->>'role',
    (dataset.value->>'uuid')::uuid,
    dataset.value->>'version',
    (dataset.value->'sourceProcess'->>'id')::uuid,
    dataset.value->'sourceProcess'->>'version',
    dataset.value->>'versionSignificantHash',
    dataset.value->>'semanticHash',
    dataset.value->>'canonicalContentHash',
    dataset.value->'artifact'
  from jsonb_array_elements(p_release_manifest->'datasets') as dataset(value);
  get diagnostics v_dataset_count = row_count;

  insert into private.lca_release_artifacts (
    release_run_id, profile_id, artifact_format, storage_bucket, object_key,
    sha256, byte_size, media_type, closure_hash, verified_at
  )
  select
    v_run.id,
    package.value->>'profileId',
    package.value->>'format',
    artifact.value->>'storageBucket',
    artifact.value->>'objectKey',
    artifact.value->>'sha256',
    (artifact.value->>'byteSize')::bigint,
    artifact.value->>'mediaType',
    package.value->>'closureHash',
    now()
  from jsonb_array_elements(p_release_manifest->'packages') as package(value)
  join jsonb_array_elements(p_artifacts) as artifact(value)
    on artifact.value->>'profileId' = package.value->>'profileId'
   and artifact.value->>'format' = package.value->>'format';
  get diagnostics v_artifact_count = row_count;

  update private.lca_release_runs
  set release_manifest = p_release_manifest,
      release_manifest_hash = p_release_manifest_hash,
      status = 'ready_for_approval',
      artifacts_finalized_at = now(),
      updated_at = now()
  where id = v_run.id;

  insert into private.command_audit_log (
    command, actor_user_id, target_table, target_id, target_version, payload
  ) values (
    'cmd_lca_release_artifacts_finalize_service', v_run.created_by,
    'lca_release_runs', v_run.id, v_run.release_version,
    coalesce(p_audit, '{}'::jsonb) || jsonb_build_object(
      'serviceCallback', true,
      'publishPlanHash', p_publish_plan_hash,
      'releaseManifestHash', p_release_manifest_hash,
      'artifactSetHash', v_run.artifact_set_hash,
      'artifactCount', v_artifact_count,
      'datasetCount', v_dataset_count
    )
  );

  return jsonb_build_object(
    'ok', true,
    'reused', false,
    'data', jsonb_build_object(
      'releaseRunId', v_run.id,
      'status', 'ready_for_approval',
      'releaseManifestHash', p_release_manifest_hash,
      'artifactCount', v_artifact_count,
      'datasetCount', v_dataset_count
    )
  );
exception
  when invalid_text_representation or numeric_value_out_of_range then
    return private.lca_release_error('release_manifest_invalid', 400, 'Release manifest contains invalid UUID or byte-size values');
  when unique_violation then
    return private.lca_release_error('release_artifact_conflict', 409, 'Release dataset or artifact identity already exists with conflicting content');
end;
$_$;

ALTER FUNCTION "private"."cmd_lca_release_artifacts_finalize_service"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_release_manifest" "jsonb", "p_release_manifest_hash" "text", "p_artifacts" "jsonb", "p_audit" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."cmd_lca_release_artifacts_finalize_service"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_release_manifest" "jsonb", "p_release_manifest_hash" "text", "p_artifacts" "jsonb", "p_audit" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."cmd_lca_release_artifacts_finalize_service"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_release_manifest" "jsonb", "p_release_manifest_hash" "text", "p_artifacts" "jsonb", "p_audit" "jsonb") TO "service_role";

GRANT ALL ON FUNCTION "private"."cmd_lca_release_artifacts_finalize_service"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_release_manifest" "jsonb", "p_release_manifest_hash" "text", "p_artifacts" "jsonb", "p_audit" "jsonb") TO "api_internal_executor";
