CREATE OR REPLACE FUNCTION "private"."study_advanced_rights"("p_study" "uuid", "p_run" "uuid", "p_actor" "uuid", "p_client" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare snapshot uuid;begin
 perform private.study_analysis_rights(p_study,jsonb_build_object('runIds',jsonb_build_array(p_run)),p_actor,p_client);
 select private.study_preparation_snapshot(p_study,preparation_id) into snapshot from private.study_runs where study_id=p_study and id=p_run;
 perform private.study_require(snapshot is not null,'REFERENCE_MISMATCH');return snapshot;
end$$;

ALTER FUNCTION "private"."study_advanced_rights"("p_study" "uuid", "p_run" "uuid", "p_actor" "uuid", "p_client" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_advanced_rights"("p_study" "uuid", "p_run" "uuid", "p_actor" "uuid", "p_client" "text") FROM PUBLIC;
