CREATE OR REPLACE FUNCTION "api"."cmd_study_review_v1"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '15s'
    AS $_$
declare op text:=p_request->>'operation';actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');sid uuid;rid uuid;member uuid;newid uuid;head uuid;allowed text[];
 req jsonb:=(p_request-'schemaVersion'-'requestId'-'idempotencyKey')||jsonb_build_object('_verifiedClientId',client);prev private.study_command_receipts%rowtype;r private.study_report_revisions%rowtype;d private.study_review_delegations%rowtype;
 s private.study_report_shares%rowtype;e private.study_review_exports%rowtype;study private.studies%rowtype;st jsonb;result jsonb;value jsonb;ts timestamptz;
begin
 perform private.study_review_envelope(p_request,true);
 case op
 when 'member.set' then allowed:=array['target','memberId','role'];sid:=(p_request->'target'->>'id')::uuid;
 when 'review.delegation.revoke' then allowed:=array['delegationId'];select study_id,report_id into sid,rid from private.study_review_delegations where id=(p_request->>'delegationId')::uuid;
 when 'share.revoke' then allowed:=array['shareId','reason'];select study_id,report_id into sid,rid from private.study_report_shares where id=(p_request->>'shareId')::uuid;
 when 'report.finalize' then allowed:=array['target','expectedContentHash','expectedReviewStateHash','profileId','acceptedReviewIds'];rid:=(p_request->'target'->>'id')::uuid;
 when 'comment.append' then allowed:=array['reportRevisionId','expectedContentHash','text'];rid:=(p_request->>'reportRevisionId')::uuid;
 when 'review.record' then allowed:=array['reportRevisionId','expectedContentHash','reviewClass','decision','comment','predecessorReviewId','delegationId'];rid:=(p_request->>'reportRevisionId')::uuid;
 when 'review.delegation.issue' then allowed:=array['reportRevisionId','expectedContentHash','clientId','reviewClass','decision','predecessorReviewId','expiresAt'];rid:=(p_request->>'reportRevisionId')::uuid;
 when 'export.request' then allowed:=array['reportRevisionId','expectedContentHash','finalizationId','expectedReviewStateHash','rendererVersion','viewModelVersion'];rid:=(p_request->>'reportRevisionId')::uuid;
 when 'share.create' then allowed:=array['reportRevisionId','expectedContentHash','exportId','recipientId','disclosurePolicyId','expiresAt'];rid:=(p_request->>'reportRevisionId')::uuid;
 else perform private.study_require(false,'CAPABILITY_UNAVAILABLE');end case;
 perform private.study_require(private.study_keys(p_request,allowed||array['schemaVersion','requestId','idempotencyKey','operation']),'INVALID_REQUEST');
 if sid is null and rid is not null then select study_id into sid from private.study_report_revisions where id=rid;end if;
 perform private.study_review_authorize(sid,actor,client,case when op in ('member.set','report.finalize','export.request','share.create','share.revoke') then 'manage'
 when op in ('review.record','review.delegation.issue','review.delegation.revoke') then 'review' else 'comment' end);
 select * into study from private.studies where id=sid;
 -- Withdrawal and explicit revoke remain possible even when disclosure ceased.
 if rid is not null and op not in ('share.revoke','review.delegation.revoke') then
  select * into r from private.study_report_revisions where id=rid and study_id=sid;
  perform private.study_require(found and r.status='frozen' and r.content_hash=p_request->>'expectedContentHash','REFERENCE_MISMATCH');
  perform private.study_review_disclosure(r.id);
 end if;
 if op in ('review.delegation.issue','review.delegation.revoke') then perform private.study_require(client is null,'FORBIDDEN');end if;
 if op='review.delegation.revoke' then select * into d from private.study_review_delegations where id=(p_request->>'delegationId')::uuid;perform private.study_require(d.actor_id=actor,'FORBIDDEN');end if;
 if op='share.revoke' then select * into s from private.study_report_shares where id=(p_request->>'shareId')::uuid;perform private.study_require(s.issuer_id=actor,'FORBIDDEN');end if;
 select * into prev from private.study_command_receipts where actor_id=actor and operation=op and scope='v4:'||sid::text and idempotency_key=p_request->>'idempotencyKey';
 if found then
  perform private.study_require(prev.request=req,'IDEMPOTENCY_CONFLICT');
  if op='review.record' and client is not null then
   select * into d from private.study_review_delegations where id=(p_request->>'delegationId')::uuid;
   perform private.study_require(d.actor_id=actor and d.client_id=client and d.revoked_at is null and d.consumed_review_id::text=prev.response->'data'->'value'->>'reviewId','FORBIDDEN');
  end if;
  if op='export.request' and prev.response->'data'->>'kind'='studyReviewIntent' then
   declare oldintent private.study_review_intents%rowtype;begin oldintent:=private.study_review_intent_check((prev.response->'data'->>'intentId')::uuid);if oldintent.response is not null then return oldintent.response;end if;end;
  end if;return private.study_review_refresh(prev.response);
 end if;
 perform private.study_require(study.status='active','FROZEN_REVISION');
 perform 1 from private.study_review_config where singleton and enabled for share;perform private.study_require(found,'CAPABILITY_UNAVAILABLE');
 if op='member.set' then
  perform private.study_require(private.study_keys(p_request->'target',array['type','id','expectedRevision']) and p_request->'target'->>'type'='study'
   and jsonb_typeof(p_request->'target'->'expectedRevision')='number' and (p_request->'target'->>'expectedRevision')::numeric=study.revision,'REVISION_CONFLICT');
  member:=(p_request->>'memberId')::uuid;
  perform private.study_require(member<>study.owner_id,'FORBIDDEN');
  perform private.study_require(p_request->'role'='null'::jsonb or p_request->>'role' in ('editor','reviewer','viewer'),'INVALID_REQUEST');
  perform private.study_require(study.team_id is not null or p_request->'role'='null'::jsonb or p_request->>'role'='reviewer','CAPABILITY_UNAVAILABLE');
  if p_request->'role'='null'::jsonb then delete from private.study_members where study_id=sid and actor_id=member;
  else
   if study.team_id is not null then perform 1 from private.roles where user_id=member and team_id=study.team_id and role in ('owner','admin','member') for share;perform private.study_require(found,'FORBIDDEN');end if;
   insert into private.study_members values(sid,member,p_request->>'role') on conflict(study_id,actor_id) do update set role=excluded.role;end if;
  update private.studies set revision=revision+1,grant_epoch=grant_epoch+1 where id=sid returning * into study;
  value:=jsonb_build_object('type','member','studyId',sid,'studyRevision',study.revision,'memberId',member,'role',p_request->'role');
 elsif op='comment.append' then
  perform private.study_require(private.study_text(p_request->'text',4096) and p_request->>'text' !~ '[<>]','INVALID_REQUEST');
  insert into private.study_report_comments(study_id,report_id,report_hash,actor_id,client_id,body) values(sid,r.id,r.content_hash,actor,client,p_request->>'text') returning id into newid;
  value:=jsonb_build_object('type','comment','value',private.study_comment_record(newid));
 elsif op in ('review.record','review.delegation.issue') then
  perform private.study_require(p_request->>'reviewClass'='internal' and p_request->>'decision' in ('approve','reject','withdraw'),'INVALID_REQUEST');
  select review_id into head from private.study_report_review_heads where report_id=r.id and actor_id=actor and review_class='internal';
  perform private.study_require(head is not distinct from (p_request->>'predecessorReviewId')::uuid,'REVISION_CONFLICT');
  perform private.study_require(p_request->>'decision'<>'withdraw' or head is not null,'REVISION_CONFLICT');
  if op='review.delegation.issue' then
   perform private.study_require((p_request->>'clientId') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' and private.study_client_allowed(p_request->>'clientId','STUDY-WRITE-01'),'FORBIDDEN');
   ts:=(p_request->>'expiresAt')::timestamptz;perform private.study_require(ts>clock_timestamp() and ts<=clock_timestamp()+interval '15 minutes','INVALID_REQUEST');
   insert into private.study_review_delegations(study_id,report_id,report_hash,actor_id,client_id,review_class,decision,predecessor_id,expires_at)
   values(sid,r.id,r.content_hash,actor,p_request->>'clientId','internal',p_request->>'decision',head,ts) returning id into newid;
   value:=jsonb_build_object('type','delegation','value',private.study_delegation_record(newid));
  else
   perform private.study_require(private.study_text(p_request->'comment',4096) and p_request->>'comment' !~ '[<>]','INVALID_REQUEST');
   perform private.study_require(head is not null or (select count(*) from private.study_report_review_heads where report_id=r.id)<64,'CAPABILITY_UNAVAILABLE');
   if client is null then perform private.study_require(p_request->'delegationId'='null'::jsonb,'FORBIDDEN');
   else
    select * into d from private.study_review_delegations where id=(p_request->>'delegationId')::uuid for update;
    perform private.study_require(found and d.actor_id=actor and d.client_id=client and d.report_id=r.id and d.report_hash=r.content_hash and d.review_class='internal'
     and d.decision=p_request->>'decision' and d.predecessor_id is not distinct from head and d.revoked_at is null and d.consumed_review_id is null and d.expires_at>clock_timestamp(),'FORBIDDEN');
   end if;
   insert into private.study_report_reviews(study_id,report_id,report_hash,actor_id,client_id,review_class,decision,body,predecessor_id,delegation_id)
    values(sid,r.id,r.content_hash,actor,client,'internal',p_request->>'decision',p_request->>'comment',head,d.id) returning id into newid;
   insert into private.study_report_review_heads values(r.id,actor,'internal',newid) on conflict(report_id,actor_id,review_class) do update set review_id=excluded.review_id;
   if d.id is not null then update private.study_review_delegations set consumed_review_id=newid where id=d.id;end if;
   value:=jsonb_build_object('type','review','value',private.study_review_record(newid),'state',private.study_review_state(r.id));
  end if;
 elsif op='review.delegation.revoke' then
  update private.study_review_delegations set revoked_at=coalesce(revoked_at,clock_timestamp()) where id=d.id;
  value:=jsonb_build_object('type','delegation','value',private.study_delegation_record(d.id));
 elsif op='report.finalize' then
  perform private.study_require(private.study_keys(p_request->'target',array['type','id','expectedRevision']) and p_request->'target'->>'type'='reportRevision'
   and jsonb_typeof(p_request->'target'->'expectedRevision')='number' and (p_request->'target'->>'expectedRevision')::numeric=r.revision,'REVISION_CONFLICT');
  st:=private.study_review_state(r.id);perform private.study_require(st->>'reviewStateHash'=p_request->>'expectedReviewStateHash','REVISION_CONFLICT');
  perform private.study_require(p_request->>'profileId' in ('lca.study-report-unreviewed.v1','lca.study-report-internal-review.v1')
   and private.study_report_ids(p_request->'acceptedReviewIds',0,64),'INVALID_REQUEST');
  perform private.study_require(case when p_request->>'profileId'='lca.study-report-unreviewed.v1' then p_request->'acceptedReviewIds'='[]'::jsonb
   else jsonb_array_length(p_request->'acceptedReviewIds')>0 and (p_request->'acceptedReviewIds')<@(st->'acceptedReviewIds') end,'FORBIDDEN');
  insert into private.study_report_finalizations(study_id,report_id,report_hash,actor_id,profile_id,expected_review_state_hash,accepted_review_ids)
   values(sid,r.id,r.content_hash,actor,p_request->>'profileId',p_request->>'expectedReviewStateHash',p_request->'acceptedReviewIds') returning id into newid;
  value:=jsonb_build_object('type','finalization','value',private.study_finalization_record(newid),'state',private.study_review_state(r.id));
 elsif op='export.request' then
  perform private.study_require(p_request->>'rendererVersion'='1.0.0' and p_request->>'viewModelVersion'='lca.study-report-view.v1','CAPABILITY_UNAVAILABLE');
  result:=private.study_review_new_intent(p_request,r.id);value:=result->'data';
 elsif op='share.create' then
  select * into e from private.study_review_exports where id=(p_request->>'exportId')::uuid;
  st:=private.study_review_state(r.id);
  perform private.study_require(found and e.report_id=r.id and e.actor_id=actor and e.grant_epoch=study.grant_epoch and st->>'acceptance'='current'
   and st->'finalization'->>'finalizationId'=e.finalization_id::text and private.study_client_allowed(e.client_id,'STUDY-WRITE-01'),'DISCLOSURE_DENIED');
  perform private.study_require(p_request->>'disclosurePolicyId'='lca.study-report-summary-share.v1','INVALID_REQUEST');
  ts:=(p_request->>'expiresAt')::timestamptz;perform private.study_require(ts>clock_timestamp() and ts<=clock_timestamp()+interval '30 days','INVALID_REQUEST');
  insert into private.study_report_shares(study_id,report_id,report_hash,export_id,finalization_id,issuer_id,issuer_client_id,recipient_id,grant_epoch,disclosure_context_hash,expires_at)
   values(sid,r.id,r.content_hash,e.id,e.finalization_id,actor,client,(p_request->>'recipientId')::uuid,study.grant_epoch,
   private.study_reporting_digest('lca.study-summary-share.v1',jsonb_build_object('exportId',e.id,'recipientId',p_request->>'recipientId','grantEpoch',study.grant_epoch,'nonce',gen_random_uuid())),ts) returning id into newid;
  value:=jsonb_build_object('type','share','value',private.study_review_share_record(newid));
 elsif op='share.revoke' then
  perform private.study_require(private.study_text(p_request->'reason',4096) and p_request->>'reason' !~ '[<>]','INVALID_REQUEST');
  update private.study_report_shares set revoked_at=coalesce(revoked_at,clock_timestamp()),revocation_reason=coalesce(revocation_reason,p_request->>'reason') where id=s.id;
  value:=jsonb_build_object('type','share','value',private.study_review_share_record(s.id));
 end if;
 result:=jsonb_build_object('ok',true,'data',value);
 insert into private.study_command_receipts values(actor,op,'v4:'||sid::text,p_request->>'idempotencyKey',req,result,clock_timestamp());return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range or check_violation or not_null_violation or invalid_datetime_format then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');end$_$;

ALTER FUNCTION "api"."cmd_study_review_v1"("p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."cmd_study_review_v1"("p_request" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."cmd_study_review_v1"("p_request" "jsonb") TO "authenticated";
