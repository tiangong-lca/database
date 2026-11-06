-- Database #943: keep the full Search contract guard once; classify failures
-- using closed coarse values only. No request text, filters, cursors or IDs.
begin;
select private.portal_display_assert_contract_v1();

CREATE OR REPLACE FUNCTION "private"."display_search_v3"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_sort" "text", "p_cursor" "text", "p_limit" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE PARALLEL RESTRICTED
    SET "search_path" TO ''
    AS $_$
declare
  v_query text;
  v_filters jsonb;
  v_sort text;
  v_limit integer := coalesce(p_limit, 20);
  v_fingerprint text;
  v_cursor jsonb;
  v_cursor_rank text;
  v_cursor_id uuid;
  v_cursor_version text;
  v_kernel jsonb;
  v_next_cursor_payload jsonb;
begin
  -- The V3 validator immediately runs the complete navigation projection
  -- guard, including this same catalog contract. Check it once per request.
  perform private.display_validate_search_v3(
    p_kind,
    coalesce(p_query, ''),
    coalesce(p_filters, '{}'::jsonb),
    coalesce(p_sort, 'relevance'),
    v_limit
  );
  v_query := pg_catalog.lower(pg_catalog.btrim(coalesce(p_query, '')));
  v_filters := private.display_normalize_filters_v1(p_filters);
  v_sort := pg_catalog.lower(pg_catalog.btrim(coalesce(p_sort, 'relevance')));
  v_fingerprint := private.display_query_fingerprint_v1(
    p_kind,
    v_query,
    v_filters,
    v_sort
  );
  if p_kind = 'process' then
  v_fingerprint := pg_catalog.encode(extensions.digest(pg_catalog.convert_to('composite-names-v2:' || v_fingerprint, 'UTF8'), 'sha256'), 'hex');
  end if;
  v_fingerprint := pg_catalog.encode(extensions.digest(
    pg_catalog.convert_to('portal-search-versions-v3:' || (select asset_sha256 from private.display_read_navigation_contract_v1 where contract_version=1) || ':' || v_fingerprint,'UTF8'),'sha256'),'hex');
  if p_cursor is not null then
    v_cursor := private.display_cursor_decode_v1(p_cursor);
    if v_cursor is null
       or (select count(*) from pg_catalog.jsonb_object_keys(v_cursor)) <> 6
       or v_cursor ->> 'v' <> '1'
       or v_cursor ->> 'fp' <> v_fingerprint
       or v_cursor ->> 'kind' <> p_kind
       or coalesce(v_cursor ->> 'rankKey', '') = ''
       or coalesce(v_cursor ->> 'id', '')
         !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or coalesce(v_cursor ->> 'version', '') !~ '^\d{2}\.\d{2}\.\d{3}$' then
      raise exception using errcode = '22023', message = 'invalid portal request';
    end if;
    v_cursor_rank := v_cursor ->> 'rankKey';
    v_cursor_id := (v_cursor ->> 'id')::uuid;
    v_cursor_version := v_cursor ->> 'version';
    if v_sort = 'relevance'
       and v_cursor_rank !~ '^(0(\.\d+)?|1(\.0+)?)$' then
      raise exception using errcode = '22023', message = 'invalid portal request';
    elsif v_sort = 'modified_desc'
       and private.display_datetime_v1(v_cursor_rank) is null then
      raise exception using errcode = '22023', message = 'invalid portal request';
    end if;
  end if;

  v_kernel := private.display_catalog_search_v3_impl(
    p_kind,v_query,v_filters,v_sort,v_cursor_rank,v_cursor_id,v_cursor_version,v_limit,v_fingerprint
  );

  v_next_cursor_payload := nullif(
    v_kernel -> 'nextCursorPayload',
    'null'::jsonb
  );

  return pg_catalog.jsonb_build_object(
    'schemaVersion', 'portal.public-search-page.v1',
    'kind', p_kind,
    'queryFingerprint', v_fingerprint,
    'items', coalesce(v_kernel -> 'items', '[]'::jsonb),
    'nextCursor', case when v_next_cursor_payload is null then null
      else private.display_cursor_encode_v1(v_next_cursor_payload)
    end
  );
