CREATE OR REPLACE FUNCTION "private"."study_advanced_artifact_authorize"("p_study" "uuid", "p_ref" "jsonb", "p_actor" "uuid", "p_client" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare a private.study_artifacts%rowtype;analysis private.study_advanced_analyses%rowtype;r private.study_report_revisions%rowtype;begin
 perform private.study_authorize(p_study,p_actor,p_client,'read');perform private.study_require((select disclosure_enabled from private.study_runtime_config where singleton),'CAPABILITY_UNAVAILABLE');
 select * into a from private.study_artifacts where study_id=p_study and id=(p_ref->>'id')::uuid;perform private.study_require(found and a.ref=p_ref,'REFERENCE_MISMATCH');
 if p_ref->>'type'='analysisFacts' and p_ref->>'schemaVersion'='lca.study-analysis-facts.v2' then
  select * into analysis from private.study_advanced_analyses where study_id=p_study and facts_artifact_id=a.id;
  perform private.study_require(found and exists(select 1 from private.worker_jobs where id=analysis.job_id and status='completed'),'DISCLOSURE_DENIED');
  perform private.study_advanced_rights(p_study,analysis.baseline_run_id,p_actor,p_client);
 elsif p_ref->>'type'='reportContent' and p_ref->>'schemaVersion'='lca.study-report-content.v2' then
  select * into r from private.study_report_revisions where study_id=p_study and template_id='lca.study-report.v2' and content_artifact_id=a.id;
  perform private.study_require(found,'DISCLOSURE_DENIED');perform private.study_report_advanced_rights(p_study,r.run_ids,r.analysis_ids,p_actor,p_client);
 else perform private.study_require(false,'DISCLOSURE_DENIED');end if;
 return jsonb_build_object('kind','artifactCapability','studyId',p_study,'artifactRef',a.ref,'storageBucket',a.bucket,'storageObjectPath',a.object_path);
end$$;

ALTER FUNCTION "private"."study_advanced_artifact_authorize"("p_study" "uuid", "p_ref" "jsonb", "p_actor" "uuid", "p_client" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_advanced_artifact_authorize"("p_study" "uuid", "p_ref" "jsonb", "p_actor" "uuid", "p_client" "text") FROM PUBLIC;
