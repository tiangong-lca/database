CREATE OR REPLACE FUNCTION "api"."svc_study_analysis_advanced_complete_v1"("p_analysis_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_completion" "jsonb", "p_idempotency_key" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare a private.study_advanced_analyses%rowtype;previous private.study_service_receipts%rowtype;request jsonb;result jsonb;artifact uuid;old_context text;snapshot uuid;
begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');perform private.study_require(private.study_text(to_jsonb(p_idempotency_key),128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');
 select * into a from private.study_advanced_analyses where id=p_analysis_id;perform private.study_require(found and a.job_id=p_job_id,'REFERENCE_MISMATCH');
 perform private.study_authorize(a.study_id,a.requested_by,a.requested_client_id,'write');snapshot:=private.study_advanced_rights(a.study_id,a.baseline_run_id,a.requested_by,a.requested_client_id);
 perform private.study_require(snapshot=a.source_snapshot_id,'REFERENCE_MISMATCH');request:=jsonb_build_object('id',p_analysis_id,'jobId',p_job_id,'leaseToken',p_lease_token,'completion',p_completion);
 select * into previous from private.study_service_receipts where operation='analysisAdvanced' and study_id=a.study_id and idempotency_key=p_idempotency_key;
 if found then perform private.study_require(previous.request=request and previous.job_id=p_job_id and previous.lease_token=p_lease_token,'IDEMPOTENCY_CONFLICT');return previous.response;end if;
 perform private.study_analysis_require_current(a.study_id,jsonb_build_object('runIds',jsonb_build_array(a.baseline_run_id)));perform private.study_advanced_lock_job(a.study_id,p_job_id,p_lease_token,a.id);
 select * into a from private.study_advanced_analyses where id=p_analysis_id for update;
 perform private.study_require(a.facts_artifact_id is null and private.study_keys(p_completion,array['profileId','configHash','factsRef','storageBucket','storageObjectPath'])
 and p_completion->>'profileId'=a.profile_id and p_completion->>'configHash'=a.config_hash and p_completion->'factsRef'->>'schemaVersion'='lca.study-analysis-facts.v2'
 and p_completion->'factsRef'->>'mediaType'='application/json','REFERENCE_MISMATCH');
 artifact:=private.study_store_artifact(a.study_id,p_completion->'factsRef',p_completion->>'storageBucket',p_completion->>'storageObjectPath','analysisFacts');
 update private.study_advanced_analyses set facts_artifact_id=artifact where id=a.id;old_context:=current_setting('app.study.task_context',true);perform set_config('app.study.task_context','complete',true);
 result:=private.worker_record_job_result(p_job_id,p_lease_token,'completed',jsonb_build_object('schemaVersion','lca.study-job-receipt.v1','studyId',a.study_id,'resourceType','analysis','resourceId',a.id),'lca.study-job-receipt.v1',p_completion->'factsRef');
 perform set_config('app.study.task_context',coalesce(old_context,''),true);perform private.study_require((result->>'ok')::boolean,'FORBIDDEN');
 result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','analysis','value',private.study_advanced_record(a.id)));
 insert into private.study_service_receipts values('analysisAdvanced',a.study_id,p_idempotency_key,p_job_id,p_lease_token,request,result);return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or numeric_value_out_of_range or not_null_violation or check_violation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');end$_$;

ALTER FUNCTION "api"."svc_study_analysis_advanced_complete_v1"("p_analysis_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_completion" "jsonb", "p_idempotency_key" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_analysis_advanced_complete_v1"("p_analysis_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_completion" "jsonb", "p_idempotency_key" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_analysis_advanced_complete_v1"("p_analysis_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_completion" "jsonb", "p_idempotency_key" "text") TO "service_role";
