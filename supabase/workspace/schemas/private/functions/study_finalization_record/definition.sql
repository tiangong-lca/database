CREATE OR REPLACE FUNCTION "private"."study_finalization_record"("p_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
 select jsonb_build_object('studyId',study_id,'reportRevisionId',report_id,'reportContentHash',report_hash,'finalizationId',id,'actorId',actor_id,'profileId',profile_id,
 'expectedReviewStateHash',expected_review_state_hash,'acceptedReviewIds',accepted_review_ids,'finalizedAt',finalized_at) from private.study_report_finalizations where id=p_id
$$;

ALTER FUNCTION "private"."study_finalization_record"("p_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_finalization_record"("p_id" "uuid") FROM PUBLIC;
