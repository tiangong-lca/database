CREATE OR REPLACE FUNCTION "private"."study_review_share_check"("p_share" "uuid", "p_actor" "uuid", "p_client" "text", "p_bytes" boolean) RETURNS "private"."study_report_shares"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare s private.study_report_shares%rowtype;st jsonb;e private.study_review_exports%rowtype;begin
 select * into s from private.study_report_shares where id=p_share;perform private.study_require(found,'FORBIDDEN');
 perform 1 from private.studies where id=s.study_id for update;
 select * into s from private.study_report_shares where id=p_share;
 perform private.study_require(p_actor in (s.issuer_id,s.recipient_id) and private.study_client_allowed(p_client,'STUDY-READ-01'),'FORBIDDEN');
 if p_bytes then
  perform private.study_require(p_actor=s.recipient_id,'FORBIDDEN');
  perform private.study_require(s.revoked_at is null and s.expires_at>clock_timestamp(),'DISCLOSURE_DENIED');
  perform private.study_review_authorize(s.study_id,s.issuer_id,s.issuer_client_id,'manage');
  select * into e from private.study_review_exports where id=s.export_id;
  perform private.study_require(private.study_client_allowed(e.client_id,'STUDY-WRITE-01'),'DISCLOSURE_DENIED');
  perform private.study_require(s.grant_epoch=(select grant_epoch from private.studies where id=s.study_id),'DISCLOSURE_DENIED');
  perform private.study_review_disclosure(s.report_id);st:=private.study_review_state(s.report_id);
  perform private.study_require(st->>'acceptance'='current' and st->'finalization'->>'finalizationId'=s.finalization_id::text,'DISCLOSURE_DENIED');
 end if;return s;
end$$;

ALTER FUNCTION "private"."study_review_share_check"("p_share" "uuid", "p_actor" "uuid", "p_client" "text", "p_bytes" boolean) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_review_share_check"("p_share" "uuid", "p_actor" "uuid", "p_client" "text", "p_bytes" boolean) FROM PUBLIC;
