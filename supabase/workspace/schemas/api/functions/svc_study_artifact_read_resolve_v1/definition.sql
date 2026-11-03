CREATE OR REPLACE FUNCTION "api"."svc_study_artifact_read_resolve_v1"("p_intent_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$ declare i private.study_artifact_read_intents%rowtype; begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 select * into i from private.study_artifact_read_intents where id=p_intent_id;
 perform private.study_require(found and i.expires_at>clock_timestamp(),'CAPABILITY_UNAVAILABLE');
 return jsonb_build_object('ok',true,'data',private.study_reporting_artifact_authorize(i.study_id,i.artifact_ref,i.actor_id,i.client_id));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end $$;

ALTER FUNCTION "api"."svc_study_artifact_read_resolve_v1"("p_intent_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_artifact_read_resolve_v1"("p_intent_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_artifact_read_resolve_v1"("p_intent_id" "uuid") TO "service_role";
