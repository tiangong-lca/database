CREATE OR REPLACE FUNCTION "private"."study_method_review_new_intent"("p_request" "jsonb", "p_report" "uuid", "p_share" "uuid" DEFAULT NULL::"uuid", "p_export" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare r private.study_report_revisions%rowtype;e private.study_review_exports%rowtype;i private.study_review_intents%rowtype;st jsonb;cfg private.study_method_review_config%rowtype;actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');op text:=p_request->>'operation';begin
 select * into r from private.study_report_revisions where id=p_report;perform private.study_require(found and r.template_id='lca.study-method-report.v1' and p_request->>'schemaVersion'='lca.study-api.v6','REFERENCE_MISMATCH');
 if p_share is not null then perform private.study_review_share_check(p_share,actor,client,true);
 elsif op='export.download' then
  e:=private.study_review_export_check(p_export,actor,client);perform private.study_require(e.report_id=p_report,'REFERENCE_MISMATCH');
 else perform private.study_review_authorize(r.study_id,actor,client,case when op='export.request' then 'manage' else 'read' end);perform private.study_review_disclosure(r.id);end if;
 st:=private.study_review_state(r.id);
 if op='export.request' then
  perform private.study_require(st->>'acceptance'='current' and st->'finalization'->>'finalizationId'=p_request->>'finalizationId'
   and st->>'reviewStateHash'=p_request->>'expectedReviewStateHash','REVISION_CONFLICT');
  perform private.study_analysis_require_current(r.study_id,jsonb_build_object('runIds',r.run_ids));
  perform private.study_require((select export_enabled and export_profile is not null from private.study_method_review_config where singleton),'CAPABILITY_UNAVAILABLE');
 end if;
 select * into cfg from private.study_method_review_config where singleton for share;perform private.study_require(cfg.enabled,'CAPABILITY_UNAVAILABLE');
 perform pg_advisory_xact_lock(hashtextextended('study-review-intent:'||actor::text,906));
 perform private.study_require((select count(*) from private.study_review_intents where actor_id=actor and response is null and expires_at>clock_timestamp())<64,'CAPABILITY_UNAVAILABLE');
 insert into private.study_review_intents(study_id,report_id,actor_id,client_id,operation,request,share_id,finalization_id,grant_epoch,config_revision,reporting_config_revision,review_state_hash,
 export_id,projection_artifact_id,resources_artifact_id,bundle_artifact_id,disclosure_context_hash)
 values(r.study_id,r.id,actor,client,op,p_request,p_share,case when op='export.download' then e.finalization_id else (st->'finalization'->>'finalizationId')::uuid end,
 (select grant_epoch from private.studies where id=r.study_id),cfg.revision,(select revision from private.study_method_review_config where singleton),st->>'reviewStateHash',
 case when op='export.request' then gen_random_uuid() when op='export.download' then e.id end,case when op='export.request' then gen_random_uuid() end,
 case when op='export.request' then gen_random_uuid() end,case when op='export.request' then gen_random_uuid() end,
 private.study_reporting_digest('lca.study-review-disclosure.v1',jsonb_build_object('actorId',actor,'clientId',client,'reportRevisionId',r.id,'reportContentHash',r.content_hash,'reviewStateHash',st->>'reviewStateHash','shareId',p_share,'nonce',gen_random_uuid()))) returning * into i;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('kind','studyMethodReviewIntent','intentId',i.id,'operation',i.operation,'expiresAt',i.expires_at));
end$$;

ALTER FUNCTION "private"."study_method_review_new_intent"("p_request" "jsonb", "p_report" "uuid", "p_share" "uuid", "p_export" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_method_review_new_intent"("p_request" "jsonb", "p_report" "uuid", "p_share" "uuid", "p_export" "uuid") FROM PUBLIC;
