CREATE OR REPLACE FUNCTION "api"."svc_study_task_fail_v1"("p_resource_type" "text", "p_resource_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_error_code" "text", "p_idempotency_key" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare sid uuid; job uuid; kind text; subject text; result jsonb; old_context text; receipt private.study_service_receipts%rowtype; request jsonb;
begin
  perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
  perform private.study_require(p_error_code=any(array['source_invalid','boundary_undeclared','normalization_underflow','normalization_overflow','numeric_invalid','resource_limit','model_not_solvable','native_execution_failed','job_timeout','job_lease_lost','runtime_unavailable','runtime_failed']) and length(p_idempotency_key) between 1 and 128,'INVALID_REQUEST');
  case p_resource_type
    when 'modelSourceAcquisition' then select study_id,job_id into sid,job from private.study_source_acquisitions where id=p_resource_id; kind:='study.source_acquire'; subject:='acquisitionId';
    when 'modelPreparation' then select study_id,job_id into sid,job from private.study_model_preparations where id=p_resource_id; kind:='study.model_prepare'; subject:='preparationId';
    when 'run' then select study_id,job_id into sid,job from private.study_runs where id=p_resource_id; kind:='study.run'; subject:='runId';
    else perform private.study_require(false,'INVALID_REQUEST');
  end case;
  perform private.study_require(sid is not null and job=p_job_id,'REFERENCE_MISMATCH'); perform 1 from private.studies where id=sid for update;
  request:=jsonb_build_object('id',p_resource_id,'jobId',p_job_id,'leaseToken',p_lease_token,'errorCode',p_error_code);
  select * into receipt from private.study_service_receipts where operation=p_resource_type and study_id=sid and idempotency_key=p_idempotency_key;
  if found then perform private.study_require(receipt.request=request,'IDEMPOTENCY_CONFLICT'); return receipt.response; end if;
  perform private.study_lock_job(sid,p_job_id,p_lease_token,kind,subject,p_resource_id);
  old_context:=current_setting('app.study.task_context',true); perform set_config('app.study.task_context','complete',true);
  result:=private.worker_record_job_result(p_job_id,p_lease_token,'failed',jsonb_build_object('schemaVersion','lca.study-job-receipt.v1','studyId',sid,'resourceType',p_resource_type,'resourceId',p_resource_id),
    'lca.study-job-receipt.v1',null,null,p_error_code,'Study task failed',null,null,null,false);
  perform set_config('app.study.task_context',coalesce(old_context,''),true); perform private.study_require((result->>'ok')::boolean,'FORBIDDEN');
  result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type',p_resource_type,'value',private.study_record(p_resource_type,p_resource_id)));
  insert into private.study_service_receipts values(p_resource_type,sid,p_idempotency_key,p_job_id,p_lease_token,request,result); return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end $$;

ALTER FUNCTION "api"."svc_study_task_fail_v1"("p_resource_type" "text", "p_resource_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_error_code" "text", "p_idempotency_key" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_task_fail_v1"("p_resource_type" "text", "p_resource_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_error_code" "text", "p_idempotency_key" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_task_fail_v1"("p_resource_type" "text", "p_resource_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_error_code" "text", "p_idempotency_key" "text") TO "service_role";
