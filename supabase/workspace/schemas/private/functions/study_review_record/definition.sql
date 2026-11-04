CREATE OR REPLACE FUNCTION "private"."study_review_record"("p_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
 select jsonb_build_object('studyId',study_id,'reportRevisionId',report_id,'reportContentHash',report_hash,'reviewId',id,'actorId',actor_id,'clientId',client_id,
 'reviewClass',review_class,'decision',decision,'comment',body,'predecessorReviewId',predecessor_id,'delegationId',delegation_id,
 'authorityKind',case when client_id is null then 'first_party_actor' else 'oauth_delegated_actor' end,'createdAt',created_at) from private.study_report_reviews where id=p_id
$$;

ALTER FUNCTION "private"."study_review_record"("p_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_review_record"("p_id" "uuid") FROM PUBLIC;
