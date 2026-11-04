CREATE OR REPLACE FUNCTION "private"."study_method_evidence_intent_check"("p_id" "uuid") RETURNS "private"."study_method_evidence_intents"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare i private.study_method_evidence_intents%rowtype;cfg private.study_method_config%rowtype;begin
 select * into i from private.study_method_evidence_intents where id=p_id;perform private.study_require(found,'CAPABILITY_UNAVAILABLE');
 perform private.study_authorize(i.study_id,i.actor_id,i.client_id,'write');
 select * into i from private.study_method_evidence_intents where id=p_id;
 if i.response is not null then return i;end if;
 select * into cfg from private.study_method_config where singleton for share;
 perform private.study_require(i.expires_at>clock_timestamp() and cfg.execution_enabled and cfg.revision=i.config_revision,'CAPABILITY_UNAVAILABLE');
 perform private.study_require(i.grant_epoch=(select grant_epoch from private.studies where id=i.study_id),'FORBIDDEN');
 perform private.study_require((select status='active' from private.studies where id=i.study_id),'FROZEN_REVISION');return i;
end$$;

ALTER FUNCTION "private"."study_method_evidence_intent_check"("p_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_method_evidence_intent_check"("p_id" "uuid") FROM PUBLIC;
