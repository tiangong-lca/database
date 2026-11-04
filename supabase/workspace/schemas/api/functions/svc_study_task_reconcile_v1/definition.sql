CREATE OR REPLACE FUNCTION "api"."svc_study_task_reconcile_v1"("p_resource_type" "text", "p_resource_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_idempotency_key" "text", "p_artifact_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare sid uuid; bound_job uuid; j private.worker_jobs%rowtype; receipt private.study_service_receipts%rowtype; state text; resource jsonb;
begin
  perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
  if p_resource_type='analysis' and exists(select 1 from private.study_advanced_analyses where id=p_resource_id and job_id=p_job_id) then return api.svc_study_analysis_advanced_reconcile_v1(p_resource_type,p_resource_id,p_job_id,p_lease_token,p_idempotency_key,p_artifact_id);end if;
  case p_resource_type
    when 'modelSourceAcquisition' then select study_id,job_id into sid,bound_job from private.study_source_acquisitions where id=p_resource_id;
    when 'modelPreparation' then select study_id,job_id into sid,bound_job from private.study_model_preparations where id=p_resource_id;
    when 'run' then select study_id,job_id into sid,bound_job from private.study_runs where id=p_resource_id;
 when 'analysis' then select study_id,job_id into sid,bound_job from private.study_analyses where id=p_resource_id;
    else perform private.study_require(false,'INVALID_REQUEST');
  end case;
  perform private.study_require(sid is not null and bound_job=p_job_id,'REFERENCE_MISMATCH');
  perform 1 from private.studies where id=sid for update;
  select * into j from private.worker_jobs where id=p_job_id for update;
 if p_resource_type='analysis' then
  perform private.study_require(j.job_kind='study.analysis' and j.worker_runtime='calculator' and j.worker_queue='solver' and j.subject_type='study' and j.subject_id=p_resource_id
   and j.payload_schema_version='study.analysis.request.v1' and j.payload_json=jsonb_build_object('schemaVersion','study.analysis.request.v1','studyId',sid,'analysisId',p_resource_id)
   and exists(select 1 from private.study_analyses a where a.id=p_resource_id and a.study_id=sid and a.job_id=p_job_id and a.requested_by=j.requested_by),'REFERENCE_MISMATCH');
 end if;
  perform private.study_require(p_lease_token is not null and (j.lease_token=p_lease_token or exists(
    select 1 from private.worker_job_events where job_id=p_job_id and lease_token=p_lease_token)),'FORBIDDEN');
  select * into receipt from private.study_service_receipts where operation=p_resource_type and study_id=sid and idempotency_key=p_idempotency_key;
  if found then
    perform private.study_require(receipt.job_id=p_job_id and receipt.lease_token=p_lease_token and receipt.request->>'id'=p_resource_id::text,'IDEMPOTENCY_CONFLICT');
    state:='committed'; resource:=receipt.response->'data';
  elsif p_artifact_id is not null and exists(select 1 from private.study_artifacts where id=p_artifact_id) then state:='referenced';
  elsif j.status in ('completed','failed','cancelled','blocked') and j.lease_token is null then state:='unreferenced';
  else state:='pending'; end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('state',state,'resource',resource,'jobStatus',j.status));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end $$;

ALTER FUNCTION "api"."svc_study_task_reconcile_v1"("p_resource_type" "text", "p_resource_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_idempotency_key" "text", "p_artifact_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_task_reconcile_v1"("p_resource_type" "text", "p_resource_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_idempotency_key" "text", "p_artifact_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_task_reconcile_v1"("p_resource_type" "text", "p_resource_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_idempotency_key" "text", "p_artifact_id" "uuid") TO "service_role";
