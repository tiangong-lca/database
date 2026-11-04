CREATE OR REPLACE FUNCTION "api"."svc_study_method_assessment_reconcile_v1"("p_resource_type" "text", "p_resource_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_idempotency_key" "text", "p_artifact_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$declare a private.study_method_assessments%rowtype;j private.worker_jobs%rowtype;receipt private.study_service_receipts%rowtype;state text;resource jsonb;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 perform private.study_require(p_resource_type='methodAssessment' and private.study_text(to_jsonb(p_idempotency_key),128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');
 select * into a from private.study_method_assessments where id=p_resource_id;perform private.study_require(found and a.job_id=p_job_id,'REFERENCE_MISMATCH');
 perform 1 from private.studies where id=a.study_id for update;select * into j from private.worker_jobs where id=p_job_id for update;
 perform private.study_require(j.job_kind='study.method_assessment'and j.worker_runtime='calculator'and j.worker_queue='solver'and j.subject_type='study'and j.subject_id=a.id
 and j.requested_by=a.requested_by and j.payload_schema_version='study.method_assessment.request.v1'
 and j.payload_json=jsonb_build_object('schemaVersion','study.method_assessment.request.v1','studyId',a.study_id,'assessmentId',a.id),'REFERENCE_MISMATCH');
 perform private.study_require(p_lease_token is not null and(j.lease_token=p_lease_token or exists(select 1 from private.worker_job_events where job_id=p_job_id and lease_token=p_lease_token)),'FORBIDDEN');
 select * into receipt from private.study_service_receipts where operation='methodAssessment'and study_id=a.study_id and idempotency_key=p_idempotency_key;
 if found then
  perform private.study_require(receipt.job_id=p_job_id and receipt.lease_token=p_lease_token and receipt.request->>'id'=a.id::text,'IDEMPOTENCY_CONFLICT');state:='committed';resource:=receipt.response->'data';
 elsif p_artifact_id is not null and exists(select 1 from private.study_artifacts where id=p_artifact_id) then state:='referenced';
 elsif j.status in('completed','failed','cancelled','blocked')and j.lease_token is null then state:='unreferenced';else state:='pending';end if;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('state',state,'resource',resource,'jobStatus',j.status));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);end$_$;

ALTER FUNCTION "api"."svc_study_method_assessment_reconcile_v1"("p_resource_type" "text", "p_resource_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_idempotency_key" "text", "p_artifact_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_method_assessment_reconcile_v1"("p_resource_type" "text", "p_resource_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_idempotency_key" "text", "p_artifact_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_method_assessment_reconcile_v1"("p_resource_type" "text", "p_resource_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_idempotency_key" "text", "p_artifact_id" "uuid") TO "service_role";
