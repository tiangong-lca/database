CREATE OR REPLACE FUNCTION "private"."study_private_artifact"("p_study" "uuid", "p_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$ declare v jsonb; begin
  select jsonb_build_object('studyId',study_id,'artifactRef',ref,'storageBucket',bucket,'storageObjectPath',object_path)
    into v from private.study_artifacts where study_id=p_study and id=p_id;
  perform private.study_require(v is not null,'REFERENCE_MISMATCH'); return v;
end $$;

ALTER FUNCTION "private"."study_private_artifact"("p_study" "uuid", "p_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_private_artifact"("p_study" "uuid", "p_id" "uuid") FROM PUBLIC;
