CREATE OR REPLACE FUNCTION "private"."study_method_report_rights"("p_study" "uuid", "p_runs" "jsonb", "p_assessments" "jsonb", "p_actor" "uuid", "p_client" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare a private.study_method_assessments%rowtype;begin
 perform private.study_authorize(p_study,p_actor,p_client,'read');perform private.study_require(private.study_report_ids(p_runs,1,1) and private.study_report_ids(p_assessments,1,1),'INVALID_REQUEST');
 select * into a from private.study_method_assessments where study_id=p_study and id=(p_assessments->>0)::uuid;
 perform private.study_require(found and a.baseline_run_id::text=p_runs->>0 and a.facts_artifact_id is not null and exists(select 1 from private.worker_jobs where id=a.job_id and status='completed'),'REFERENCE_MISMATCH');
 perform private.study_require(a.source_snapshot_id=private.study_advanced_rights(p_study,a.baseline_run_id,p_actor,p_client),'REFERENCE_MISMATCH');
 perform private.study_method_evidence_refs(p_study,a.config,p_actor,p_client);
 return jsonb_build_array((select ref from private.study_artifacts where study_id=p_study and id=a.facts_artifact_id));
end$$;

ALTER FUNCTION "private"."study_method_report_rights"("p_study" "uuid", "p_runs" "jsonb", "p_assessments" "jsonb", "p_actor" "uuid", "p_client" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_method_report_rights"("p_study" "uuid", "p_runs" "jsonb", "p_assessments" "jsonb", "p_actor" "uuid", "p_client" "text") FROM PUBLIC;
