CREATE OR REPLACE FUNCTION "api"."cmd_final_result_release_prepare_v2"("p_plan_text" "text", "p_idempotency_key" "text") RETURNS "jsonb"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
 select private.final_result_prepare_draft(p_plan_text,p_idempotency_key,null,null);
$$;

ALTER FUNCTION "api"."cmd_final_result_release_prepare_v2"("p_plan_text" "text", "p_idempotency_key" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."cmd_final_result_release_prepare_v2"("p_plan_text" "text", "p_idempotency_key" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."cmd_final_result_release_prepare_v2"("p_plan_text" "text", "p_idempotency_key" "text") TO "authenticated";
