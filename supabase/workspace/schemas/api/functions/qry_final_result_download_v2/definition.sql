CREATE OR REPLACE FUNCTION "api"."qry_final_result_download_v2"("p_publication_id" "uuid", "p_format" "text") RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  select api.qry_final_result_download(p_publication_id, p_format);
$$;

ALTER FUNCTION "api"."qry_final_result_download_v2"("p_publication_id" "uuid", "p_format" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."qry_final_result_download_v2"("p_publication_id" "uuid", "p_format" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."qry_final_result_download_v2"("p_publication_id" "uuid", "p_format" "text") TO "authenticated";
