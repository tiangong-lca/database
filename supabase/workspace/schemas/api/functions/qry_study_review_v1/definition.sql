CREATE OR REPLACE FUNCTION "api"."qry_study_review_v1"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '15s'
    AS $$
declare op text:=p_request->>'operation';actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');allowed text[];rid uuid;r private.study_report_revisions%rowtype;
 s private.study_report_shares%rowtype;e private.study_review_exports%rowtype;value jsonb;ops jsonb;kind text;lim integer;afterid uuid;nextid uuid;ids uuid[];resource_id uuid;
 selection jsonb;epoch text;cur private.study_cursors%rowtype;items jsonb:='[]'::jsonb;more boolean;
begin
 perform private.study_review_envelope(p_request,false);perform private.study_require(private.study_client_allowed(client,'STUDY-READ-01'),'FORBIDDEN');
 if op='capability.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation']),'INVALID_REQUEST');
  if not(select enabled from private.study_review_config where singleton) then
   value:=jsonb_build_object('type','capabilities','contractVersion','4.0.0','runtimeEnabled',false,'operations',jsonb_build_array('capability.read'),'finalizationProfiles','[]'::jsonb,'reviewClasses','[]'::jsonb,'disclosurePolicies','[]'::jsonb);
  else
   ops:='["capability.read","resource.actions","comment.list","review.list","review.delegation.list","report.current","report.view","export.read","share.read","share.view","share.download","share.list"]';
   if private.study_client_allowed(client,'STUDY-WRITE-01') then
    ops:=ops||'["member.set","comment.append","review.record","report.finalize","export.request","share.create","share.revoke"]'::jsonb;
    if client is null then ops:=ops||'["review.delegation.issue","review.delegation.revoke"]'::jsonb;end if;
   end if;
   value:=jsonb_build_object('type','capabilities','contractVersion','4.0.0','runtimeEnabled',true,'operations',ops,
   'finalizationProfiles',jsonb_build_array('lca.study-report-unreviewed.v1','lca.study-report-internal-review.v1'),'reviewClasses',jsonb_build_array('internal'),'disclosurePolicies',jsonb_build_array('lca.study-report-summary-share.v1'));
  end if;return jsonb_build_object('ok',true,'data',value);
 end if;
 perform private.study_require((select enabled from private.study_review_config where singleton),'CAPABILITY_UNAVAILABLE');
 case op
 when 'resource.actions' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','resource']) and private.study_keys(p_request->'resource',array['type','id'])
   and p_request->'resource'->>'type' in ('study','reportRevision','share','export'),'INVALID_REQUEST');
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','actions','resource',p_request->'resource','actions',private.study_review_actions(p_request->'resource'->>'type',(p_request->'resource'->>'id')::uuid,actor,client)));
 when 'share.read','share.view','share.download' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','shareId']),'INVALID_REQUEST');
  s:=private.study_review_share_check((p_request->>'shareId')::uuid,actor,client,op<>'share.read');
  if op='share.read' then value:=jsonb_build_object('type','share','value',private.study_review_share_record(s.id));else return private.study_review_new_intent(p_request,s.report_id,s.id);end if;
  return jsonb_build_object('ok',true,'data',value);
 when 'export.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','exportId']),'INVALID_REQUEST');
  select * into e from private.study_review_exports where study_review_exports.id=(p_request->>'exportId')::uuid;
  perform private.study_review_authorize(e.study_id,actor,client,'manage');perform private.study_review_disclosure(e.report_id);
  perform private.study_require(e.actor_id=actor and private.study_client_allowed(e.client_id,'STUDY-WRITE-01') and e.grant_epoch=(select grant_epoch from private.studies where id=e.study_id),'FORBIDDEN');
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','export','value',e.record));
 when 'report.current','report.view' then allowed:=array['reportRevisionId','expectedContentHash'];
 when 'comment.list','review.list','review.delegation.list','share.list' then allowed:=array['reportRevisionId','expectedContentHash','cursor','limit'];
 else perform private.study_require(false,'CAPABILITY_UNAVAILABLE');end case;
 perform private.study_require(private.study_keys(p_request,allowed||array['schemaVersion','requestId','operation']),'INVALID_REQUEST');
 rid:=(p_request->>'reportRevisionId')::uuid;select * into r from private.study_report_revisions where study_report_revisions.id=rid;
 perform private.study_review_authorize(r.study_id,actor,client,case when op='share.list' then 'manage' when op='review.delegation.list' then 'review' else 'read' end);
 perform private.study_require(r.status='frozen' and r.content_hash=p_request->>'expectedContentHash','REFERENCE_MISMATCH');perform private.study_review_disclosure(r.id);
 if op='report.current' then return jsonb_build_object('ok',true,'data',jsonb_build_object('type','reportState','value',private.study_review_state(r.id)));end if;
 if op='report.view' then return private.study_review_new_intent(p_request,r.id);end if;
 perform private.study_require(jsonb_typeof(p_request->'limit')='number' and (p_request->>'limit')::numeric between 1 and 100 and (p_request->>'limit')::numeric=trunc((p_request->>'limit')::numeric),'INVALID_REQUEST');lim:=(p_request->>'limit')::integer;
 selection:=p_request-'requestId'-'cursor';epoch:=private.study_access_epoch(actor,r.study_id);
 if p_request->'cursor'<>'null'::jsonb then
  select * into cur from private.study_cursors where study_cursors.id=(p_request->>'cursor')::uuid;
  perform private.study_require(found and cur.actor_id=actor and cur.client_id is not distinct from client and cur.selection=selection and cur.access_epoch=epoch and cur.expires_at>clock_timestamp(),'INVALID_REQUEST');afterid:=cur.after_id;
 end if;
 kind:=case op when 'comment.list' then 'comment' when 'review.list' then 'review' when 'review.delegation.list' then 'delegation' else 'share' end;
 select array_agg(x.id order by x.id) into ids from(
  select c.id from private.study_report_comments c where kind='comment' and c.report_id=r.id and(afterid is null or c.id>afterid)
  union all select c.id from private.study_report_reviews c where kind='review' and c.report_id=r.id and(afterid is null or c.id>afterid)
  union all select c.id from private.study_review_delegations c where kind='delegation' and c.report_id=r.id and c.actor_id=actor and(afterid is null or c.id>afterid)
  union all select c.id from private.study_report_shares c where kind='share' and c.report_id=r.id and c.issuer_id=actor and(afterid is null or c.id>afterid)
  order by id limit lim+1)x;
 more:=coalesce(cardinality(ids)>lim,false);
 foreach resource_id in array coalesce(ids[1:lim],'{}') loop
  items:=items||jsonb_build_array(case kind when 'comment' then private.study_comment_record(resource_id) when 'review' then private.study_review_record(resource_id) when 'delegation' then private.study_delegation_record(resource_id) else private.study_review_share_record(resource_id) end);
 end loop;
 if more then insert into private.study_cursors(actor_id,client_id,selection,access_epoch,after_id) values(actor,client,selection,epoch,ids[lim]) returning study_cursors.id into nextid;end if;
 value:=jsonb_build_object('type','history','studyId',r.study_id,'reportRevisionId',r.id,'reportContentHash',r.content_hash,'kind',kind,'items',items,'nextCursor',nextid);
 return jsonb_build_object('ok',true,'data',value);
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');end$$;

ALTER FUNCTION "api"."qry_study_review_v1"("p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."qry_study_review_v1"("p_request" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."qry_study_review_v1"("p_request" "jsonb") TO "authenticated";
