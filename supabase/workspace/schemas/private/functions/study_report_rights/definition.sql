CREATE OR REPLACE FUNCTION "private"."study_report_rights"("p_study" "uuid", "p_runs" "jsonb", "p_analyses" "jsonb", "p_actor" "uuid", "p_client" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare rid text;aid text;a private.study_analyses%rowtype;refs jsonb:='[]'::jsonb;begin
 perform private.study_authorize(p_study,p_actor,p_client,'read');
 perform private.study_require(private.study_report_ids(p_runs,1,2) and private.study_report_ids(p_analyses,1,2),'INVALID_REQUEST');
 for rid in select jsonb_array_elements_text(p_runs) loop
  perform private.study_analysis_rights(p_study,jsonb_build_object('runIds',jsonb_build_array(rid)),p_actor,p_client);
 end loop;
 for aid in select jsonb_array_elements_text(p_analyses) loop
  select * into a from private.study_analyses where study_id=p_study and id=aid::uuid;
  perform private.study_require(found and a.facts_artifact_id is not null and exists(select 1 from private.worker_jobs where id=a.job_id and status='completed')
   and a.config->'runIds'<@p_runs,'REFERENCE_MISMATCH');
  perform private.study_analysis_rights(p_study,a.config,p_actor,p_client);
  refs:=refs||jsonb_build_array((select ref from private.study_artifacts where id=a.facts_artifact_id));
 end loop;return refs;
end$$;

ALTER FUNCTION "private"."study_report_rights"("p_study" "uuid", "p_runs" "jsonb", "p_analyses" "jsonb", "p_actor" "uuid", "p_client" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_report_rights"("p_study" "uuid", "p_runs" "jsonb", "p_analyses" "jsonb", "p_actor" "uuid", "p_client" "text") FROM PUBLIC;
