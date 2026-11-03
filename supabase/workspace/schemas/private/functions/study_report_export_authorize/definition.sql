CREATE OR REPLACE FUNCTION "private"."study_report_export_authorize"("p_id" "uuid", "p_actor" "uuid", "p_client" "text") RETURNS "private"."study_report_exports"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare e private.study_report_exports%rowtype;r private.study_report_revisions%rowtype;begin
 select * into e from private.study_report_exports where id=p_id;
 perform private.study_require(found,'FORBIDDEN');perform private.study_authorize(e.study_id,p_actor,p_client,'read');
 perform private.study_require(e.actor_id=p_actor and e.client_id is not distinct from p_client
 and e.grant_epoch=(select grant_epoch from private.studies where id=e.study_id),'FORBIDDEN');
 select * into r from private.study_report_revisions where id=e.report_id;
 perform private.study_require(private.study_report_rights(e.study_id,r.run_ids,r.analysis_ids,p_actor,p_client)=r.facts_refs,'REFERENCE_MISMATCH');return e;
end$$;

ALTER FUNCTION "private"."study_report_export_authorize"("p_id" "uuid", "p_actor" "uuid", "p_client" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_report_export_authorize"("p_id" "uuid", "p_actor" "uuid", "p_client" "text") FROM PUBLIC;
