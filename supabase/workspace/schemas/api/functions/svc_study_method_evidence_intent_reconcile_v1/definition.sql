CREATE OR REPLACE FUNCTION "api"."svc_study_method_evidence_intent_reconcile_v1"("p_intent_id" "uuid", "p_artifact_id" "uuid", "p_content_hash" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare i private.study_method_evidence_intents%rowtype;state text;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');select * into i from private.study_method_evidence_intents where id=p_intent_id;
 perform private.study_require(found and i.artifact_id=p_artifact_id and p_content_hash=private.study_reporting_digest(null,i.request->'content'),'REFERENCE_MISMATCH');
 perform 1 from private.studies where id=i.study_id for update;select * into i from private.study_method_evidence_intents where id=p_intent_id for update;
 if i.response is not null then state:='committed';
 elsif exists(select 1 from private.study_artifacts where id=p_artifact_id) then state:='referenced';
 elsif i.expires_at<=clock_timestamp() then state:='expired_unreferenced';else state:='pending';end if;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('schemaVersion','lca.study-method-evidence-reconcile.v1','intentId',i.id,'state',state,'response',i.response,'deletionPermitted',false));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);end$$;

ALTER FUNCTION "api"."svc_study_method_evidence_intent_reconcile_v1"("p_intent_id" "uuid", "p_artifact_id" "uuid", "p_content_hash" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_method_evidence_intent_reconcile_v1"("p_intent_id" "uuid", "p_artifact_id" "uuid", "p_content_hash" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_method_evidence_intent_reconcile_v1"("p_intent_id" "uuid", "p_artifact_id" "uuid", "p_content_hash" "text") TO "service_role";
