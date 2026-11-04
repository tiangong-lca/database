CREATE OR REPLACE FUNCTION "private"."study_review_state"("p_report" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare r private.study_report_revisions%rowtype;heads jsonb:='[]'::jsonb;currentids jsonb:='[]'::jsonb;accepted jsonb:='[]'::jsonb;h record;valid boolean;digest text;f private.study_report_finalizations%rowtype;begin
 select * into r from private.study_report_revisions where id=p_report;perform private.study_require(found,'FORBIDDEN');
 for h in select v.* from private.study_report_review_heads x join private.study_report_reviews v on v.id=x.review_id where x.report_id=r.id order by v.actor_id,v.review_class loop
  valid:=private.study_review_current(h.id);heads:=heads||jsonb_build_array(jsonb_build_object('review',private.study_review_record(h.id),'current',valid));
  currentids:=currentids||jsonb_build_array(h.id);
  if valid and h.decision='approve' and h.actor_id<>r.author_id then accepted:=accepted||jsonb_build_array(h.id);end if;
 end loop;
 digest:=private.study_reporting_digest('lca.study-review-state.v1',jsonb_build_object('reportRevisionId',r.id,'reportContentHash',r.content_hash,'heads',heads));
 select * into f from private.study_report_finalizations where report_id=r.id order by finalized_at desc,id desc limit 1;
 return jsonb_build_object('studyId',r.study_id,'reportRevisionId',r.id,'reportContentHash',r.content_hash,'reportRevision',r.revision,'authorId',r.author_id,
 'reviewStateHash',digest,'currentReviewIds',currentids,'acceptedReviewIds',accepted,'finalization',private.study_finalization_record(f.id),
 'acceptance',case when f.id is null then 'not_finalized' when f.profile_id='lca.study-report-unreviewed.v1' or
 (f.expected_review_state_hash=digest and jsonb_array_length(f.accepted_review_ids)>0 and f.accepted_review_ids<@accepted) then 'current' else 'invalidated' end,
 'validity',private.study_report_validity_snapshot(r.study_id,r.run_ids,(r.validity_snapshot->>'checkedAt')::timestamptz),'checkedAt',clock_timestamp());
end$$;

ALTER FUNCTION "private"."study_review_state"("p_report" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_review_state"("p_report" "uuid") FROM PUBLIC;
