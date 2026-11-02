CREATE OR REPLACE FUNCTION "api"."svc_study_revision_freeze_consume_v1"("p_intent_id" "uuid", "p_outcome" "text", "p_error_code" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '15s'
    AS $$
declare i private.study_validation_intents%rowtype; r private.study_revisions%rowtype; prep private.study_model_preparations%rowtype; current_binding jsonb; v_response jsonb;
begin
  perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
  select * into i from private.study_validation_intents where id=p_intent_id;
  perform private.study_require(found,'FORBIDDEN');
  -- Shared ordering: Study, intent, revision, then preparation/job. No service
  -- function acquires a worker row before its owning Study row.
  perform private.study_authorize(i.study_id,i.actor_id,i.client_id,'write');
  select * into i from private.study_validation_intents where id=p_intent_id for update;
  if i.response is not null then
    perform private.study_require(p_outcome='passed','IDEMPOTENCY_CONFLICT'); return i.response;
  end if;
  perform private.study_require(i.expires_at>clock_timestamp(),'CAPABILITY_UNAVAILABLE');
  perform private.study_require((select status='active' from private.studies where id=i.study_id),'FROZEN_REVISION');
  select * into r from private.study_revisions where id=i.revision_id for update;
  perform private.study_require(r.revision=(i.binding->>'expectedRevision')::bigint,'REVISION_CONFLICT');
  perform private.study_require(r.status='draft','FROZEN_REVISION');
  prep:=private.study_qualified_preparation(i.study_id,r.preparation_id);
  current_binding:=jsonb_build_object('revisionId',r.id,'expectedRevision',r.revision,'contentHash',r.content_hash,'modelPreparationId',r.preparation_id,'modelRef',r.model_ref,'definition',r.definition);
  perform private.study_require(current_binding=i.binding and r.model_ref=prep.model_ref and r.definition->'methodRefs'=prep.method_refs,'REFERENCE_MISMATCH');
  perform private.study_require(p_outcome<>'unavailable','CAPABILITY_UNAVAILABLE');
  perform private.study_require(p_outcome='passed' and p_error_code is null,'INVALID_REQUEST');
  update private.study_revisions set status='frozen',validation='passed',revision=revision+1,
    validation_evidence=jsonb_build_object('schemaVersion','lca.study-validation.v1','intentId',i.id,'binding',i.binding,'validatedAt',clock_timestamp()) where id=r.id;
  v_response:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','studyRevision','value',private.study_record('studyRevision',r.id)));
  update private.study_validation_intents set response=v_response,consumed_at=clock_timestamp() where id=i.id;
  return v_response;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end $$;

ALTER FUNCTION "api"."svc_study_revision_freeze_consume_v1"("p_intent_id" "uuid", "p_outcome" "text", "p_error_code" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_revision_freeze_consume_v1"("p_intent_id" "uuid", "p_outcome" "text", "p_error_code" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_revision_freeze_consume_v1"("p_intent_id" "uuid", "p_outcome" "text", "p_error_code" "text") TO "service_role";
