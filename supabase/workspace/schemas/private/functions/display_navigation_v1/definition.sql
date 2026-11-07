CREATE OR REPLACE FUNCTION "private"."display_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE PARALLEL RESTRICTED
    SET "search_path" TO ''
    AS $$
begin
  return private.display_navigation_v1(p_kind,p_query,p_filters,p_dimension,p_parent_node_id,p_cursor,p_limit,true);
end;
$$;

ALTER FUNCTION "private"."display_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer) OWNER TO "portal_display_executor";

CREATE OR REPLACE FUNCTION "private"."display_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer, "p_include_totals" boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE PARALLEL RESTRICTED
    SET "search_path" TO ''
    AS $_$
declare
  v_query text:=lower(btrim(coalesce(p_query,'')));
  v_filters jsonb;
  v_limit integer:=coalesce(p_limit,100);
  v_fingerprint text;
  v_cursor jsonb;
  v_cursor_node text;
begin
  if p_dimension is null or p_dimension not in ('classification','geography')
    or v_limit<1 or v_limit>500 then
    raise exception using errcode='22023',message='invalid portal request';
  end if;
  perform private.display_validate_search_v3(p_kind,coalesce(p_query,''),coalesce(p_filters,'{}'::jsonb),'relevance',1);
  v_filters:=private.display_normalize_filters_v1(p_filters);
  v_fingerprint:=encode(extensions.digest(convert_to(
    'portal-navigation-v1:' || (select asset_sha256 from private.display_read_navigation_contract_v1 where contract_version=1) || ':' ||
    private.display_query_fingerprint_v1(p_kind,v_query,v_filters,p_dimension || ':' || coalesce(p_parent_node_id,'')),
    'UTF8'),'sha256'),'hex');
  if p_cursor is not null then
    v_cursor:=private.display_cursor_decode_v1(p_cursor);
    if v_cursor is null or jsonb_typeof(v_cursor)<>'object'
      or (select count(*) from jsonb_object_keys(v_cursor))<>6
      or v_cursor->>'v' is distinct from '1' or v_cursor->>'fp' is distinct from v_fingerprint
      or v_cursor->>'kind' is distinct from p_kind or v_cursor->>'dimension' is distinct from p_dimension
      or v_cursor->>'parent' is distinct from p_parent_node_id
      or coalesce(v_cursor->>'node','') !~ '^[a-z][a-z0-9-]*:[!-~]{1,96}$'
    then raise exception using errcode='22023',message='invalid portal request'; end if;
    v_cursor_node:=v_cursor->>'node';
  end if;
  return private.display_navigation_impl_v1(p_kind,v_query,v_filters,p_dimension,p_parent_node_id,v_cursor_node,v_limit,v_fingerprint,p_include_totals);
end;
$_$;

ALTER FUNCTION "private"."display_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer, "p_include_totals" boolean) OWNER TO "portal_display_executor";

REVOKE ALL ON FUNCTION "private"."display_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer) FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."display_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer) TO "postgres";

REVOKE ALL ON FUNCTION "private"."display_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer, "p_include_totals" boolean) FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."display_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer, "p_include_totals" boolean) TO "postgres";
