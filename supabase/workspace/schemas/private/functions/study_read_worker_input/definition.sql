CREATE OR REPLACE FUNCTION "private"."study_read_worker_input"("p_kind" "text", "p_id" "uuid", "p_job" "uuid", "p_token" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare p private.study_model_preparations%rowtype; r private.study_runs%rowtype; sid uuid; result jsonb;
begin
  perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
  if p_kind='modelPreparation' then
    select * into p from private.study_model_preparations where id=p_id;
    sid:=p.study_id; perform private.study_require(p.job_id=p_job,'REFERENCE_MISMATCH');
    perform private.study_lock_job(sid,p_job,p_token,'study.model_prepare','preparationId',p_id);
    result:=jsonb_build_object('preparation',private.study_record('modelPreparation',p.id),'sourceDocument',p.source_document,'methodRefs',p.method_refs);
  else
    select * into r from private.study_runs where id=p_id;
    sid:=r.study_id; perform private.study_require(r.job_id=p_job,'REFERENCE_MISMATCH');
    perform private.study_lock_job(sid,p_job,p_token,'study.run','runId',p_id);
    result:=jsonb_build_object('run',private.study_record('run',r.id),'preparation',private.study_record('modelPreparation',r.preparation_id),'revision',private.study_record('studyRevision',r.study_revision_id),'scenario',private.study_record('scenarioRevision',r.scenario_id));
  end if;
  return jsonb_build_object('ok',true,'data',result);
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end $$;

ALTER FUNCTION "private"."study_read_worker_input"("p_kind" "text", "p_id" "uuid", "p_job" "uuid", "p_token" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_read_worker_input"("p_kind" "text", "p_id" "uuid", "p_job" "uuid", "p_token" "uuid") FROM PUBLIC;
