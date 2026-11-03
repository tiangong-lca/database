CREATE OR REPLACE FUNCTION "private"."study_report_intent_check"("p_id" "uuid") RETURNS "private"."study_report_intents"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare i private.study_report_intents%rowtype;r private.study_report_revisions%rowtype;cfg private.study_reporting_config%rowtype;refs jsonb;begin
 select * into i from private.study_report_intents where id=p_id;
 perform private.study_require(found,'CAPABILITY_UNAVAILABLE');
 perform private.study_authorize(i.study_id,i.actor_id,i.client_id,case when i.operation='export.request' then 'read' else 'write' end);
 select * into i from private.study_report_intents where id=p_id;
 perform private.study_require((select grant_epoch from private.studies where id=i.study_id)=i.grant_epoch,'FORBIDDEN');
 if i.operation='report.create' then
  refs:=private.study_report_rights(i.study_id,i.request->'runIds',i.request->'analysisIds',i.actor_id,i.client_id);
 else
  select * into r from private.study_report_revisions where study_id=i.study_id and id=i.report_id;
  perform private.study_require(found,'REFERENCE_MISMATCH');
  refs:=private.study_report_rights(i.study_id,r.run_ids,r.analysis_ids,i.actor_id,i.client_id);
  perform private.study_require(refs=r.facts_refs,'REFERENCE_MISMATCH');
 end if;
 if i.response is not null then return i;end if;
 perform private.study_analysis_require_current(i.study_id,jsonb_build_object('runIds',case when i.operation='report.create' then i.request->'runIds' else r.run_ids end));
 perform private.study_require(i.expires_at>clock_timestamp(),'CAPABILITY_UNAVAILABLE');
 select * into cfg from private.study_reporting_config where singleton for share;
 perform private.study_require(cfg.revision=i.config_revision and case when i.operation='export.request' then cfg.export_enabled else cfg.report_enabled end,'CAPABILITY_UNAVAILABLE');
 perform private.study_require((select status='active' from private.studies where id=i.study_id),'FROZEN_REVISION');
 if i.operation<>'report.create' then
  perform private.study_require(private.study_report_record(r.id)=i.report_snapshot,'REVISION_CONFLICT');
 end if;return i;
end$$;

ALTER FUNCTION "private"."study_report_intent_check"("p_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_report_intent_check"("p_id" "uuid") FROM PUBLIC;
