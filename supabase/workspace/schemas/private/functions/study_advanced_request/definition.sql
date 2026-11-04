CREATE OR REPLACE FUNCTION "private"."study_advanced_request"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '15s'
    AS $$
declare sid uuid:=(p_request->>'studyId')::uuid;actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');req jsonb:=p_request-'schemaVersion'-'requestId'-'idempotencyKey';
 previous private.study_command_receipts%rowtype;cfg private.study_advanced_config%rowtype;s private.studies%rowtype;aid uuid:=gen_random_uuid();job uuid;snapshot uuid;result jsonb;old_role text;old_context text;
begin
 perform private.study_advanced_envelope(p_request,true);
 perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','idempotencyKey','operation','studyId','profileId','config','configHash'])
 and p_request->>'operation'='analysis.request' and private.study_advanced_config_valid(p_request->'config'),'INVALID_REQUEST');
 perform private.study_require(p_request->>'profileId'=case p_request->'config'->>'kind' when 'sensitivityOat' then 'lca.study-sensitivity-oat.v1' else 'lca.study-uncertainty-bounded.v1' end
 and p_request->>'configHash'=private.study_advanced_config_hash(p_request->'config'),'REFERENCE_MISMATCH');
 perform private.study_authorize(sid,actor,client,'write');snapshot:=private.study_advanced_rights(sid,(p_request->'config'->>'baselineRunId')::uuid,actor,client);
 select * into previous from private.study_command_receipts where actor_id=actor and operation='analysis.advanced.request' and scope=sid::text and idempotency_key=p_request->>'idempotencyKey';
 if found then perform private.study_require(previous.request=req,'IDEMPOTENCY_CONFLICT');return previous.response;end if;
 perform private.study_analysis_require_current(sid,jsonb_build_object('runIds',jsonb_build_array(p_request->'config'->'baselineRunId')));
 select * into s from private.studies where id=sid;perform private.study_require(s.status='active','FROZEN_REVISION');select * into cfg from private.study_advanced_config where singleton for share;
 perform private.study_require(case p_request->'config'->>'kind' when 'sensitivityOat' then cfg.sensitivity_enabled else cfg.uncertainty_enabled end,'CAPABILITY_UNAVAILABLE');
 perform private.study_require(jsonb_array_length(p_request->'config'->'parameters')<=cfg.max_parameters
 and (p_request->'config'->>'kind'<>'uncertainty' or (p_request->'config'->>'sampleCount')::bigint<=cfg.max_samples),'CAPABILITY_UNAVAILABLE');
 old_role:=current_setting('request.jwt.claim.role',true);old_context:=current_setting('app.study.task_context',true);perform set_config('request.jwt.claim.role','service_role',true);perform set_config('app.study.task_context','enqueue',true);
 result:=private.worker_enqueue_job('study.analysis_advanced',jsonb_build_object('schemaVersion','study.analysis_advanced.request.v1','studyId',sid,'analysisId',aid),
 'study.analysis_advanced.request.v1','study',aid,null,actor,'user',s.team_id,actor::text||':'||sid::text||':study.analysis_advanced:'||(p_request->>'idempotencyKey'),
 private.study_content_hash('lca.study-job-request.v1',req),null,0,null,null,'user');
 perform set_config('request.jwt.claim.role',coalesce(old_role,''),true);perform set_config('app.study.task_context',coalesce(old_context,''),true);
 perform private.study_require((result->>'ok')::boolean,'CAPABILITY_UNAVAILABLE');job:=(result->'data'->>'id')::uuid;
 insert into private.study_advanced_analyses(id,study_id,profile_id,config,config_hash,baseline_run_id,source_snapshot_id,job_id,requested_by,requested_client_id)
 values(aid,sid,p_request->>'profileId',p_request->'config',p_request->>'configHash',(p_request->'config'->>'baselineRunId')::uuid,snapshot,job,actor,client);
 result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','analysis','value',private.study_advanced_record(aid)));
 insert into private.study_command_receipts values(actor,'analysis.advanced.request',sid::text,p_request->>'idempotencyKey',req,result,clock_timestamp());return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range or not_null_violation or check_violation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');end$$;

ALTER FUNCTION "private"."study_advanced_request"("p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_advanced_request"("p_request" "jsonb") FROM PUBLIC;
