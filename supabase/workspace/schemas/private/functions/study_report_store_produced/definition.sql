CREATE OR REPLACE FUNCTION "private"."study_report_store_produced"("p_study" "uuid", "p_artifact" "jsonb", "p_id" "uuid", "p_type" "text", "p_schema" "text", "p_name" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$begin
 perform private.study_require(private.study_keys(p_artifact,array['studyId','artifactRef','storageBucket','storageObjectPath'])
 and p_artifact->>'studyId'=p_study::text and p_artifact->'artifactRef'->>'id'=p_id::text and p_artifact->'artifactRef'->>'schemaVersion'=p_schema
 and p_artifact->'artifactRef'->>'mediaType'='application/json' and p_artifact->>'storageBucket'='study-artifacts'
 and p_artifact->>'storageObjectPath'='study/'||p_study::text||'/'||p_id::text||'/'||p_name||'.json','REFERENCE_MISMATCH');
 return private.study_store_artifact(p_study,p_artifact->'artifactRef',p_artifact->>'storageBucket',p_artifact->>'storageObjectPath',p_type);
end$$;

ALTER FUNCTION "private"."study_report_store_produced"("p_study" "uuid", "p_artifact" "jsonb", "p_id" "uuid", "p_type" "text", "p_schema" "text", "p_name" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_report_store_produced"("p_study" "uuid", "p_artifact" "jsonb", "p_id" "uuid", "p_type" "text", "p_schema" "text", "p_name" "text") FROM PUBLIC;
