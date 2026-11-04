CREATE OR REPLACE FUNCTION "private"."study_comment_record"("p_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
 select jsonb_build_object('studyId',study_id,'reportRevisionId',report_id,'reportContentHash',report_hash,'commentId',id,'actorId',actor_id,'clientId',client_id,'text',body,'createdAt',created_at)
 from private.study_report_comments where id=p_id
$$;

ALTER FUNCTION "private"."study_comment_record"("p_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_comment_record"("p_id" "uuid") FROM PUBLIC;
