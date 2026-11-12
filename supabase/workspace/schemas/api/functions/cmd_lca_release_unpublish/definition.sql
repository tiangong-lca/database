CREATE OR REPLACE FUNCTION "api"."cmd_lca_release_unpublish"("p_publication_id" "uuid", "p_reason" "text", "p_audit" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'api', 'private', 'public', 'util', 'extensions', 'pg_temp'
    AS $$
declare
  v_actor uuid := auth.uid();
  v_publication private.lca_release_publications%rowtype;
  v_now timestamptz := clock_timestamp();
begin
  if v_actor is null then
    return private.lca_release_error('auth_required', 401, 'Authentication required');
  end if;
  if not private.lca_release_is_manager() then
    return private.lca_release_error('not_data_product_manager', 403, 'Data product manager role is required');
  end if;
  if nullif(trim(coalesce(p_reason, '')), '') is null then
    return private.lca_release_error('reason_required', 400, 'Unpublish requires an audit reason');
  end if;

  select * into v_publication
  from private.lca_release_publications
  where id = p_publication_id
  for update;

  if v_publication.id is null then
    return private.lca_release_error('publication_not_found', 404, 'Publication not found');
  end if;
  if v_publication.status = 'unpublished' then
    return jsonb_build_object(
      'ok', true,
      'reused', true,
      'data', jsonb_build_object('publicationId', v_publication.id, 'status', 'unpublished')
    );
  end if;
  if not ((v_publication.is_current and v_publication.status = 'current') or
    (v_publication.status = 'superseded' and exists(select 1 from private.final_result_publication_bindings where publication_id=v_publication.id))) then
    return private.lca_release_error('publication_not_current', 409, 'Publication cannot be withdrawn');
  end if;

  update private.lca_release_publications
  set status = 'unpublished', is_current = false, unpublished_by = v_actor,
      unpublished_at = v_now, reason = p_reason, updated_at = v_now
  where id = v_publication.id;

  update private.lca_release_runs
  set status = 'unpublished', updated_at = v_now
  where id = v_publication.release_run_id;

  insert into private.command_audit_log (
    command, actor_user_id, target_table, target_id, target_version, payload
  ) values (
    'cmd_lca_release_unpublish', v_actor, 'lca_release_publications',
    v_publication.id, v_publication.release_version,
    coalesce(p_audit, '{}'::jsonb) || jsonb_build_object('reason', p_reason)
  );

  return jsonb_build_object(
    'ok', true,
    'reused', false,
    'data', jsonb_build_object('publicationId', v_publication.id, 'status', 'unpublished')
  );
end;
$$;

ALTER FUNCTION "api"."cmd_lca_release_unpublish"("p_publication_id" "uuid", "p_reason" "text", "p_audit" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."cmd_lca_release_unpublish"("p_publication_id" "uuid", "p_reason" "text", "p_audit" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."cmd_lca_release_unpublish"("p_publication_id" "uuid", "p_reason" "text", "p_audit" "jsonb") TO "api_internal_executor";

GRANT ALL ON FUNCTION "api"."cmd_lca_release_unpublish"("p_publication_id" "uuid", "p_reason" "text", "p_audit" "jsonb") TO "authenticated";
