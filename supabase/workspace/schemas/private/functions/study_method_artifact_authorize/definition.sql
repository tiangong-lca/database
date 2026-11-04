CREATE OR REPLACE FUNCTION "private"."study_method_artifact_authorize"("p_study" "uuid", "p_ref" "jsonb", "p_actor" "uuid", "p_client" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare a private.study_artifacts%rowtype;m private.study_method_assessments%rowtype;begin
 perform private.study_authorize(p_study,p_actor,p_client,'read');perform private.study_require((select disclosure_enabled from private.study_runtime_config where singleton),'CAPABILITY_UNAVAILABLE');
 select * into a from private.study_artifacts where study_id=p_study and id=(p_ref->>'id')::uuid;perform private.study_require(found and a.ref=p_ref,'REFERENCE_MISMATCH');
 if p_ref->>'type'='methodAssessmentFacts' and p_ref->>'schemaVersion'='lca.study-method-assessment-facts.v1' then
  select * into m from private.study_method_assessments where study_id=p_study and facts_artifact_id=a.id;
  perform private.study_require(found and exists(select 1 from private.worker_jobs where id=m.job_id and status='completed'),'DISCLOSURE_DENIED');
  perform private.study_advanced_rights(p_study,m.baseline_run_id,p_actor,p_client);perform private.study_method_evidence_refs(p_study,m.config,p_actor,p_client);
 elsif p_ref->>'type'='methodEvidence' and p_ref->>'schemaVersion'='lca.study-method-evidence.v1' then
  perform private.study_require(exists(select 1 from private.study_method_evidence where study_id=p_study and artifact_id=a.id),'DISCLOSURE_DENIED');
 elsif p_ref->>'type' in('modelInput','runResult') then
  perform private.study_require(exists(select 1 from private.study_method_assessments ma join private.study_runs r on r.id=ma.baseline_run_id and r.study_id=ma.study_id
   join private.study_model_preparations p on p.id=r.preparation_id and p.study_id=r.study_id where ma.study_id=p_study and (a.id=r.result_artifact_id or a.id=p.input_artifact_id)),'DISCLOSURE_DENIED');
  return private.study_reporting_artifact_authorize(p_study,p_ref,p_actor,p_client);
 elsif p_ref->>'type'='reportContent' and p_ref->>'schemaVersion'='lca.study-method-report-content.v1' then
  perform private.study_method_report_artifact_authorize(p_study,p_ref,p_actor,p_client);
 else perform private.study_require(false,'DISCLOSURE_DENIED');end if;
 return jsonb_build_object('kind','artifactCapability','studyId',p_study,'artifactRef',a.ref,'storageBucket',a.bucket,'storageObjectPath',a.object_path);
end$$;

ALTER FUNCTION "private"."study_method_artifact_authorize"("p_study" "uuid", "p_ref" "jsonb", "p_actor" "uuid", "p_client" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_method_artifact_authorize"("p_study" "uuid", "p_ref" "jsonb", "p_actor" "uuid", "p_client" "text") FROM PUBLIC;
