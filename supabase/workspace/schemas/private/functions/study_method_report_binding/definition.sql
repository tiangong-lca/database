CREATE OR REPLACE FUNCTION "private"."study_method_report_binding"("p_study" "uuid", "p_runs" "jsonb", "p_assessments" "jsonb") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare a private.study_method_assessments%rowtype;r jsonb;p jsonb;source_ref jsonb;baseline jsonb;assessment jsonb;refs jsonb;begin
 perform private.study_require(private.study_report_ids(p_runs,1,1)and private.study_report_ids(p_assessments,1,1),'INVALID_REQUEST');
 select * into a from private.study_method_assessments where study_id=p_study and id=(p_assessments->>0)::uuid;
 perform private.study_require(found and a.baseline_run_id::text=p_runs->>0 and a.facts_artifact_id is not null,'REFERENCE_MISMATCH');
 r:=private.study_record('run',a.baseline_run_id);p:=private.study_record('modelPreparation',(r->>'modelPreparationId')::uuid);
 select ar.ref into source_ref from private.study_source_snapshots s join private.study_artifacts ar on ar.study_id=s.study_id and ar.id=s.artifact_id where s.study_id=p_study and s.id=a.source_snapshot_id;
 baseline:=jsonb_build_object('runId',r->'runId','studyId',r->'studyId','studyRevisionId',r->'studyRevisionId','scenarioRevisionId',r->'scenarioRevisionId',
 'effectiveModelRef',r->'effectiveModelRef','inputHash',r->'inputHash','profileId',r->'profileId','engineId',r->'engineId','calculationContractRef',r->'calculationContractRef',
 'resultRef',r->'resultRef','preparedArtifactRef',p->'inputArtifactRef','sourceSnapshotRef',source_ref);
 assessment:=jsonb_build_object('assessmentId',a.id,'profileId',a.profile_id,'configHash',a.config_hash,'moduleRef',a.config->'moduleRef');
 refs:=jsonb_build_array((select ref from private.study_artifacts where study_id=p_study and id=a.facts_artifact_id));
 return private.study_reporting_digest('lca.study-method-report-facts-binding.v1',jsonb_build_object('studyId',p_study,'runIds',p_runs,'methodAssessmentIds',p_assessments,'factsRefs',refs,'baseline',baseline,'assessment',assessment));
end$$;

ALTER FUNCTION "private"."study_method_report_binding"("p_study" "uuid", "p_runs" "jsonb", "p_assessments" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_method_report_binding"("p_study" "uuid", "p_runs" "jsonb", "p_assessments" "jsonb") FROM PUBLIC;
