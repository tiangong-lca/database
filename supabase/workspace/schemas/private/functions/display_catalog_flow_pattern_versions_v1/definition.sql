CREATE OR REPLACE FUNCTION "private"."display_catalog_flow_pattern_versions_v1"("p_like_pattern" "text") RETURNS TABLE("id" "uuid", "version" "text")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER PARALLEL RESTRICTED
    SET "search_path" TO ''
    SET "statement_timeout" TO '20s'
    SET "plan_cache_mode" TO 'force_custom_plan'
    SET "row_security" TO 'on'
    AS $$
declare v_literal text;
begin
  if pg_catalog.char_length(p_like_pattern) = 3
     and pg_catalog.left(p_like_pattern, 1) = '%'
     and pg_catalog.right(p_like_pattern, 1) = '%' then
    v_literal := pg_catalog.substr(p_like_pattern, 2, 1);
    return query select candidate.id, candidate.version
      from private.display_catalog_flow_single_character_versions_v1(v_literal) as candidate;
    return;
  end if;
  return query select candidate.id, candidate.version
    from private.display_catalog_scoped_pattern_keys_v1('flow', p_like_pattern) as candidate;
end
$$;

ALTER FUNCTION "private"."display_catalog_flow_pattern_versions_v1"("p_like_pattern" "text") OWNER TO "portal_display_executor";

REVOKE ALL ON FUNCTION "private"."display_catalog_flow_pattern_versions_v1"("p_like_pattern" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."display_catalog_flow_pattern_versions_v1"("p_like_pattern" "text") TO "postgres";
