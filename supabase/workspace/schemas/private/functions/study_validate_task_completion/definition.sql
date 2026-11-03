CREATE OR REPLACE FUNCTION "private"."study_validate_task_completion"("p_kind" "text", "p_id" "uuid", "p_completion" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare sid uuid; actor uuid; client text; snapshot uuid; a private.study_source_acquisitions%rowtype; p private.study_model_preparations%rowtype; r private.study_runs%rowtype;
begin
  if p_kind='modelSourceAcquisition' then
    select * into a from private.study_source_acquisitions where id=p_id; sid:=a.study_id; actor:=a.requested_by; client:=a.requested_client_id;
    perform private.study_authorize(sid,actor,client,'write');
    perform private.study_require(a.source_packet is not null and p_completion->'sourceAuthorization'=a.source_packet->'sourceAuthorization'
      and p_completion->'originRef'=a.source_packet->'originRef' and p_completion->>'licenseRef'=a.source_packet->>'licenseRef'
      and p_completion->>'issuerId'=a.source_packet->>'issuerId' and p_completion->>'observedAt'=a.source_packet->>'observedAt'
      and p_completion->'sourceArtifactRef'->>'schemaVersion'='lca.study-source-snapshot.v1'
      and p_completion->'sourceArtifactRef'->>'mediaType'='application/json','REFERENCE_MISMATCH');
    perform private.study_source_rights(a.source_packet->'sourceAuthorization'->'sourceScope',actor,client);
  elsif p_kind='modelPreparation' then
    select * into p from private.study_model_preparations where id=p_id; sid:=p.study_id; client:=p.requested_client_id;
    select requested_by into actor from private.worker_jobs where id=p.job_id;
    perform private.study_authorize(sid,actor,client,'write');
    snapshot:=case when p.source_snapshot_id is not null then p.source_snapshot_id else private.study_preparation_snapshot(sid,(select preparation_id from private.study_revisions where id=p.source_study_revision_id)) end;
    perform private.study_snapshot_rights(snapshot,actor,client);
  elsif p_kind='run' then
    select * into r from private.study_runs where id=p_id; sid:=r.study_id; client:=r.requested_client_id;
    select requested_by into actor from private.worker_jobs where id=r.job_id;
    perform private.study_authorize(sid,actor,client,'write'); snapshot:=private.study_preparation_snapshot(sid,r.preparation_id);
    perform private.study_snapshot_rights(snapshot,actor,client);
  else perform private.study_require(false,'INVALID_REQUEST'); end if;
end $$;

ALTER FUNCTION "private"."study_validate_task_completion"("p_kind" "text", "p_id" "uuid", "p_completion" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_validate_task_completion"("p_kind" "text", "p_id" "uuid", "p_completion" "jsonb") FROM PUBLIC;
