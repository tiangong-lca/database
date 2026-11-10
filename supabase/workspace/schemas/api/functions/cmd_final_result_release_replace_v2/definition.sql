CREATE OR REPLACE FUNCTION "api"."cmd_final_result_release_replace_v2"("p_plan_text" "text", "p_idempotency_key" "text", "p_replace_run_id" "uuid", "p_replace_plan_hash" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_auth jsonb:=api.assert_lca_release_manager();
begin
 if not coalesce((v_auth->>'ok')::boolean,false) then return v_auth; end if;
 if p_replace_run_id is null or p_replace_plan_hash is null then
   return private.lca_release_error('final_result_draft_replacement_conflict',409,'Replacement requires an exact predecessor run and plan hash');
 end if;
 return private.final_result_prepare_draft(p_plan_text,p_idempotency_key,p_replace_run_id,p_replace_plan_hash);
end;
$$;

ALTER FUNCTION "api"."cmd_final_result_release_replace_v2"("p_plan_text" "text", "p_idempotency_key" "text", "p_replace_run_id" "uuid", "p_replace_plan_hash" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."cmd_final_result_release_replace_v2"("p_plan_text" "text", "p_idempotency_key" "text", "p_replace_run_id" "uuid", "p_replace_plan_hash" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."cmd_final_result_release_replace_v2"("p_plan_text" "text", "p_idempotency_key" "text", "p_replace_run_id" "uuid", "p_replace_plan_hash" "text") TO "authenticated";
