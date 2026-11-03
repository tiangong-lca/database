CREATE OR REPLACE FUNCTION "private"."study_analysis_rights"("p_study" "uuid", "p_config" "jsonb", "p_actor" "uuid", "p_client" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$ declare rid text; r private.study_runs%rowtype; begin
 perform private.study_authorize(p_study,p_actor,p_client,'read');
 for rid in select jsonb_array_elements_text(p_config->'runIds') loop
  select * into r from private.study_runs where study_id=p_study and id=rid::uuid for share;
  perform private.study_require(found and r.result_artifact_id is not null
   and exists(select 1 from private.worker_jobs where id=r.job_id and status='completed'),'REFERENCE_MISMATCH');
  perform private.study_require(exists(select 1 from private.study_revisions where study_id=p_study and id=r.study_revision_id and status='frozen')
   and exists(select 1 from private.study_scenarios where study_id=p_study and id=r.scenario_id and status='frozen' and study_revision_id=r.study_revision_id
    and preparation_id=r.preparation_id and effective_model_ref=r.model_ref),'REFERENCE_MISMATCH');
  perform private.study_require(exists(select 1 from private.study_model_preparations p join private.worker_jobs j on j.id=p.job_id where p.study_id=p_study and p.id=r.preparation_id
   and p.model_ref=r.model_ref and p.input_hash=r.input_hash and p.profile_id=r.profile_id and p.calculation_contract_ref=r.calculation_contract_ref and p.input_artifact_id is not null and j.status='completed'),'REFERENCE_MISMATCH');
  perform private.study_reporting_snapshot_rights(private.study_preparation_snapshot(p_study,r.preparation_id),p_actor,p_client);
 end loop;
end $$;

ALTER FUNCTION "private"."study_analysis_rights"("p_study" "uuid", "p_config" "jsonb", "p_actor" "uuid", "p_client" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_analysis_rights"("p_study" "uuid", "p_config" "jsonb", "p_actor" "uuid", "p_client" "text") FROM PUBLIC;