end;
$_$;

ALTER FUNCTION "private"."display_search_v3"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_sort" "text", "p_cursor" "text", "p_limit" integer) OWNER TO "portal_display_executor";

REVOKE ALL ON FUNCTION "private"."display_search_v3"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_sort" "text", "p_cursor" "text", "p_limit" integer) FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."display_search_v3"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_sort" "text", "p_cursor" "text", "p_limit" integer) TO "postgres";

CREATE OR REPLACE FUNCTION "private"."display_api_search_processes_v3"("p_query" "text", "p_filters" "jsonb" DEFAULT '{}'::"jsonb", "p_sort" "text" DEFAULT 'relevance'::"text", "p_cursor" "text" DEFAULT NULL::"text", "p_limit" integer DEFAULT 20) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '8s'
    AS $$
declare
  v_diagnostic_message text;
  v_diagnostic_state text;
begin
  return pg_catalog.jsonb_set(private.display_decorate_card_context_v1(
    private.display_lcia_decorate_item_page_v1(
      private.display_search_v3(
        'process', p_query, p_filters, p_sort, p_cursor, p_limit
      )
    )
  ), '{schemaVersion}', '"portal.public-search-page.v2"'::jsonb);
exception
  when sqlstate '22023' then
    raise log using message = 'portal read failure diagnostic',
      detail = pg_catalog.jsonb_build_object(
        'schemaVersion', 'portal.read-failure.v1', 'rpc', 'display_search_processes_v3',
        'queryClass', case
          when p_query is null then 'default'
          when octet_length(p_query)>2048 then 'oversize'
          when btrim(p_query)='' then 'empty'
          when char_length(btrim(p_query))=1 then 'single'
          else 'multiple' end,
        'filterClass', case
          when p_filters is null then 'default'
          when pg_column_size(p_filters)>4096 then 'oversize'
          when jsonb_typeof(p_filters)<>'object' then 'invalid'
          when p_filters='{}'::jsonb then 'empty' else 'filtered' end,
        'sortClass', case
          when p_sort is null then 'default'
          when octet_length(p_sort)>64 then 'invalid'
          when lower(btrim(p_sort)) in ('relevance','name_asc','modified_desc')
            then lower(btrim(p_sort)) else 'invalid' end,
        'hasCursor', p_cursor is not null,
        'limitClass', case when p_limit is null then 'default'
          when p_limit between 1 and 10 then '1_10'
          when p_limit between 11 and 50 then '11_50' else 'invalid' end,
        'category', 'validation', 'reason', 'input'
      )::text;
    raise exception using errcode = '22023', message = 'invalid portal request';
  when query_canceled then
    get stacked diagnostics v_diagnostic_message = MESSAGE_TEXT;
    raise log using message = 'portal read failure diagnostic',
      detail = pg_catalog.jsonb_build_object(
        'schemaVersion', 'portal.read-failure.v1', 'rpc', 'display_search_processes_v3',
        'queryClass', case
          when p_query is null then 'default'
          when octet_length(p_query)>2048 then 'oversize'
          when btrim(p_query)='' then 'empty'
          when char_length(btrim(p_query))=1 then 'single'
          else 'multiple' end,
        'filterClass', case
          when p_filters is null then 'default'
          when pg_column_size(p_filters)>4096 then 'oversize'
          when jsonb_typeof(p_filters)<>'object' then 'invalid'
          when p_filters='{}'::jsonb then 'empty' else 'filtered' end,
        'sortClass', case
          when p_sort is null then 'default'
          when octet_length(p_sort)>64 then 'invalid'
          when lower(btrim(p_sort)) in ('relevance','name_asc','modified_desc')
            then lower(btrim(p_sort)) else 'invalid' end,
        'hasCursor', p_cursor is not null,
        'limitClass', case when p_limit is null then 'default'
          when p_limit between 1 and 10 then '1_10'
          when p_limit between 11 and 50 then '11_50' else 'invalid' end,
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
        'schemaVersion', 'portal.read-failure.v1', 'rpc', 'display_search_processes_v3',
        'queryClass', case
          when p_query is null then 'default'
          when octet_length(p_query)>2048 then 'oversize'
          when btrim(p_query)='' then 'empty'
          when char_length(btrim(p_query))=1 then 'single'
          else 'multiple' end,
        'filterClass', case
          when p_filters is null then 'default'
          when pg_column_size(p_filters)>4096 then 'oversize'
          when jsonb_typeof(p_filters)<>'object' then 'invalid'
          when p_filters='{}'::jsonb then 'empty' else 'filtered' end,
        'sortClass', case
          when p_sort is null then 'default'
          when octet_length(p_sort)>64 then 'invalid'
          when lower(btrim(p_sort)) in ('relevance','name_asc','modified_desc')
            then lower(btrim(p_sort)) else 'invalid' end,
        'hasCursor', p_cursor is not null,
        'limitClass', case when p_limit is null then 'default'
          when p_limit between 1 and 10 then '1_10'
          when p_limit between 11 and 50 then '11_50' else 'invalid' end,
        'category', 'internal', 'reason', case v_diagnostic_state
          when '54000' then 'response_budget'
          when '55000' then 'contract_drift'
          else 'other'
        end
      )::text;
    raise exception using errcode = 'P0001', message = 'portal catalog unavailable';
