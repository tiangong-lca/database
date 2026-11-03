CREATE OR REPLACE FUNCTION "private"."study_complete"("p_kind" "text", "p_id" "uuid", "p_job" "uuid", "p_token" "uuid", "p_completion" "jsonb", "p_key" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare sid uuid; job uuid; expected_kind text; subject text; artifact_kind text; artifact_key text;
  p private.study_model_preparations%rowtype; a private.study_source_acquisitions%rowtype; r private.study_runs%rowtype;
  previous private.study_service_receipts%rowtype; request jsonb; response jsonb; result jsonb; artifact uuid; snapshot uuid; jresult jsonb;
begin
  perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
  perform private.study_require(length(p_key) between 1 and 128 and jsonb_typeof(p_completion)='object','INVALID_REQUEST');
  case p_kind
    when 'modelPreparation' then
      select * into p from private.study_model_preparations where id=p_id;
      sid:=p.study_id; job:=p.job_id; expected_kind:='study.model_prepare'; subject:='preparationId'; artifact_kind:='modelInput'; artifact_key:='inputArtifactRef';
    when 'modelSourceAcquisition' then
      select * into a from private.study_source_acquisitions where id=p_id;
      sid:=a.study_id; job:=a.job_id; expected_kind:='study.source_acquire'; subject:='acquisitionId'; artifact_kind:='modelSource'; artifact_key:='sourceArtifactRef';
    when 'run' then
      select * into r from private.study_runs where id=p_id;
      sid:=r.study_id; job:=r.job_id; expected_kind:='study.run'; subject:='runId'; artifact_kind:='runResult'; artifact_key:='resultRef';
    else perform private.study_require(false,'INVALID_REQUEST');
  end case;
  perform private.study_require(sid is not null and job=p_job,'REFERENCE_MISMATCH');
  perform 1 from private.studies where id=sid for update;
  request:=jsonb_build_object('id',p_id,'jobId',p_job,'leaseToken',p_token,'completion',p_completion);
  select * into previous from private.study_service_receipts where operation=p_kind and study_id=sid and idempotency_key=p_key;
  if found then
    perform private.study_require(previous.request=request,'IDEMPOTENCY_CONFLICT');
    -- A terminal acknowledgement may be recovered using its original exact lease;
    -- a fresh or foreign lease cannot impersonate the committed completion.
    perform private.study_require(previous.job_id=p_job and previous.lease_token=p_token,'FORBIDDEN');
    return previous.response;
  end if;
  perform private.study_validate_task_completion(p_kind,p_id,p_completion);
  perform private.study_lock_job(sid,p_job,p_token,expected_kind,subject,p_id);
  if p_kind='modelPreparation' then
    perform private.study_require(p.model_ref is null,'IDEMPOTENCY_CONFLICT');
    perform private.study_require(p_completion->'calculationContractRef'=p.calculation_contract_ref and p_completion->>'profileId'=p.profile_id,'REFERENCE_MISMATCH');
    perform private.study_require(private.study_keys(p_completion->'modelRef',array['type','modelRevisionId','contentHash','digestScope'])
      and p_completion->'modelRef'->>'type'='modelRevision' and p_completion->'modelRef'->>'digestScope'='worker_prepared_model'
      and private.study_text(p_completion->'modelRef'->'contentHash',64,'^[0-9a-f]{64}$')
      and private.study_text(p_completion->'modelRef'->'modelRevisionId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'REFERENCE_MISMATCH');
    perform private.study_require(p_completion->>'inputHash' is null or p_completion->>'inputHash' ~ '^[0-9a-f]{64}$','REFERENCE_MISMATCH');
    perform private.study_require(p.source->>'type'<>'scenarioRevision' or p_completion->>'inputHash' is not null,'REFERENCE_MISMATCH');
  elsif p_kind='modelSourceAcquisition' then
    perform private.study_require(a.snapshot_id is null,'IDEMPOTENCY_CONFLICT');
    perform private.study_require(p_completion->'originRef'=a.origin_ref and length(p_completion->>'licenseRef') between 1 and 128
      and length(p_completion->>'issuerId') between 1 and 128 and p_completion->>'observedAt' is not null,'REFERENCE_MISMATCH');
    perform private.study_require(p_completion->'sourceAuthorization'->>'schemaVersion'='lca.study-source-authorization.v1'
      and p_completion->'sourceAuthorization'->>'requestedBy'=a.requested_by::text
      and p_completion->'sourceAuthorization'->'originRef'=a.origin_ref
      and jsonb_typeof(p_completion->'sourceAuthorization'->'sourceScope')='array','REFERENCE_MISMATCH');
  else
    perform private.study_require(r.result_artifact_id is null,'IDEMPOTENCY_CONFLICT');
    perform private.study_require(p_completion->>'inputHash'=r.input_hash and p_completion->'calculationContractRef'=r.calculation_contract_ref,'REFERENCE_MISMATCH');
  end if;
  artifact:=private.study_store_artifact(sid,p_completion->artifact_key,p_completion->>'storageBucket',p_completion->>'storageObjectPath',artifact_kind);
  if p_kind='modelPreparation' then
    update private.study_model_preparations set model_ref=p_completion->'modelRef',input_artifact_id=artifact,input_hash=p_completion->>'inputHash' where id=p_id;
  elsif p_kind='modelSourceAcquisition' then
    snapshot:=(p_completion->>'snapshotId')::uuid;
    insert into private.study_source_snapshots(id,study_id,acquisition_id,origin_ref,artifact_id,license_ref,issuer_id,observed_at,source_authorization)
      values(snapshot,sid,p_id,a.origin_ref,artifact,p_completion->>'licenseRef',p_completion->>'issuerId',(p_completion->>'observedAt')::timestamptz,p_completion->'sourceAuthorization');
    update private.study_source_acquisitions set snapshot_id=snapshot where id=p_id;
  else update private.study_runs set result_artifact_id=artifact where id=p_id; end if;
  -- Generic worker_job_payload(false) includes result_json. Never place private
  -- source scope, model/numerics or storage locators in that shared projection.
  perform set_config('app.study.task_context','complete',true);
  jresult:=private.worker_record_job_result(p_job,p_token,'completed',
    jsonb_build_object('schemaVersion','lca.study-job-receipt.v1','studyId',sid,'resourceType',p_kind,'resourceId',p_id),
    'lca.study-job-receipt.v1',p_completion->artifact_key);
  perform set_config('app.study.task_context','',true);
  perform private.study_require((jresult->>'ok')::boolean,'FORBIDDEN');
  perform private.study_assert_provenance(sid);
  response:=jsonb_build_object('ok',true,'data',jsonb_build_object('type',p_kind,'value',private.study_record(p_kind,p_id)));
  insert into private.study_service_receipts values(p_kind,sid,p_key,p_job,p_token,request,response);
  return response;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or numeric_value_out_of_range or not_null_violation or check_violation or invalid_datetime_format then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');
end $_$;

ALTER FUNCTION "private"."study_complete"("p_kind" "text", "p_id" "uuid", "p_job" "uuid", "p_token" "uuid", "p_completion" "jsonb", "p_key" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_complete"("p_kind" "text", "p_id" "uuid", "p_job" "uuid", "p_token" "uuid", "p_completion" "jsonb", "p_key" "text") FROM PUBLIC;
