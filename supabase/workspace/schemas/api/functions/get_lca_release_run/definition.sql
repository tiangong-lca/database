CREATE OR REPLACE FUNCTION "api"."get_lca_release_run"("p_release_run_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'api', 'private', 'public', 'util', 'extensions', 'pg_temp'
    AS $$
declare
  v_run private.lca_release_runs%rowtype;
  v_is_public boolean;
begin
  select * into v_run
  from private.lca_release_runs
  where id = p_release_run_id;

  if v_run.id is null then
    return private.lca_release_error('release_run_not_found', 404, 'Release run not found');
  end if;
  select exists (
    select 1 from private.lca_release_publications
    where release_run_id = v_run.id and status in ('current', 'superseded')
  ) into v_is_public;

  if not v_is_public and not private.lca_release_is_manager() then
    return private.lca_release_error('not_data_product_manager', 403, 'Data product manager role is required for private release runs');
  end if;

  if v_run.publication_format<>'legacy-four-zip.v1' then
    return private.lca_release_error('final_result_versioned_api_required',409,'Use the explicit final Result release API');
  end if;
  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'releaseRunId', v_run.id,
      'releaseVersion', v_run.release_version,
      'status', v_run.status,
      'scopeMode', v_run.scope_mode,
      'selectionManifestHash', v_run.selection_manifest_hash,
      'inputManifestHash', v_run.input_manifest_hash,
      'calculationBundleHash', v_run.calculation_bundle_hash,
      'publishPlanHash', v_run.publish_plan_hash,
      'releaseManifestHash', v_run.release_manifest_hash,
      'artifactSetHash', v_run.artifact_set_hash,
      'createdBy', case when private.lca_release_is_manager() then v_run.created_by else null end,
      'createdAt', v_run.created_at,
      'approvedAt', v_run.approved_at,
      'publishedAt', v_run.published_at,
      'readbackVerifiedAt', v_run.readback_verified_at,
      'calculationBundle', case when private.lca_release_is_manager() then v_run.calculation_bundle_ref else null end,
      'datasetCounts', (
        select coalesce(jsonb_object_agg(counts.dataset_role, counts.dataset_count), '{}'::jsonb)
        from (
          select dataset.dataset_role, count(*) as dataset_count
          from private.lca_release_dataset_versions as dataset
          where dataset.release_run_id = v_run.id
          group by dataset.dataset_role
        ) as counts
      ),
      'validation', jsonb_build_object(
        'tidas', v_run.release_manifest->'validation'->'tidas'->>'status',
        'ilcd', v_run.release_manifest->'validation'->'ilcd'->>'status',
        'semanticRoundtrip', v_run.release_manifest->'validation'->'semanticRoundtrip'->>'status',
        'referenceClosure', v_run.release_manifest->'validation'->'referenceClosure'->>'status',
        'numericParity', v_run.release_manifest->'validation'->'numericParity'->>'status'
      ),
      'publication', (
        select jsonb_build_object(
          'publicationId', publication.id,
          'status', publication.status,
          'isCurrent', publication.is_current,
          'publishedAt', publication.published_at,
          'unpublishedAt', publication.unpublished_at
        )
        from private.lca_release_publications as publication
        where publication.release_run_id = v_run.id
        order by publication.published_at desc
        limit 1
      ),
      'artifacts', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'artifactId', artifact.id,
          'profileId', artifact.profile_id,
          'format', artifact.artifact_format,
          'sha256', artifact.sha256,
          'byteSize', artifact.byte_size,
          'mediaType', artifact.media_type,
          'pinned', artifact.pinned
        ) order by artifact.profile_id, artifact.artifact_format), '[]'::jsonb)
        from private.lca_release_artifacts as artifact
        where artifact.release_run_id = v_run.id
      ),
      'blockers', case
        when v_run.status = 'prepared' then jsonb_build_array('artifacts_not_finalized')
        when v_run.status = 'ready_for_approval' then jsonb_build_array('approval_required')
        when v_run.status = 'approved' then jsonb_build_array('publish_required')
        when v_run.status = 'published' then jsonb_build_array('readback_verification_required')
        else '[]'::jsonb
      end
    )
  );
end;
$$;

ALTER FUNCTION "api"."get_lca_release_run"("p_release_run_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."get_lca_release_run"("p_release_run_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."get_lca_release_run"("p_release_run_id" "uuid") TO "api_internal_executor";

GRANT ALL ON FUNCTION "api"."get_lca_release_run"("p_release_run_id" "uuid") TO "authenticated";

GRANT ALL ON FUNCTION "api"."get_lca_release_run"("p_release_run_id" "uuid") TO "service_role";