end;
$$;

ALTER FUNCTION "private"."display_api_search_processes_v3"("p_query" "text", "p_filters" "jsonb", "p_sort" "text", "p_cursor" "text", "p_limit" integer) OWNER TO "portal_display_executor";

REVOKE ALL ON FUNCTION "private"."display_api_search_processes_v3"("p_query" "text", "p_filters" "jsonb", "p_sort" "text", "p_cursor" "text", "p_limit" integer) FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."display_api_search_processes_v3"("p_query" "text", "p_filters" "jsonb", "p_sort" "text", "p_cursor" "text", "p_limit" integer) TO "portal_public_executor";

CREATE OR REPLACE FUNCTION "private"."display_api_search_flows_v3"("p_query" "text", "p_filters" "jsonb" DEFAULT '{}'::"jsonb", "p_sort" "text" DEFAULT 'relevance'::"text", "p_cursor" "text" DEFAULT NULL::"text", "p_limit" integer DEFAULT 20) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '8s'
    AS $$
declare
  v_diagnostic_message text;
  v_diagnostic_state text;
begin
  return pg_catalog.jsonb_set(private.display_decorate_card_context_v1(
    private.display_search_v3(
      'flow', p_query, p_filters, p_sort, p_cursor, p_limit
    )
  ), '{schemaVersion}', '"portal.public-search-page.v2"'::jsonb);
