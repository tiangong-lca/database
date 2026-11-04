CREATE OR REPLACE FUNCTION "private"."study_advanced_baseline"("p_study" "uuid", "p_run" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$select jsonb_build_object('run',private.study_record('run',r.id),'revision',private.study_record('studyRevision',r.study_revision_id),
 'scenario',private.study_record('scenarioRevision',r.scenario_id),'preparation',private.study_record('modelPreparation',r.preparation_id),
 'preparedArtifact',private.study_private_artifact(p_study,p.input_artifact_id),'resultArtifact',private.study_private_artifact(p_study,r.result_artifact_id))
 from private.study_runs r join private.study_model_preparations p on p.study_id=r.study_id and p.id=r.preparation_id where r.study_id=p_study and r.id=p_run$$;

ALTER FUNCTION "private"."study_advanced_baseline"("p_study" "uuid", "p_run" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_advanced_baseline"("p_study" "uuid", "p_run" "uuid") FROM PUBLIC;
