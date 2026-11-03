CREATE OR REPLACE FUNCTION "private"."study_reporting_digest"("p_domain" "text", "p_value" "jsonb") RETURNS "text"
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$select encode(extensions.digest(case when p_domain is null then ''::bytea else convert_to(p_domain,'UTF8')||decode('00','hex') end||convert_to(private.study_reporting_canonical(p_value),'UTF8'),'sha256'),'hex')$$;

ALTER FUNCTION "private"."study_reporting_digest"("p_domain" "text", "p_value" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_reporting_digest"("p_domain" "text", "p_value" "jsonb") FROM PUBLIC;
