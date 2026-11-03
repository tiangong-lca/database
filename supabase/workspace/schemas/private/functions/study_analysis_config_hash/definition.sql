CREATE OR REPLACE FUNCTION "private"."study_analysis_config_hash"("p_config" "jsonb") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
 select encode(extensions.digest(convert_to('study.analysis-config.v1','UTF8')||decode('00','hex')||convert_to(
 '{"kind":'||to_jsonb(p_config->>'kind')::text||',"runIds":['||
 (select string_agg(to_jsonb(x#>>'{}')::text,',' order by n) from jsonb_array_elements(p_config->'runIds') with ordinality e(x,n))||
 '],"schemaVersion":"lca.study-analysis-config.v1"}','UTF8'),'sha256'),'hex')
$$;

ALTER FUNCTION "private"."study_analysis_config_hash"("p_config" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_analysis_config_hash"("p_config" "jsonb") FROM PUBLIC;
