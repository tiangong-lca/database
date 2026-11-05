CREATE OR REPLACE FUNCTION "private"."final_result_query_row_hash"("p_row" "jsonb") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
  select encode(extensions.digest(convert_to(
    'tiangong.final-result-row.v2' || E'\n' || (p_row->>'ordinal') || E'\n'
    || (p_row->>'uuid') || E'\n' || (p_row->>'version') || E'\n'
    || (p_row->>'canonicalContentHash') || E'\n' || (p_row->>'contentHash') || E'\n'
    || (p_row->>'relationKind') || E'\n'
    || (select string_agg((value->>'uuid') || '@' || (value->>'version') || E'\n',''
        order by (value->>'uuid') collate "C",(value->>'version') collate "C")
        from jsonb_array_elements(p_row->'sources')),'UTF8'),'sha256'),'hex')
$$;

ALTER FUNCTION "private"."final_result_query_row_hash"("p_row" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."final_result_query_row_hash"("p_row" "jsonb") FROM PUBLIC;
