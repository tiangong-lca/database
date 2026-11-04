CREATE OR REPLACE FUNCTION "private"."study_report_advanced_rights"("p_study" "uuid", "p_runs" "jsonb", "p_analyses" "jsonb", "p_actor" "uuid", "p_client" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare aid text;a private.study_advanced_analyses%rowtype;refs jsonb:='[]'::jsonb;begin
 perform private.study_authorize(p_study,p_actor,p_client,'read');perform private.study_require(private.study_report_ids(p_runs,1,1) and private.study_report_ids(p_analyses,1,2),'INVALID_REQUEST');
 perform private.study_advanced_rights(p_study,(p_runs->>0)::uuid,p_actor,p_client);
 for aid in select jsonb_array_elements_text(p_analyses) loop
  select * into a from private.study_advanced_analyses where study_id=p_study and id=aid::uuid;
  perform private.study_require(found and a.baseline_run_id::text=p_runs->>0 and a.facts_artifact_id is not null
   and exists(select 1 from private.worker_jobs where id=a.job_id and status='completed'),'REFERENCE_MISMATCH');
  perform private.study_require(a.source_snapshot_id=private.study_advanced_rights(p_study,a.baseline_run_id,p_actor,p_client),'REFERENCE_MISMATCH');
  refs:=refs||jsonb_build_array((select ref from private.study_artifacts where id=a.facts_artifact_id));
 end loop;return refs;
end$$;

ALTER FUNCTION "private"."study_report_advanced_rights"("p_study" "uuid", "p_runs" "jsonb", "p_analyses" "jsonb", "p_actor" "uuid", "p_client" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_report_advanced_rights"("p_study" "uuid", "p_runs" "jsonb", "p_analyses" "jsonb", "p_actor" "uuid", "p_client" "text") FROM PUBLIC;
