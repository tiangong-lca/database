CREATE OR REPLACE FUNCTION "private"."study_task_control"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare actor uuid:=auth.uid(); client text:=nullif(auth.jwt()->>'client_id',''); sid uuid:=(p_request->>'studyId')::uuid;
  op text:=p_request->>'operation'; rid uuid:=(p_request->'resource'->>'id')::uuid; typ text:=p_request->'resource'->>'type'; job uuid;
  j private.worker_jobs%rowtype; old_role text; old_context text; result jsonb; previous private.study_command_receipts%rowtype;
  request jsonb:=p_request-'schemaVersion'-'requestId'-'idempotencyKey'; key text:=p_request->>'idempotencyKey';
begin
  perform private.study_require(actor is not null and not coalesce(util.is_service_request(),false),'AUTH_REQUIRED');
  perform private.study_require(p_request->>'schemaVersion'='lca.study-api.v2' and private.study_keys(p_request->'resource',array['type','id'])
    and op in ('task.read','task.cancel'),'INVALID_REQUEST');
  perform private.study_authorize(sid,actor,client,case op when 'task.read' then 'read' else 'write' end);
  job:=private.study_resource_job(sid,typ,rid);
  if op='task.cancel' then
    perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','idempotencyKey','studyId','resource','reason'])
      and private.study_text(p_request->'reason',512) and private.study_text(p_request->'idempotencyKey',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');
    select * into previous from private.study_command_receipts where actor_id=actor and operation=op and scope=sid::text and idempotency_key=key;
    if found then perform private.study_require(previous.request=request,'IDEMPOTENCY_CONFLICT'); return previous.response; end if;
    old_role:=current_setting('request.jwt.claim.role',true); old_context:=current_setting('app.study.task_context',true);
    perform set_config('request.jwt.claim.role','service_role',true); perform set_config('app.study.task_context','cancel',true);
    result:=private.worker_cancel_job(job,actor,'Study task cancelled');
    perform set_config('request.jwt.claim.role',coalesce(old_role,''),true); perform set_config('app.study.task_context',coalesce(old_context,''),true);
    perform private.study_require((result->>'ok')::boolean,'REVISION_CONFLICT');
  else
    perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','studyId','resource']),'INVALID_REQUEST');
  end if;
  select * into j from private.worker_jobs where id=job;
  result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','task','value',jsonb_build_object('studyId',sid,'resource',p_request->'resource',
    'execution',jsonb_build_object('jobId',job,'status',j.status,'phase',case when j.phase in ('queued','source_capture','model_prepare','solve','complete','cancelled','study_start','study_native','study_artifact','study_publish') then j.phase else null end,'progress',j.progress),
    'errorCode',case when j.error_code=any(array['source_invalid','boundary_undeclared','normalization_underflow','normalization_overflow','numeric_invalid','resource_limit','model_not_solvable','native_execution_failed','job_timeout','job_lease_lost','runtime_unavailable','runtime_failed']) then j.error_code else null end)));
  if op='task.cancel' then insert into private.study_command_receipts values(actor,op,sid::text,key,request,result,clock_timestamp()); end if;
  return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
end $_$;

ALTER FUNCTION "private"."study_task_control"("p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_task_control"("p_request" "jsonb") FROM PUBLIC;
