CREATE OR REPLACE FUNCTION "private"."study_delegation_record"("p_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
 select jsonb_build_object('studyId',study_id,'reportRevisionId',report_id,'reportContentHash',report_hash,'delegationId',id,'actorId',actor_id,'clientId',client_id,
 'reviewClass',review_class,'decision',decision,'predecessorReviewId',predecessor_id,'issuedAt',issued_at,'expiresAt',expires_at,'revokedAt',revoked_at,'consumedReviewId',consumed_review_id)
 from private.study_review_delegations where id=p_id
$$;

ALTER FUNCTION "private"."study_delegation_record"("p_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_delegation_record"("p_id" "uuid") FROM PUBLIC;
