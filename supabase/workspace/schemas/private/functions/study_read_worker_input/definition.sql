CREATE OR REPLACE FUNCTION "private"."study_read_worker_input"("p_kind" "text", "p_id" "uuid", "p_job" "uuid", "p_token" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare p private.study_model_preparations%rowtype; r private.study_runs%rowtype; sid uuid; actor uuid; client text; snapshot uuid; result jsonb;
begin
  perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
  if p_kind='modelPreparation' then
    select * into p from private.study_model_preparations where id=p_id; sid:=p.study_id; client:=p.requested_client_id;
    perform private.study_require(p.job_id=p_job,'REFERENCE_MISMATCH');
  else
    select * into r from private.study_runs where id=p_id; sid:=r.study_id; client:=r.requested_client_id;
    perform private.study_require(r.job_id=p_job,'REFERENCE_MISMATCH');
  end if;
  select requested_by into actor from private.worker_jobs where id=p_job;
  perform private.study_authorize(sid,actor,client,'write');
  perform private.study_lock_job(sid,p_job,p_token,case p_kind when 'modelPreparation' then 'study.model_prepare' else 'study.run' end,
    case p_kind when 'modelPreparation' then 'preparationId' else 'runId' end,p_id);
  if p_kind='modelPreparation' then
    snapshot:=case when p.source_snapshot_id is not null then p.source_snapshot_id else private.study_preparation_snapshot(sid,(select preparation_id from private.study_revisions where id=p.source_study_revision_id)) end;
    perform private.study_snapshot_rights(snapshot,actor,client);
    result:=jsonb_build_object('preparation',private.study_record('modelPreparation',p.id),'sourceDocument',p.source_document,'methodRefs',p.method_refs);
  else
    snapshot:=private.study_preparation_snapshot(sid,r.preparation_id); perform private.study_snapshot_rights(snapshot,actor,client);
    result:=jsonb_build_object('run',private.study_record('run',r.id),'preparation',private.study_record('modelPreparation',r.preparation_id),
      'revision',private.study_record('studyRevision',r.study_revision_id),'scenario',private.study_record('scenarioRevision',r.scenario_id),
      'preparedArtifact',private.study_private_artifact(sid,(select input_artifact_id from private.study_model_preparations where id=r.preparation_id)));
  end if;
  return jsonb_build_object('ok',true,'data',result);
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end $$;

ALTER FUNCTION "private"."study_read_worker_input"("p_kind" "text", "p_id" "uuid", "p_job" "uuid", "p_token" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_read_worker_input"("p_kind" "text", "p_id" "uuid", "p_job" "uuid", "p_token" "uuid") FROM PUBLIC;
