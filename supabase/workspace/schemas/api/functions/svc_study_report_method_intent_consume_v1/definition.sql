CREATE OR REPLACE FUNCTION "api"."svc_study_report_method_intent_consume_v1"("p_intent_id" "uuid", "p_completion" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare i private.study_report_intents%rowtype;r private.study_report_revisions%rowtype;refs jsonb;contentref jsonb;artifact uuid;result jsonb;validation jsonb;claimcount integer;runids jsonb;assessmentids jsonb;binding text;assessmentid uuid;config_hash text;
begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 i:=private.study_method_report_intent_check(p_intent_id);
 select * into i from private.study_report_intents where id=i.id for update;
 if i.response is not null then return i.response;end if;
 if i.operation='report.create' then
  refs:=private.study_method_report_rights(i.study_id,i.request->'runIds',i.request->'methodAssessmentIds',i.actor_id,i.client_id);claimcount:=jsonb_array_length(i.request->'content'->'claims');
 else
  select * into r from private.study_report_revisions where id=i.report_id for update;
  refs:=private.study_method_report_rights(i.study_id,r.run_ids,r.method_assessment_ids,i.actor_id,i.client_id);
  claimcount:=case when i.operation='report.save' then jsonb_array_length(i.request->'content'->'claims') else (r.validation_evidence->>'claimCount')::integer end;
 end if;
 runids:=case when i.operation='report.create'then i.request->'runIds'else r.run_ids end;
 assessmentids:=case when i.operation='report.create'then i.request->'methodAssessmentIds'else r.method_assessment_ids end;
 assessmentid:=(assessmentids->>0)::uuid;select ma.config_hash into config_hash from private.study_method_assessments ma where ma.id=assessmentid;
 binding:=private.study_method_report_binding(i.study_id,runids,assessmentids);
 validation:=p_completion->'validation';
 if i.operation in ('report.create','report.save') then
  perform private.study_require(private.study_keys(p_completion,array['kind','contentArtifact','factsRefs','validation']) and p_completion->>'kind'='validatedContent'
   and p_completion->'factsRefs'=refs,'REFERENCE_MISMATCH');
  contentref:=p_completion->'contentArtifact'->'artifactRef';
  perform private.study_method_report_validation_check(validation,i.report_id,contentref->>'contentHash',claimcount,binding,assessmentid,config_hash);
  artifact:=private.study_report_store_produced(i.study_id,p_completion->'contentArtifact',i.content_artifact_id,'reportContent','lca.study-method-report-content.v1','content');
  if i.operation='report.create' then
   insert into private.study_report_revisions(id,study_id,parent_report_id,author_id,content_hash,content_artifact_id,template_id,run_ids,analysis_ids,method_assessment_ids,facts_refs,validity_snapshot,validation_evidence)
   values(i.report_id,i.study_id,(i.request->>'parentReportRevisionId')::uuid,i.actor_id,contentref->>'contentHash',artifact,i.request->>'templateId',i.request->'runIds','[]'::jsonb,i.request->'methodAssessmentIds',refs,
   private.study_report_validity_snapshot(i.study_id,i.request->'runIds',i.created_at),validation);
   insert into private.study_report_runs select i.study_id,i.report_id,n,v::uuid from jsonb_array_elements_text(i.request->'runIds') with ordinality e(v,n);
   insert into private.study_report_method_assessments select i.study_id,i.report_id,(i.request->'methodAssessmentIds'->>0)::uuid;
  else update private.study_report_revisions set revision=revision+1,content_hash=contentref->>'contentHash',content_artifact_id=artifact,validation_evidence=validation where id=i.report_id;end if;
  result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','reportRevision','value',private.study_method_report_record(i.report_id)));
 elsif i.operation='report.freeze' then
  select ref into contentref from private.study_artifacts where id=r.content_artifact_id;
  perform private.study_require(private.study_keys(p_completion,array['kind','contentRef','validation']) and p_completion->>'kind'='validatedFreeze' and p_completion->'contentRef'=contentref,'REFERENCE_MISMATCH');
  perform private.study_method_report_validation_check(validation,r.id,r.content_hash,claimcount,binding,assessmentid,config_hash);
  update private.study_report_revisions set status='frozen',revision=revision+1,validation_evidence=validation where id=r.id;
  result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','reportRevision','value',private.study_method_report_record(r.id)));
 end if;
 update private.study_report_intents set response=result where id=i.id;
 update private.study_command_receipts set response=result where actor_id=i.actor_id and operation='method.'||i.operation and scope=i.study_id::text and idempotency_key=i.request->>'idempotencyKey';return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range or check_violation or not_null_violation or invalid_datetime_format then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');
end$$;

ALTER FUNCTION "api"."svc_study_report_method_intent_consume_v1"("p_intent_id" "uuid", "p_completion" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_report_method_intent_consume_v1"("p_intent_id" "uuid", "p_completion" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_report_method_intent_consume_v1"("p_intent_id" "uuid", "p_completion" "jsonb") TO "service_role";
