CREATE OR REPLACE FUNCTION "api"."svc_study_analysis_read_input_v1"("p_analysis_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$ declare a private.study_analyses%rowtype; inputs jsonb; begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 select * into a from private.study_analyses where id=p_analysis_id;
 perform private.study_require(found and a.job_id=p_job_id,'REFERENCE_MISMATCH');
 perform private.study_authorize(a.study_id,a.requested_by,a.requested_client_id,'write');
 perform private.study_analysis_rights(a.study_id,a.config,a.requested_by,a.requested_client_id);
 perform private.study_analysis_require_current(a.study_id,a.config);
 perform private.study_analysis_lock_job(a.study_id,p_job_id,p_lease_token,p_analysis_id);
 select jsonb_agg(jsonb_build_object('run',private.study_record('run',r.id),'revision',private.study_record('studyRevision',r.study_revision_id),
 'scenario',private.study_record('scenarioRevision',r.scenario_id),'preparation',private.study_record('modelPreparation',r.preparation_id),
 'preparedArtifact',private.study_private_artifact(a.study_id,p.input_artifact_id),'resultArtifact',private.study_private_artifact(a.study_id,r.result_artifact_id)) order by l.ordinal)
 into inputs from private.study_analysis_runs l join private.study_runs r on r.study_id=l.study_id and r.id=l.run_id
 join private.study_model_preparations p on p.study_id=r.study_id and p.id=r.preparation_id where l.analysis_id=a.id;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('schemaVersion','lca.study-analysis-input.v1','analysis',private.study_analysis_record(a.id)-'comparability'-'factsRef','runs',inputs));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end $$;

ALTER FUNCTION "api"."svc_study_analysis_read_input_v1"("p_analysis_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_study_analysis_read_input_v1"("p_analysis_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_study_analysis_read_input_v1"("p_analysis_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid") TO "service_role";
