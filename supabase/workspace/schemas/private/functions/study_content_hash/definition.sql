CREATE OR REPLACE FUNCTION "private"."study_content_hash"("p_domain" "text", "p_document" "jsonb") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
  select encode(extensions.digest(convert_to(p_domain || chr(10) || p_document::text,'UTF8'),'sha256'),'hex')
$$;

ALTER FUNCTION "private"."study_content_hash"("p_domain" "text", "p_document" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_content_hash"("p_domain" "text", "p_document" "jsonb") FROM PUBLIC;
