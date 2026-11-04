CREATE OR REPLACE FUNCTION "api"."svc_study_method_assessment_fail_v1"("p_resource_type" "text", "p_resource_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_error_code" "text", "p_idempotency_key" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$declare a private.study_method_assessments%rowtype;request jsonb;receipt private.study_service_receipts%rowtype;result jsonb;old_context text;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 perform private.study_require(p_resource_type='methodAssessment' and private.study_text(to_jsonb(p_idempotency_key),128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$')
 and p_error_code=any(array['source_invalid','boundary_undeclared','normalization_underflow','normalization_overflow','numeric_invalid','resource_limit','model_not_solvable','native_execution_failed','job_timeout','job_lease_lost','runtime_unavailable','runtime_failed']),'INVALID_REQUEST');
 select * into a from private.study_method_assessments where id=p_resource_id;perform private.study_require(found and a.job_id=p_job_id,'REFERENCE_MISMATCH');
 perform 1 from private.studies where id=a.study_id for update;
 request:=jsonb_build_object('id',p_resource_id,'jobId',p_job_id,'leaseToken',p_lease_token,'errorCode',p_error_code);
 select * into receipt from private.study_service_receipts where operation='methodAssessment'and study_id=a.study_id and idempotency_key=p_idempotency_key;
 if found then perform private.study_require(receipt.request=request and receipt.job_id=p_job_id and receipt.lease_token=p_lease_token,'IDEMPOTENCY_CONFLICT');return receipt.response;end if;
 perform private.study_method_lock_job(a.study_id,p_job_id,p_lease_token,a.id);old_context:=current_setting('app.study.task_context',true);perform set_config('app.study.task_context','complete',true);
 result:=private.worker_record_job_result(p_job_id,p_lease_token,'failed',jsonb_build_object('schemaVersion','lca.study-job-receipt.v1','studyId',a.study_id,'resourceType','methodAssessment','resourceId',a.id),
 'lca.study-job-receipt.v1',null,null,p_error_code,'Study task failed',null,null,null,false);
 perform set_config('app.study.task_context',coalesce(old_context,''),true);perform private.study_require((result->>'ok')::boolean,'FORBIDDEN');
 result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','methodAssessment','value',private.study_method_record(a.id)));
 insert into private.study_service_receipts values('methodAssessment',a.study_id,p_idempotency_key,p_job_id,p_lease_token,request,result);return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);end$_$;

ALTER FUNCTION "api"."svc_study_method_assessment_fail_v1"("p_resource_type" "text", "p_resource_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_error_code" "text", "p_idempotency_key" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_method_assessment_fail_v1"("p_resource_type" "text", "p_resource_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_error_code" "text", "p_idempotency_key" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_method_assessment_fail_v1"("p_resource_type" "text", "p_resource_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_error_code" "text", "p_idempotency_key" "text") TO "service_role";