exception
  when sqlstate '22023' then
    raise log using message = 'portal read failure diagnostic',
      detail = pg_catalog.jsonb_build_object(
        'schemaVersion', 'portal.read-failure.v1', 'rpc', 'display_search_flows_v3',
        'queryClass', case
          when p_query is null then 'default'
          when octet_length(p_query)>2048 then 'oversize'
          when btrim(p_query)='' then 'empty'
          when char_length(btrim(p_query))=1 then 'single'
          else 'multiple' end,
        'filterClass', case
          when p_filters is null then 'default'
          when pg_column_size(p_filters)>4096 then 'oversize'
          when jsonb_typeof(p_filters)<>'object' then 'invalid'
          when p_filters='{}'::jsonb then 'empty' else 'filtered' end,
        'sortClass', case
          when p_sort is null then 'default'
          when octet_length(p_sort)>64 then 'invalid'
          when lower(btrim(p_sort)) in ('relevance','name_asc','modified_desc')
            then lower(btrim(p_sort)) else 'invalid' end,
        'hasCursor', p_cursor is not null,
        'limitClass', case when p_limit is null then 'default'
          when p_limit between 1 and 10 then '1_10'
          when p_limit between 11 and 50 then '11_50' else 'invalid' end,
        'category', 'validation', 'reason', 'input'
      )::text;
    raise exception using errcode = '22023', message = 'invalid portal request';
  when query_canceled then
    get stacked diagnostics v_diagnostic_message = MESSAGE_TEXT;
    raise log using message = 'portal read failure diagnostic',
      detail = pg_catalog.jsonb_build_object(
        'schemaVersion', 'portal.read-failure.v1', 'rpc', 'display_search_flows_v3',
        'queryClass', case
          when p_query is null then 'default'
          when octet_length(p_query)>2048 then 'oversize'
          when btrim(p_query)='' then 'empty'
          when char_length(btrim(p_query))=1 then 'single'
          else 'multiple' end,
        'filterClass', case
          when p_filters is null then 'default'
          when pg_column_size(p_filters)>4096 then 'oversize'
          when jsonb_typeof(p_filters)<>'object' then 'invalid'
          when p_filters='{}'::jsonb then 'empty' else 'filtered' end,
        'sortClass', case
          when p_sort is null then 'default'
          when octet_length(p_sort)>64 then 'invalid'
          when lower(btrim(p_sort)) in ('relevance','name_asc','modified_desc')
            then lower(btrim(p_sort)) else 'invalid' end,
        'hasCursor', p_cursor is not null,
        'limitClass', case when p_limit is null then 'default'
          when p_limit between 1 and 10 then '1_10'
          when p_limit between 11 and 50 then '11_50' else 'invalid' end,
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
        'schemaVersion', 'portal.read-failure.v1', 'rpc', 'display_search_flows_v3',
        'queryClass', case
          when p_query is null then 'default'
          when octet_length(p_query)>2048 then 'oversize'
          when btrim(p_query)='' then 'empty'
          when char_length(btrim(p_query))=1 then 'single'
          else 'multiple' end,
        'filterClass', case
          when p_filters is null then 'default'
          when pg_column_size(p_filters)>4096 then 'oversize'
          when jsonb_typeof(p_filters)<>'object' then 'invalid'
          when p_filters='{}'::jsonb then 'empty' else 'filtered' end,
        'sortClass', case
          when p_sort is null then 'default'
          when octet_length(p_sort)>64 then 'invalid'
          when lower(btrim(p_sort)) in ('relevance','name_asc','modified_desc')
            then lower(btrim(p_sort)) else 'invalid' end,
        'hasCursor', p_cursor is not null,
        'limitClass', case when p_limit is null then 'default'
          when p_limit between 1 and 10 then '1_10'
          when p_limit between 11 and 50 then '11_50' else 'invalid' end,
        'category', 'internal', 'reason', case v_diagnostic_state
          when '54000' then 'response_budget'
          when '55000' then 'contract_drift'
          else 'other'
        end
      )::text;
    raise exception using errcode = 'P0001', message = 'portal catalog unavailable';
end;
$$;

ALTER FUNCTION "private"."display_api_search_flows_v3"("p_query" "text", "p_filters" "jsonb", "p_sort" "text", "p_cursor" "text", "p_limit" integer) OWNER TO "portal_display_executor";

REVOKE ALL ON FUNCTION "private"."display_api_search_flows_v3"("p_query" "text", "p_filters" "jsonb", "p_sort" "text", "p_cursor" "text", "p_limit" integer) FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."display_api_search_flows_v3"("p_query" "text", "p_filters" "jsonb", "p_sort" "text", "p_cursor" "text", "p_limit" integer) TO "portal_public_executor";

update private.portal_display_contract_manifest
set identity=private.portal_display_contract_identity_v1() where singleton;
select private.portal_display_assert_contract_v1();
commit;
