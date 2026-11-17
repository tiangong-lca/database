CREATE OR REPLACE FUNCTION "api"."cmd_lifecycle_model_bundle_save"("p_plan" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
    v_actor uuid := auth.uid();
begin
    if v_actor is null then raise exception using errcode = '42501', message = 'AUTH_REQUIRED'; end if;
    if p_plan ? 'protocol' then
        if p_plan->>'protocol' is distinct from 'model-bundle.v1' then raise exception 'INVALID_PLAN'; end if;
        return private.model_bundle_operation_v1(v_actor, p_plan);
    end if;
    return private.save_lifecycle_model_bundle(
        jsonb_set(coalesce(p_plan, '{}'::jsonb), '{actorUserId}', to_jsonb(v_actor::text), true)
    );
end
$$;

ALTER FUNCTION "api"."cmd_lifecycle_model_bundle_save"("p_plan" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."cmd_lifecycle_model_bundle_save"("p_plan" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."cmd_lifecycle_model_bundle_save"("p_plan" "jsonb") TO "authenticated";
