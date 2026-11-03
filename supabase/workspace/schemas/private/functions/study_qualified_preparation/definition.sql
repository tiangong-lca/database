CREATE OR REPLACE FUNCTION "private"."study_qualified_preparation"("p_study" "uuid", "p_id" "uuid") RETURNS "private"."study_model_preparations"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare p private.study_model_preparations%rowtype;
begin
  select * into p from private.study_model_preparations where study_id=p_study and id=p_id;
  perform private.study_require(found,'REFERENCE_MISMATCH');
  perform private.study_require(p.model_ref is not null and p.input_artifact_id is not null
    and exists(select 1 from private.worker_jobs where id=p.job_id and status='completed'),'CAPABILITY_UNAVAILABLE');
  perform private.study_require(exists(select 1 from private.study_profiles where profile_id=p.profile_id and enabled
    and calculation_fingerprint=p.calculation_contract_ref->>'sha256'),'CAPABILITY_UNAVAILABLE');
  return p;
end $$;

ALTER FUNCTION "private"."study_qualified_preparation"("p_study" "uuid", "p_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_qualified_preparation"("p_study" "uuid", "p_id" "uuid") FROM PUBLIC;
