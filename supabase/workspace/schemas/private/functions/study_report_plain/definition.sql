CREATE OR REPLACE FUNCTION "private"."study_report_plain"("p_value" "jsonb", "p_max" integer) RETURNS boolean
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO ''
    AS $$select private.study_text(p_value,p_max) and (p_value#>>'{}') !~ '[<>]' and (p_value#>>'{}') !~* '(https?|javascript|data|file|blob):'$$;

ALTER FUNCTION "private"."study_report_plain"("p_value" "jsonb", "p_max" integer) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_report_plain"("p_value" "jsonb", "p_max" integer) FROM PUBLIC;
