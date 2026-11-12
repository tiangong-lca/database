CREATE OR REPLACE FUNCTION "private"."lca_release_guard_publication_update"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'private', 'api', 'public', 'util', 'extensions', 'pg_temp'
    AS $$
begin
  if old.id is distinct from new.id
     or old.release_run_id is distinct from new.release_run_id
     or old.release_version is distinct from new.release_version
     or old.publication_series_key is distinct from new.publication_series_key
     or old.publication_channel is distinct from new.publication_channel
     or old.visibility_scope is distinct from new.visibility_scope
     or old.approval_id is distinct from new.approval_id
     or old.approval_hash is distinct from new.approval_hash
     or old.publish_plan_hash is distinct from new.publish_plan_hash
     or old.release_manifest_hash is distinct from new.release_manifest_hash
     or old.artifact_set_hash is distinct from new.artifact_set_hash
     or old.approved_by is distinct from new.approved_by
     or old.executed_by is distinct from new.executed_by
     or old.credential_fingerprint is distinct from new.credential_fingerprint
     or old.idempotency_key is distinct from new.idempotency_key
     or old.published_at is distinct from new.published_at
     or old.created_at is distinct from new.created_at
     or (not old.is_current and new.is_current)
     or (old.status <> 'current' and old.status is distinct from new.status
       and not (old.status='superseded' and new.status='unpublished' and exists
         (select 1 from private.final_result_publication_bindings where publication_id=old.id)))
     or (old.status = 'current' and new.status not in ('current', 'superseded', 'unpublished')) then
    raise exception 'lca_release_publication_immutable'
      using errcode = '23514';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

ALTER FUNCTION "private"."lca_release_guard_publication_update"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."lca_release_guard_publication_update"() FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."lca_release_guard_publication_update"() TO "api_internal_executor";
