CREATE OR REPLACE FUNCTION "private"."study_review_share_record"("p_share" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare s private.study_report_shares%rowtype;e private.study_review_exports%rowtype;status text:='active';begin
 select * into s from private.study_report_shares where id=p_share;if not found then return null;end if;select * into e from private.study_review_exports where id=s.export_id;
 if s.revoked_at is not null then status:='revoked';elsif s.expires_at<=clock_timestamp() then status:='expired';else
  begin perform private.study_review_share_check(s.id,s.recipient_id,null,true);exception when raise_exception then status:='invalidated';end;
 end if;
 return jsonb_build_object('studyId',s.study_id,'reportRevisionId',s.report_id,'reportContentHash',s.report_hash,'shareId',s.id,'exportId',s.export_id,
 'finalizationId',s.finalization_id,'issuerId',s.issuer_id,'recipientId',s.recipient_id,'disclosurePolicyId','lca.study-report-summary-share.v1',
 'disclosureContextHash',s.disclosure_context_hash,'grantEpoch',s.grant_epoch,'projectionRef',e.record->'projectionRef','bundleRef',e.record->'bundleRef',
 'createdAt',s.created_at,'expiresAt',s.expires_at,'revokedAt',s.revoked_at,'status',status);
end$$;

ALTER FUNCTION "private"."study_review_share_record"("p_share" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_review_share_record"("p_share" "uuid") FROM PUBLIC;
