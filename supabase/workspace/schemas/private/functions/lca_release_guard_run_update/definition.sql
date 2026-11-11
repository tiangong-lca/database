CREATE OR REPLACE FUNCTION "private"."lca_release_guard_run_update"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'private', 'api', 'public', 'util', 'extensions', 'pg_temp'
    AS $$
begin
  if old.publication_format is distinct from new.publication_format
     or old.id is distinct from new.id
     or old.release_version is distinct from new.release_version
     or old.scope_mode is distinct from new.scope_mode
     or old.selection_manifest_hash is distinct from new.selection_manifest_hash
     or old.input_manifest_hash is distinct from new.input_manifest_hash
     or old.calculation_bundle_hash is distinct from new.calculation_bundle_hash
     or old.calculation_bundle_ref is distinct from new.calculation_bundle_ref
     or old.profile_lock_hash is distinct from new.profile_lock_hash
     or old.publish_plan_hash is distinct from new.publish_plan_hash
     or old.publish_plan is distinct from new.publish_plan
     or old.artifact_set_hash is distinct from new.artifact_set_hash
     or old.idempotency_key is distinct from new.idempotency_key
     or old.request_hash is distinct from new.request_hash
     or old.created_by is distinct from new.created_by
     or old.created_at is distinct from new.created_at then
    raise exception 'lca_release_run_immutable_content'
      using errcode = '23514';
  end if;

  if old.release_manifest_hash is not null
     and (
       old.release_manifest_hash is distinct from new.release_manifest_hash
       or old.release_manifest is distinct from new.release_manifest
       or old.artifacts_finalized_at is distinct from new.artifacts_finalized_at
     ) then
    raise exception 'lca_release_manifest_immutable'
      using errcode = '23514';
  end if;

  if old.status is distinct from new.status
     and not (
       (old.status = 'prepared' and new.status in ('ready_for_approval', 'failed', 'abandoned'))
       or (old.status = 'ready_for_approval' and new.status in ('approved', 'failed', 'abandoned'))
       or (old.status = 'approved' and new.status in ('published', 'failed', 'abandoned'))
       or (old.publication_format='final-result-pair.v2' and old.status='failed' and new.status='abandoned' and new.replaced_by_run_id is not null)
       or (old.status = 'published' and new.status in ('readback_verified', 'unpublished'))
       or (old.status = 'readback_verified' and new.status = 'unpublished')
     ) then
    raise exception 'lca_release_state_transition_invalid:%->%', old.status, new.status
      using errcode = '23514';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

ALTER FUNCTION "private"."lca_release_guard_run_update"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."lca_release_guard_run_update"() FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."lca_release_guard_run_update"() TO "api_internal_executor";
