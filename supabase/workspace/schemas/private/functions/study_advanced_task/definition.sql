CREATE OR REPLACE FUNCTION "private"."study_advanced_task"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare sid uuid:=(p_request->>'studyId')::uuid; actor uuid:=auth.uid(); client text:=nullif(auth.jwt()->>'client_id','');
 op text:=p_request->>'operation'; a private.study_advanced_analyses%rowtype; j private.worker_jobs%rowtype; result jsonb;
 old_role text; old_context text; previous private.study_command_receipts%rowtype; req jsonb:=p_request-'schemaVersion'-'requestId'-'idempotencyKey';
begin
 perform private.study_advanced_envelope(p_request,op='task.cancel');
 perform private.study_require(private.study_keys(p_request->'resource',array['type','id']) and p_request->'resource'->>'type'='analysis','INVALID_REQUEST');
 perform private.study_authorize(sid,actor,client,case when op='task.cancel' then 'write' else 'read' end);
 select * into a from private.study_advanced_analyses where study_id=sid and id=(p_request->'resource'->>'id')::uuid;
 perform private.study_require(found,'FORBIDDEN');
 -- Minimal status/cancellation stays available after source withdrawal and
 -- admission shutdown. No source, result, payload or raw diagnostic is projected.
 perform private.study_require(exists(select 1 from private.worker_jobs bound_job where bound_job.id=a.job_id
 and bound_job.job_kind='study.analysis_advanced' and bound_job.worker_runtime='calculator' and bound_job.worker_queue='solver'
 and bound_job.subject_type='study' and bound_job.subject_id=a.id and bound_job.requested_by=a.requested_by
 and bound_job.payload_schema_version='study.analysis_advanced.request.v1'
 and bound_job.payload_json=jsonb_build_object('schemaVersion','study.analysis_advanced.request.v1','studyId',sid,'analysisId',a.id)),'REFERENCE_MISMATCH');
 if op='task.cancel' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','idempotencyKey','studyId','resource','reason']) and private.study_text(p_request->'reason',512),'INVALID_REQUEST');
  select * into previous from private.study_command_receipts where actor_id=actor and operation='advanced.'||op and scope=sid::text and idempotency_key=p_request->>'idempotencyKey';
  if found then perform private.study_require(previous.request=req,'IDEMPOTENCY_CONFLICT'); return previous.response; end if;
  old_role:=current_setting('request.jwt.claim.role',true); old_context:=current_setting('app.study.task_context',true);
  perform set_config('request.jwt.claim.role','service_role',true); perform set_config('app.study.task_context','cancel',true);
  result:=private.worker_cancel_job(a.job_id,actor,'Study task cancelled');
  perform set_config('request.jwt.claim.role',coalesce(old_role,''),true); perform set_config('app.study.task_context',coalesce(old_context,''),true);
  perform private.study_require((result->>'ok')::boolean,'REVISION_CONFLICT');
 else perform private.study_require(op='task.read' and private.study_keys(p_request,array['schemaVersion','requestId','operation','studyId','resource']),'INVALID_REQUEST'); end if;
 select * into j from private.worker_jobs where id=a.job_id;
 result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','task','value',jsonb_build_object('studyId',sid,'resource',p_request->'resource',
 'execution',jsonb_build_object('jobId',j.id,'status',j.status,'phase',case when j.phase in ('queued','complete','cancelled','study_start','study_native','study_artifact','study_publish') then j.phase else null end,'progress',j.progress),
 'errorCode',case when j.error_code=any(array['source_invalid','boundary_undeclared','normalization_underflow','normalization_overflow','numeric_invalid','resource_limit','model_not_solvable','native_execution_failed','job_timeout','job_lease_lost','runtime_unavailable','runtime_failed']) then j.error_code else null end)));
 if op='task.cancel' then insert into private.study_command_receipts values(actor,'advanced.'||op,sid::text,p_request->>'idempotencyKey',req,result,clock_timestamp()); end if;
 return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
end $$;

ALTER FUNCTION "private"."study_advanced_task"("p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_advanced_task"("p_request" "jsonb") FROM PUBLIC;
