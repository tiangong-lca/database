CREATE OR REPLACE FUNCTION "private"."study_report_disclosure_context"("p_intent" "private"."study_report_intents") RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$select private.study_content_hash('lca.study-report-security-context.v1',jsonb_build_object(
 'intentId',p_intent.id,'actorId',p_intent.actor_id,'clientId',p_intent.client_id,'grantEpoch',p_intent.grant_epoch,'configRevision',p_intent.config_revision,
 'report',p_intent.report_snapshot,'accessEpoch',private.study_access_epoch(p_intent.actor_id,p_intent.study_id)))$$;

ALTER FUNCTION "private"."study_report_disclosure_context"("p_intent" "private"."study_report_intents") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_report_disclosure_context"("p_intent" "private"."study_report_intents") FROM PUBLIC;
