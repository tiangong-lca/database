CREATE OR REPLACE FUNCTION "private"."study_review_export_check"("p_export" "uuid", "p_actor" "uuid", "p_client" "text") RETURNS "private"."study_review_exports"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare e private.study_review_exports%rowtype;begin
 select * into e from private.study_review_exports where id=p_export;perform private.study_require(found,'FORBIDDEN');
 perform private.study_review_authorize(e.study_id,p_actor,p_client,'manage');
 select * into e from private.study_review_exports where id=p_export;
 perform private.study_require(e.actor_id=p_actor and private.study_client_allowed(e.client_id,'STUDY-WRITE-01')
  and e.grant_epoch=(select grant_epoch from private.studies where id=e.study_id),'FORBIDDEN');
 perform private.study_review_disclosure(e.report_id);return e;
end$$;

ALTER FUNCTION "private"."study_review_export_check"("p_export" "uuid", "p_actor" "uuid", "p_client" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_review_export_check"("p_export" "uuid", "p_actor" "uuid", "p_client" "text") FROM PUBLIC;
