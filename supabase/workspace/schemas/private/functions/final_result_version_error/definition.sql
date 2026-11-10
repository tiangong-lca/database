CREATE OR REPLACE FUNCTION "private"."final_result_version_error"("p_code" "text", "p_release_version" "text") RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
 select private.lca_release_error(p_code,409,'Publication version is occupied; inspect the exact draft before an explicitly confirmed replacement')
   ||jsonb_build_object('details',private.final_result_version_state(p_release_version));
$$;

ALTER FUNCTION "private"."final_result_version_error"("p_code" "text", "p_release_version" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."final_result_version_error"("p_code" "text", "p_release_version" "text") FROM PUBLIC;
