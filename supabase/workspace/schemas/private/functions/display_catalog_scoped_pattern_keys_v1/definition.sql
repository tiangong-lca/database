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
  case p_kind
    when 'process' then v_relation := 'display_catalog_search_rows_v2';
    when 'flow' then v_relation := 'display_catalog_search_rows_v1';
    else raise exception using errcode='22023', message='invalid portal request';
  end case;

  -- Materialize only exact keys, once, with the unchanged LIKE/ESCAPE rule.
  -- 2048 selects a plan shape, never a result limit. Both paths intersect every
  -- returned key with the current deployment/visibility/brand scope.
  return query execute pg_catalog.format($sql$
    with matches as materialized (
      select projection.id, projection.version
      from private.%I as projection
      where projection.dataset_kind = %L
        and projection.document like $1 escape E'\\'
    ), match_count as materialized (select count(*) as n from matches)
    select matched.id, matched.version
    from matches matched
    where (select n from match_count) <= 2048
      and exists (
        select 1 from private.display_request_visible_settings_v1 scope
        where scope.dataset_kind = %L and scope.dataset_id = matched.id
          and scope.dataset_version = matched.version
        offset 0
      )
    union all
    select matched.id, matched.version
    from matches matched
    where (select n from match_count) > 2048
      and exists (
        select 1 from private.display_request_visible_settings_v1 scope
        where scope.dataset_kind = %L and scope.dataset_id = matched.id
          and scope.dataset_version = matched.version
      )
  $sql$, v_relation, p_kind, p_kind, p_kind) using p_like_pattern;
end
$_$;

ALTER FUNCTION "private"."display_catalog_scoped_pattern_keys_v1"("p_kind" "text", "p_like_pattern" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."display_catalog_scoped_pattern_keys_v1"("p_kind" "text", "p_like_pattern" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."display_catalog_scoped_pattern_keys_v1"("p_kind" "text", "p_like_pattern" "text") TO "portal_display_executor";
