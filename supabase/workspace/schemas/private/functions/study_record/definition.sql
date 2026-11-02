CREATE OR REPLACE FUNCTION "private"."study_record"("p_kind" "text", "p_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v jsonb;
begin
  case p_kind
  when 'study' then select jsonb_build_object('studyId',id,'revision',revision,'scope',case when team_id is null then jsonb_build_object('kind','user','id',owner_id) else jsonb_build_object('kind','team','id',team_id) end,'title',title,'status',status,'currentRevisionId',current_revision_id) into v from private.studies where id=p_id;
  when 'studyRevision' then select jsonb_build_object('revisionId',id,'studyId',study_id,'revision',revision,'parentRevisionId',parent_revision_id,'status',status,'contentHash',content_hash,'definition',definition,'modelPreparationId',preparation_id,'modelRef',model_ref,'validation',validation) into v from private.study_revisions where id=p_id;
  when 'scenarioRevision' then select jsonb_build_object('scenarioId',scenario_id,'scenarioRevisionId',id,'studyId',study_id,'studyRevisionId',study_revision_id,'parentScenarioRevisionId',parent_scenario_id,'revision',revision,'status',status,'contentHash',content_hash,'overrides',overrides,'modelPreparationId',preparation_id,'effectiveModelRef',effective_model_ref) into v from private.study_scenarios where id=p_id;
  when 'modelPreparation' then select jsonb_build_object('preparationId',p.id,'studyId',p.study_id,'source',p.source,'methodRefs',p.method_refs,'profileId',p.profile_id,'calculationContractRef',p.calculation_contract_ref,'execution',jsonb_build_object('jobId',p.job_id,'status',j.status),'modelRef',p.model_ref,'inputArtifactRef',a.ref,'inputHash',p.input_hash) into v from private.study_model_preparations p join private.worker_jobs j on j.id=p.job_id left join private.study_artifacts a on a.id=p.input_artifact_id where p.id=p_id;
  when 'modelSourceSnapshot' then select jsonb_build_object('snapshotId',s.id,'studyId',s.study_id,'originRef',s.origin_ref,'sourceArtifactRef',a.ref,'digestScope','artifact_bytes_sha256','licenseRef',s.license_ref,'issuerId',s.issuer_id,'observedAt',s.observed_at) into v from private.study_source_snapshots s join private.study_artifacts a on a.id=s.artifact_id where s.id=p_id;
  when 'modelSourceAcquisition' then select jsonb_build_object('acquisitionId',a.id,'studyId',a.study_id,'originRef',a.origin_ref,'execution',jsonb_build_object('jobId',a.job_id,'status',j.status),'snapshot',case when a.snapshot_id is null then null else private.study_record('modelSourceSnapshot',a.snapshot_id) end) into v from private.study_source_acquisitions a join private.worker_jobs j on j.id=a.job_id where a.id=p_id;
  when 'run' then select jsonb_build_object('runId',r.id,'studyId',r.study_id,'studyRevisionId',r.study_revision_id,'scenarioRevisionId',r.scenario_id,'modelPreparationId',r.preparation_id,'effectiveModelRef',r.model_ref,'inputHash',r.input_hash,'profileId',r.profile_id,'calculationContractRef',r.calculation_contract_ref,'engineId','solver-worker','execution',jsonb_build_object('jobId',r.job_id,'status',j.status),'resultRef',a.ref,'validity',jsonb_build_object('status',r.validity,'checkedAt',r.validity_checked_at,'reasonCodes','[]'::jsonb)) into v from private.study_runs r join private.worker_jobs j on j.id=r.job_id left join private.study_artifacts a on a.id=r.result_artifact_id where r.id=p_id;
  else perform private.study_require(false,'CAPABILITY_UNAVAILABLE');
  end case;
  perform private.study_require(v is not null,'FORBIDDEN');
  return v;
end $$;

ALTER FUNCTION "private"."study_record"("p_kind" "text", "p_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_record"("p_kind" "text", "p_id" "uuid") FROM PUBLIC;
