CREATE OR REPLACE FUNCTION "private"."study_method_review_intent_check"("p_id" "uuid") RETURNS "private"."study_review_intents"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare i private.study_review_intents%rowtype;st jsonb;cfg private.study_method_review_config%rowtype;begin
 select * into i from private.study_review_intents where id=p_id;perform private.study_require(found and i.request->>'schemaVersion'='lca.study-api.v6' and exists(select 1 from private.study_report_revisions where id=i.report_id and template_id='lca.study-method-report.v1'),'CAPABILITY_UNAVAILABLE');
 perform 1 from private.studies where id=i.study_id for update;
 select * into i from private.study_review_intents where id=p_id;
 if i.share_id is not null then perform private.study_review_share_check(i.share_id,i.actor_id,i.client_id,true);
 elsif i.operation='export.download' then perform private.study_review_export_check(i.export_id,i.actor_id,i.client_id);
 else perform private.study_review_authorize(i.study_id,i.actor_id,i.client_id,case when i.operation='export.request' then 'manage' else 'read' end);perform private.study_review_disclosure(i.report_id);end if;
 if i.response is not null then return i;end if;
 select * into cfg from private.study_method_review_config where singleton for share;
 perform private.study_require(cfg.enabled and cfg.revision=i.config_revision and i.expires_at>clock_timestamp(),'CAPABILITY_UNAVAILABLE');
 perform private.study_require(i.grant_epoch=(select grant_epoch from private.studies where id=i.study_id),'FORBIDDEN');
 if i.operation='export.request' then
  st:=private.study_review_state(i.report_id);
  perform private.study_require(st->>'acceptance'='current' and st->'finalization'->>'finalizationId'=i.finalization_id::text and st->>'reviewStateHash'=i.review_state_hash,'REVISION_CONFLICT');
  perform private.study_analysis_require_current(i.study_id,jsonb_build_object('runIds',(select run_ids from private.study_report_revisions where id=i.report_id)));
  perform private.study_require((select export_enabled and export_profile is not null and revision=i.reporting_config_revision from private.study_method_review_config where singleton),'CAPABILITY_UNAVAILABLE');
 end if;return i;
end$$;

ALTER FUNCTION "private"."study_method_review_intent_check"("p_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_method_review_intent_check"("p_id" "uuid") FROM PUBLIC;
