CREATE OR REPLACE FUNCTION "api"."svc_study_method_evidence_intent_consume_v1"("p_intent_id" "uuid", "p_completion" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare i private.study_method_evidence_intents%rowtype;a uuid;result jsonb;ref jsonb;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');i:=private.study_method_evidence_intent_check(p_intent_id);
 select * into i from private.study_method_evidence_intents where id=p_intent_id for update;
 if i.response is not null then
  perform private.study_require(private.study_keys(p_completion,array['artifact']) and p_completion->'artifact'->'artifactRef'=i.response->'data'->'value'->'artifactRef'
   and exists(select 1 from private.study_artifacts where study_id=i.study_id and id=i.artifact_id and bucket=p_completion->'artifact'->>'storageBucket' and object_path=p_completion->'artifact'->>'storageObjectPath'),'IDEMPOTENCY_CONFLICT');
  return i.response;
 end if;
 ref:=p_completion->'artifact'->'artifactRef';
 perform private.study_require(private.study_keys(p_completion,array['artifact']) and private.study_keys(p_completion->'artifact',array['artifactRef','storageBucket','storageObjectPath'])
 and private.study_method_artifact_valid(ref,'methodEvidence','lca.study-method-evidence.v1',65536) and ref->>'id'=i.artifact_id::text
 and ref->>'contentHash'=private.study_reporting_digest(null,i.request->'content')
 and(ref->>'byteSize')::numeric=octet_length(private.study_reporting_canonical(i.request->'content')),'REFERENCE_MISMATCH');
 a:=private.study_store_artifact(i.study_id,ref,p_completion->'artifact'->>'storageBucket',p_completion->'artifact'->>'storageObjectPath','methodEvidence');
 insert into private.study_method_evidence(id,study_id,requirement_id,declared_kind,artifact_id,recorded_by,recorded_client_id,recorded_at)
 values(i.evidence_id,i.study_id,i.request->'content'->>'requirementId',i.request->'content'->>'declaredKind',a,i.actor_id,i.client_id,i.created_at);
 result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','methodEvidence','value',private.study_method_evidence_record(i.evidence_id)));
 update private.study_method_evidence_intents set response=result where id=i.id;
 update private.study_command_receipts set response=result where actor_id=i.actor_id and operation='method.evidence.create' and scope=i.study_id::text and idempotency_key=i.request->>'idempotencyKey';return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or numeric_value_out_of_range or not_null_violation or check_violation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');end$$;

ALTER FUNCTION "api"."svc_study_method_evidence_intent_consume_v1"("p_intent_id" "uuid", "p_completion" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_method_evidence_intent_consume_v1"("p_intent_id" "uuid", "p_completion" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_method_evidence_intent_consume_v1"("p_intent_id" "uuid", "p_completion" "jsonb") TO "service_role";
