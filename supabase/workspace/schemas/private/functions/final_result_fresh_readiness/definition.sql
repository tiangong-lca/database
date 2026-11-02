CREATE OR REPLACE FUNCTION "private"."final_result_fresh_readiness"("p_verification" "uuid", "p_run" "uuid", "p_plan_hash" "text", "p_actor" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_ready private.final_result_release_readiness%rowtype; v_context jsonb;
begin
 select * into v_ready from private.final_result_release_readiness where verification_id=p_verification;
 if not found or v_ready.expires_at<=clock_timestamp() then
   raise exception using errcode='55000',message='Fresh final Result readiness is required'; end if;
 v_context:=private.final_result_verification_context(p_run,p_plan_hash,p_actor);
 if (v_ready.receipt-array['schemaVersion','verificationId','artifactCount','probeCount','fileCount','coverageHash','expiresAt','sealedAt'])
   is distinct from v_context then raise exception using errcode='55000',message='Final Result readiness preconditions changed'; end if;
 return v_ready.receipt;
end;
$$;

ALTER FUNCTION "private"."final_result_fresh_readiness"("p_verification" "uuid", "p_run" "uuid", "p_plan_hash" "text", "p_actor" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."final_result_fresh_readiness"("p_verification" "uuid", "p_run" "uuid", "p_plan_hash" "text", "p_actor" "uuid") FROM PUBLIC;
