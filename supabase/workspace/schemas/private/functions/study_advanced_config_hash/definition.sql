CREATE OR REPLACE FUNCTION "private"."study_advanced_config_hash"("p_config" "jsonb") RETURNS "text"
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$select private.study_reporting_digest('study.analysis-config.v2',p_config)$$;

ALTER FUNCTION "private"."study_advanced_config_hash"("p_config" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_advanced_config_hash"("p_config" "jsonb") FROM PUBLIC;
