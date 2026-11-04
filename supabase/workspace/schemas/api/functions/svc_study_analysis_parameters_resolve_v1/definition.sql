CREATE OR REPLACE FUNCTION "api"."svc_study_analysis_parameters_resolve_v1"("p_intent_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare i private.study_advanced_parameter_intents%rowtype;snapshot uuid;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');select * into i from private.study_advanced_parameter_intents where id=p_intent_id;
 perform private.study_require(found and i.expires_at>clock_timestamp(),'CAPABILITY_UNAVAILABLE');snapshot:=private.study_advanced_rights(i.study_id,i.baseline_run_id,i.actor_id,i.client_id);
 perform private.study_require(snapshot=i.source_snapshot_id,'REFERENCE_MISMATCH');
 return jsonb_build_object('ok',true,'data',jsonb_build_object('kind','advancedParameterContext','intentId',i.id,'expiresAt',i.expires_at,'studyId',i.study_id,'baselineRunId',i.baseline_run_id,'actorId',i.actor_id,'clientId',i.client_id,
 'baseline',private.study_advanced_baseline(i.study_id,i.baseline_run_id),'sourceSnapshot',private.study_record('modelSourceSnapshot',snapshot),
 'sourceArtifact',private.study_private_artifact(i.study_id,(select artifact_id from private.study_source_snapshots where id=snapshot))));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);end$$;

ALTER FUNCTION "api"."svc_study_analysis_parameters_resolve_v1"("p_intent_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_analysis_parameters_resolve_v1"("p_intent_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_analysis_parameters_resolve_v1"("p_intent_id" "uuid") TO "service_role";
