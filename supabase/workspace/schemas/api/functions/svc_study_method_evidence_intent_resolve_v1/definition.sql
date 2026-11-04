CREATE OR REPLACE FUNCTION "api"."svc_study_method_evidence_intent_resolve_v1"("p_intent_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare i private.study_method_evidence_intents%rowtype;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');i:=private.study_method_evidence_intent_check(p_intent_id);
 if i.response is not null then return i.response;end if;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('kind','methodEvidenceCommandContext','intentId',i.id,'expiresAt',i.expires_at,
 'request',i.request,'studyId',i.study_id,'actorId',i.actor_id,'clientId',i.client_id,'evidenceId',i.evidence_id,'artifactId',i.artifact_id,'recordedAt',i.created_at,
 'contentHash',private.study_reporting_digest(null,i.request->'content'),'byteSize',octet_length(private.study_reporting_canonical(i.request->'content'))));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);end$$;

ALTER FUNCTION "api"."svc_study_method_evidence_intent_resolve_v1"("p_intent_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_method_evidence_intent_resolve_v1"("p_intent_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_method_evidence_intent_resolve_v1"("p_intent_id" "uuid") TO "service_role";
