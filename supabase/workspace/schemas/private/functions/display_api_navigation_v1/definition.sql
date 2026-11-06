CREATE OR REPLACE FUNCTION "private"."display_api_navigation_v1"("p_kind" "text", "p_query" "text" DEFAULT ''::"text", "p_filters" "jsonb" DEFAULT '{}'::"jsonb", "p_dimension" "text" DEFAULT 'classification'::"text", "p_parent_node_id" "text" DEFAULT NULL::"text", "p_cursor" "text" DEFAULT NULL::"text", "p_limit" integer DEFAULT 100) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '8s'
    SET "row_security" TO 'on'
    AS $$
begin
  return private.display_api_navigation_v1(p_kind,p_query,p_filters,p_dimension,p_parent_node_id,p_cursor,p_limit,true);
end;
$$;

ALTER FUNCTION "private"."display_api_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer) OWNER TO "portal_display_executor";

CREATE OR REPLACE FUNCTION "private"."display_api_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer, "p_include_totals" boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '8s'
    SET "row_security" TO 'on'
    AS $$
declare
  v_diagnostic_message text;
  v_diagnostic_context text;
  v_diagnostic_state text;
begin
  return private.display_navigation_v1(p_kind,p_query,p_filters,p_dimension,p_parent_node_id,p_cursor,p_limit,p_include_totals);
exception
  when sqlstate '22023' then
    get stacked diagnostics v_diagnostic_context = PG_EXCEPTION_CONTEXT;
    raise log using message = 'portal read failure diagnostic',
      detail = pg_catalog.jsonb_build_object(
        'schemaVersion', 'portal.read-failure.v1', 'rpc', 'display_navigation_v1',
        'category', 'validation', 'reason', case
          when v_diagnostic_context ~ '^PL/pgSQL function private\.display_validate_search_v1\(' then 'search_input'
          when v_diagnostic_context ~ '^PL/pgSQL function private\.display_validate_search_v3\(' then 'hierarchy_input'
          when v_diagnostic_context ~ '^PL/pgSQL function private\.display_navigation_impl_v1\(' then
            case when p_cursor is null then 'parent' else 'parent_or_cursor_node' end
          when v_diagnostic_context ~ '^PL/pgSQL function private\.display_navigation_v1\(' then
            case
              when p_dimension is null or p_dimension not in ('classification', 'geography')
                or coalesce(p_limit, 100) not between 1 and 500 then 'navigation_options'
              when p_cursor is not null then 'cursor_binding'
              else 'unknown'
            end
          else 'unknown'
        end
      )::text;
    raise exception using errcode = '22023', message = 'invalid portal request';
  when query_canceled then
    get stacked diagnostics v_diagnostic_message = MESSAGE_TEXT;
    raise log using message = 'portal read failure diagnostic',
      detail = pg_catalog.jsonb_build_object(
        'schemaVersion', 'portal.read-failure.v1', 'rpc', 'display_navigation_v1',
        'category', 'cancellation', 'reason', case v_diagnostic_message
          when 'canceling statement due to statement timeout' then 'statement_timeout'
          when 'canceling statement due to user request' then 'cancel_request'
          else 'unknown'
        end
      )::text;
    raise exception using errcode = 'P0001', message = 'portal catalog unavailable';
  when others then
    get stacked diagnostics v_diagnostic_state = RETURNED_SQLSTATE;
    raise log using message = 'portal read failure diagnostic',
      detail = pg_catalog.jsonb_build_object(
        'schemaVersion', 'portal.read-failure.v1', 'rpc', 'display_navigation_v1',
        'category', 'internal', 'reason', case v_diagnostic_state
          when '54000' then 'response_budget'
          when '55000' then 'contract_drift'
          else 'other'
        end
      )::text;
    raise exception using errcode = 'P0001', message = 'portal catalog unavailable';
end;
$$;

ALTER FUNCTION "private"."display_api_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer, "p_include_totals" boolean) OWNER TO "portal_display_executor";

REVOKE ALL ON FUNCTION "private"."display_api_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer) FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."display_api_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer) TO "portal_public_executor";

REVOKE ALL ON FUNCTION "private"."display_api_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer, "p_include_totals" boolean) FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."display_api_navigation_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor" "text", "p_limit" integer, "p_include_totals" boolean) TO "portal_public_executor";
