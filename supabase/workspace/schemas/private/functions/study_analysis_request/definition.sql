CREATE OR REPLACE FUNCTION "private"."study_analysis_request"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '15s'
    AS $$
declare sid uuid:=(p_request->>'studyId')::uuid; actor uuid:=auth.uid(); client text:=nullif(auth.jwt()->>'client_id','');
 req jsonb:=p_request-'schemaVersion'-'requestId'-'idempotencyKey'; key text:=p_request->>'idempotencyKey';
 previous private.study_command_receipts%rowtype; aid uuid:=gen_random_uuid(); job uuid; result jsonb;
 old_role text; old_context text; s private.studies%rowtype;
begin
 perform private.study_reporting_envelope(p_request,true);
 perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','idempotencyKey','operation','studyId','profileId','config','configHash'])
  and p_request->>'operation'='analysis.request' and p_request->>'profileId'='lca.study-analysis-explicit-v1'
  and private.study_analysis_config_valid(p_request->'config'),'INVALID_REQUEST');
 perform private.study_require(p_request->>'configHash'=private.study_analysis_config_hash(p_request->'config'),'REFERENCE_MISMATCH');
 perform private.study_authorize(sid,actor,client,'write');
 -- Live input rights precede receipt recovery as well as fresh admission.
 perform private.study_analysis_rights(sid,p_request->'config',actor,client);
 select * into previous from private.study_command_receipts where actor_id=actor and operation='analysis.request' and scope=sid::text and idempotency_key=key;
 if found then perform private.study_require(previous.request=req,'IDEMPOTENCY_CONFLICT'); return previous.response; end if;
 perform private.study_analysis_require_current(sid,p_request->'config');
 select * into s from private.studies where id=sid;
 perform private.study_require(s.status='active','FROZEN_REVISION');
 perform private.study_require((select analysis_enabled from private.study_reporting_config where singleton),'CAPABILITY_UNAVAILABLE');
 old_role:=current_setting('request.jwt.claim.role',true); old_context:=current_setting('app.study.task_context',true);
 perform set_config('request.jwt.claim.role','service_role',true); perform set_config('app.study.task_context','enqueue',true);
 result:=private.worker_enqueue_job('study.analysis',jsonb_build_object('schemaVersion','study.analysis.request.v1','studyId',sid,'analysisId',aid),
 'study.analysis.request.v1','study',aid,null,actor,'user',s.team_id,actor::text||':'||sid::text||':study.analysis:'||key,
 private.study_content_hash('lca.study-job-request.v1',req),null,0,null,null,'user');
 perform set_config('request.jwt.claim.role',coalesce(old_role,''),true); perform set_config('app.study.task_context',coalesce(old_context,''),true);
 perform private.study_require((result->>'ok')::boolean,'CAPABILITY_UNAVAILABLE'); job:=(result->'data'->>'id')::uuid;
 insert into private.study_analyses(id,study_id,profile_id,config,config_hash,job_id,requested_by,requested_client_id)
 values(aid,sid,p_request->>'profileId',p_request->'config',p_request->>'configHash',job,actor,client);
 insert into private.study_analysis_runs(study_id,analysis_id,ordinal,run_id)
 select sid,aid,n,(v#>>'{}')::uuid from jsonb_array_elements(p_request->'config'->'runIds') with ordinality e(v,n);
 result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','analysis','value',private.study_analysis_record(aid)));
 insert into private.study_command_receipts values(actor,'analysis.request',sid::text,key,req,result,clock_timestamp()); return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range or not_null_violation or check_violation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');
end $$;

ALTER FUNCTION "private"."study_analysis_request"("p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_analysis_request"("p_request" "jsonb") FROM PUBLIC;
