CREATE OR REPLACE FUNCTION "api"."cmd_lca_release_readback_verify"("p_release_run_id" "uuid", "p_release_manifest_hash" "text", "p_artifact_hashes" "jsonb", "p_audit" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'api', 'private', 'public', 'util', 'extensions', 'pg_temp'
    AS $$
declare
  v_actor uuid := auth.uid();
  v_run private.lca_release_runs%rowtype;
  v_mismatch_count integer;
  v_now timestamptz := clock_timestamp();
begin
  if v_actor is null then
    return private.lca_release_error('auth_required', 401, 'Authentication required');
  end if;
  if not private.lca_release_is_manager() then
    return private.lca_release_error('not_data_product_manager', 403, 'Data product manager role is required');
  end if;
  if jsonb_typeof(coalesce(p_artifact_hashes, 'null'::jsonb)) <> 'array' then
    return private.lca_release_error('invalid_readback_payload', 400, 'artifactHashes must be a JSON array');
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
  if v_run.status not in ('published', 'readback_verified') then
    return private.lca_release_error('release_not_published', 409, 'Release must be published before readback verification');
  end if;
  if v_run.release_manifest_hash <> p_release_manifest_hash then
    return private.lca_release_error('readback_manifest_hash_mismatch', 409, 'Readback release manifest hash differs from the published value');
  end if;
  if jsonb_array_length(p_artifact_hashes) <> 4 then
    return private.lca_release_error('readback_artifacts_incomplete', 409, 'Readback must verify all four release artifacts');
  end if;

  with expected as (
    select id::text as artifact_id, sha256
    from private.lca_release_artifacts
    where release_run_id = v_run.id
  ),
  observed as (
    select value->>'artifactId' as artifact_id, value->>'sha256' as sha256
    from jsonb_array_elements(p_artifact_hashes)
  )
  select count(*) into v_mismatch_count
  from expected
  full join observed using (artifact_id)
  where expected.artifact_id is null
     or observed.artifact_id is null
     or expected.sha256 is distinct from observed.sha256;

  if v_mismatch_count <> 0 then
    return private.lca_release_error('readback_artifact_hash_mismatch', 409, 'Readback artifact hashes differ from published immutable refs');
  end if;

  update private.lca_release_runs
  set status = 'readback_verified',
      readback_verified_at = coalesce(readback_verified_at, v_now),
      readback_receipt = jsonb_build_object(
        'releaseManifestHash', p_release_manifest_hash,
        'artifactHashes', p_artifact_hashes,
        'verifiedBy', v_actor,
        'verifiedAt', v_now
      ),
      updated_at = v_now
  where id = v_run.id;

  insert into private.command_audit_log (
    command, actor_user_id, target_table, target_id, target_version, payload
  ) values (
    'cmd_lca_release_readback_verify', v_actor, 'lca_release_runs', v_run.id,
    v_run.release_version,
    coalesce(p_audit, '{}'::jsonb) || jsonb_build_object(
      'releaseManifestHash', p_release_manifest_hash,
      'artifactCount', jsonb_array_length(p_artifact_hashes)
    )
  );

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'releaseRunId', v_run.id,
      'status', 'readback_verified',
      'releaseManifestHash', p_release_manifest_hash,
      'verifiedAt', v_now
    )
  );
end;
$$;

ALTER FUNCTION "api"."cmd_lca_release_readback_verify"("p_release_run_id" "uuid", "p_release_manifest_hash" "text", "p_artifact_hashes" "jsonb", "p_audit" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."cmd_lca_release_readback_verify"("p_release_run_id" "uuid", "p_release_manifest_hash" "text", "p_artifact_hashes" "jsonb", "p_audit" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."cmd_lca_release_readback_verify"("p_release_run_id" "uuid", "p_release_manifest_hash" "text", "p_artifact_hashes" "jsonb", "p_audit" "jsonb") TO "api_internal_executor";

GRANT ALL ON FUNCTION "api"."cmd_lca_release_readback_verify"("p_release_run_id" "uuid", "p_release_manifest_hash" "text", "p_artifact_hashes" "jsonb", "p_audit" "jsonb") TO "authenticated";
