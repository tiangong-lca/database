CREATE OR REPLACE FUNCTION "private"."study_assert_provenance"("p_study" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  perform private.study_require(not exists(
    with recursive edges(a,b) as (
      select 'r:'||id,'p:'||preparation_id from private.study_revisions where study_id=p_study
      union all select 'r:'||id,'r:'||parent_revision_id from private.study_revisions where study_id=p_study and parent_revision_id is not null
      union all select 's:'||id,'r:'||study_revision_id from private.study_scenarios where study_id=p_study
      union all select 's:'||id,'s:'||parent_scenario_id from private.study_scenarios where study_id=p_study and parent_scenario_id is not null
      union all select 's:'||id,'p:'||preparation_id from private.study_scenarios where study_id=p_study and preparation_id is not null
      -- Captured draft source edges exclude the later frozen Scenario's own preparation.
      union all select 'p:'||id,'r:'||source_study_revision_id from private.study_model_preparations where study_id=p_study and source_study_revision_id is not null
      union all select 'p:'||id,'s:'||source_parent_scenario_id from private.study_model_preparations where study_id=p_study and source_parent_scenario_id is not null
    ), reach(a,b) as (
      select a,b from edges
      union select r.a,e.b from reach r join edges e on e.a=r.b
    ) select 1 from reach where a=b
  ),'REFERENCE_MISMATCH');
end $$;

ALTER FUNCTION "private"."study_assert_provenance"("p_study" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_assert_provenance"("p_study" "uuid") FROM PUBLIC;
