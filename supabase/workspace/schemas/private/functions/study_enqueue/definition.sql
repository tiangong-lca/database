CREATE OR REPLACE FUNCTION "private"."study_enqueue"("p_kind" "text", "p_study" "uuid", "p_resource" "uuid", "p_actor" "uuid", "p_team" "uuid", "p_key" "text", "p_request" "jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare old_role text:=current_setting('request.jwt.claim.role',true); old_context text:=current_setting('app.study.task_context',true); result jsonb; subject text;
begin
  subject:=case p_kind when 'study.source_acquire' then 'acquisitionId' when 'study.model_prepare' then 'preparationId' when 'study.run' then 'runId' end;
  perform private.study_require(subject is not null,'INVALID_REQUEST');
  -- This closed postgres-only helper is reached only after actor admission.
  -- Reuse the canonical enqueuer under scoped service context, restoring it
  -- before returning; public requests cannot select either context setting.
  perform set_config('request.jwt.claim.role','service_role',true); perform set_config('app.study.task_context','enqueue',true);
  result:=private.worker_enqueue_job(p_kind,jsonb_build_object('schemaVersion',p_kind||'.request.v1','studyId',p_study,subject,p_resource),
    p_kind||'.request.v1','study',p_resource,null,p_actor,'user',p_team,p_actor::text||':'||p_study::text||':'||p_kind||':'||p_key,
    private.study_content_hash('lca.study-job-request.v1',p_request),null,0,null,null,'user');
  perform set_config('request.jwt.claim.role',coalesce(old_role,''),true); perform set_config('app.study.task_context',coalesce(old_context,''),true);
  perform private.study_require((result->>'ok')::boolean,'CAPABILITY_UNAVAILABLE');
  return (result->'data'->>'id')::uuid;
exception when others then
  perform set_config('request.jwt.claim.role',coalesce(old_role,''),true); perform set_config('app.study.task_context',coalesce(old_context,''),true); raise;
end $$;

ALTER FUNCTION "private"."study_enqueue"("p_kind" "text", "p_study" "uuid", "p_resource" "uuid", "p_actor" "uuid", "p_team" "uuid", "p_key" "text", "p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_enqueue"("p_kind" "text", "p_study" "uuid", "p_resource" "uuid", "p_actor" "uuid", "p_team" "uuid", "p_key" "text", "p_request" "jsonb") FROM PUBLIC;
