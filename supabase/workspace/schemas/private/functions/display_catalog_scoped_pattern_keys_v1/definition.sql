CREATE OR REPLACE FUNCTION "private"."display_catalog_scoped_pattern_keys_v1"("p_kind" "text", "p_like_pattern" "text") RETURNS TABLE("id" "uuid", "version" "text")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER PARALLEL RESTRICTED
    SET "search_path" TO ''
    SET "statement_timeout" TO '20s'
    SET "plan_cache_mode" TO 'force_custom_plan'
    SET "row_security" TO 'on'
    AS $_$
declare
  v_relation text;
begin
  -- Relation names come only from this allowlist, never from caller input.
  case p_kind
    when 'process' then v_relation := 'display_catalog_search_rows_v2';
    when 'flow' then v_relation := 'display_catalog_search_rows_v1';
    else raise exception using errcode='22023', message='invalid portal request';
  end case;

  -- Use the identical LIKE/ESCAPE contract. The explicit scope intersection
  -- precedes every returned key, latest/rank/count/page operation. There is no
  -- candidate cap, cached visibility, caller-provided SQL or payload output.
  return query execute pg_catalog.format($sql$
    select projection.id, projection.version
    from private.%I as projection
    where projection.dataset_kind = %L
      and projection.document like $1 escape E'\\'
      and exists (
        select 1 from private.display_request_visible_settings_v1 as scope
        where scope.dataset_kind = projection.dataset_kind
          and scope.dataset_id = projection.id
          and scope.dataset_version = projection.version
      )
  $sql$, v_relation, p_kind) using p_like_pattern;
end
$_$;

ALTER FUNCTION "private"."display_catalog_scoped_pattern_keys_v1"("p_kind" "text", "p_like_pattern" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."display_catalog_scoped_pattern_keys_v1"("p_kind" "text", "p_like_pattern" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."display_catalog_scoped_pattern_keys_v1"("p_kind" "text", "p_like_pattern" "text") TO "portal_display_executor";
