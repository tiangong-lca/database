CREATE OR REPLACE FUNCTION "private"."study_analysis_artifact_authorize"("p_study" "uuid", "p_ref" "jsonb", "p_actor" "uuid", "p_client" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$ declare a private.study_analyses%rowtype; artifact private.study_artifacts%rowtype; begin
 if p_ref->>'type'<>'analysisFacts' then return private.study_artifact_authorize(p_study,p_ref,p_actor,p_client); end if;
 perform private.study_authorize(p_study,p_actor,p_client,'read');
 perform private.study_require((select disclosure_enabled from private.study_runtime_config where singleton),'CAPABILITY_UNAVAILABLE');
 select * into artifact from private.study_artifacts where study_id=p_study and id=(p_ref->>'id')::uuid;
 perform private.study_require(found and artifact.ref=p_ref,'REFERENCE_MISMATCH');
 select * into a from private.study_analyses where study_id=p_study and facts_artifact_id=artifact.id;
 perform private.study_require(found and exists(select 1 from private.worker_jobs where id=a.job_id and status='completed'),'DISCLOSURE_DENIED');
 perform private.study_analysis_rights(p_study,a.config,p_actor,p_client);
 return jsonb_build_object('kind','artifactCapability','studyId',p_study,'artifactRef',artifact.ref,'storageBucket',artifact.bucket,'storageObjectPath',artifact.object_path);
end $$;

ALTER FUNCTION "private"."study_analysis_artifact_authorize"("p_study" "uuid", "p_ref" "jsonb", "p_actor" "uuid", "p_client" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_analysis_artifact_authorize"("p_study" "uuid", "p_ref" "jsonb", "p_actor" "uuid", "p_client" "text") FROM PUBLIC;
