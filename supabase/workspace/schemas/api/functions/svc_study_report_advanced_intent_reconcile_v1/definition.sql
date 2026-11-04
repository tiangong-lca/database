CREATE OR REPLACE FUNCTION "api"."svc_study_report_advanced_intent_reconcile_v1"("p_intent_id" "uuid", "p_artifact_id" "uuid", "p_content_hash" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare i private.study_report_intents%rowtype;a private.study_artifacts%rowtype;expected_ref jsonb;state text:='unknown';begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 perform private.study_require(p_intent_id is not null and p_artifact_id is not null and private.study_text(to_jsonb(p_content_hash),64,'^[0-9a-f]{64}$'),'INVALID_REQUEST');
 select * into i from private.study_report_intents where id=p_intent_id;
 if found and i.family='advanced' then
  perform 1 from private.studies where id=i.study_id for update;
  select * into i from private.study_report_intents where id=p_intent_id for update;
  if p_artifact_id=any(array[i.content_artifact_id,i.projection_artifact_id,i.resources_artifact_id,i.bundle_artifact_id]) then
   select * into a from private.study_artifacts where id=p_artifact_id;
   if found then
    expected_ref:=case when p_artifact_id=i.content_artifact_id then i.response->'data'->'value'->'contentRef'
     when p_artifact_id=i.projection_artifact_id then i.response->'data'->'value'->'projectionRef'
     when p_artifact_id=i.resources_artifact_id then i.response->'data'->'value'->'resourcesRef'
     else i.response->'data'->'value'->'bundleRef' end;
    if i.response->>'ok'='true' and a.study_id=i.study_id and a.ref=expected_ref and a.ref->>'contentHash'=p_content_hash then state:='committed';
    else state:='referenced';end if;
   elsif i.response is null and i.expires_at<=clock_timestamp() then state:='expired_unreferenced';
   elsif i.response is null then state:='pending';end if;
  end if;
 end if;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('schemaVersion','lca.study-report-reconcile.v1','intentId',p_intent_id,'artifactId',p_artifact_id,'state',state,'deletionPermitted',false));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end$_$;

ALTER FUNCTION "api"."svc_study_report_advanced_intent_reconcile_v1"("p_intent_id" "uuid", "p_artifact_id" "uuid", "p_content_hash" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_report_advanced_intent_reconcile_v1"("p_intent_id" "uuid", "p_artifact_id" "uuid", "p_content_hash" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_report_advanced_intent_reconcile_v1"("p_intent_id" "uuid", "p_artifact_id" "uuid", "p_content_hash" "text") TO "service_role";
