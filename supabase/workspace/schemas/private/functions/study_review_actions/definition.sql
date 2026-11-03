CREATE OR REPLACE FUNCTION "private"."study_review_actions"("p_type" "text", "p_id" "uuid", "p_actor" "uuid", "p_client" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare r private.study_report_revisions%rowtype;role text;ops jsonb:='[]'::jsonb;st jsonb;s private.study_report_shares%rowtype;e private.study_review_exports%rowtype;begin
 if p_type='share' then
  s:=private.study_review_share_check(p_id,p_actor,p_client,false);ops:='["share.read"]';
  if s.issuer_id=p_actor and private.study_client_allowed(p_client,'STUDY-WRITE-01') then
   begin perform private.study_review_authorize(s.study_id,p_actor,p_client,'manage');ops:=ops||jsonb_build_array('share.revoke');exception when raise_exception then null;end;
  end if;
  begin perform private.study_review_share_check(p_id,p_actor,p_client,true);ops:=ops||jsonb_build_array('share.view','share.download');exception when raise_exception then null;end;return ops;
 elsif p_type='study' then
  role:=private.study_review_authorize(p_id,p_actor,p_client,'read');
  if role='owner' and private.study_client_allowed(p_client,'STUDY-WRITE-01') then ops:=jsonb_build_array('member.set');end if;return ops;
 elsif p_type='export' then
  select * into e from private.study_review_exports where id=p_id;
  perform private.study_review_authorize(e.study_id,p_actor,p_client,'manage');perform private.study_review_disclosure(e.report_id);
  perform private.study_require(e.actor_id=p_actor and private.study_client_allowed(e.client_id,'STUDY-WRITE-01') and e.grant_epoch=(select grant_epoch from private.studies where id=e.study_id),'FORBIDDEN');return '["export.read"]'::jsonb;
 end if;
 perform private.study_require(p_type='reportRevision','INVALID_REQUEST');select * into r from private.study_report_revisions where id=p_id;
 role:=private.study_review_authorize(r.study_id,p_actor,p_client,'read');perform private.study_review_disclosure(r.id);
 ops:='["report.current","report.view","comment.list","review.list"]';
 if private.study_client_allowed(p_client,'STUDY-WRITE-01') then
  if role in ('owner','editor','reviewer') then ops:=ops||jsonb_build_array('comment.append');end if;
  if role='reviewer' then ops:=ops||jsonb_build_array('review.record','review.delegation.list');if p_client is null then ops:=ops||jsonb_build_array('review.delegation.issue','review.delegation.revoke');end if;end if;
  if role='owner' then
   ops:=ops||jsonb_build_array('report.finalize','share.list');st:=private.study_review_state(r.id);
   if st->>'acceptance'='current' then
    if (select export_enabled and export_profile is not null from private.study_reporting_config where singleton) and not exists(select 1 from private.study_runs where id in(select jsonb_array_elements_text(r.run_ids)::uuid) and validity<>'current') then ops:=ops||jsonb_build_array('export.request');end if;
    if exists(select 1 from private.study_review_exports where report_id=r.id and finalization_id=(st->'finalization'->>'finalizationId')::uuid and actor_id=p_actor and grant_epoch=(select grant_epoch from private.studies where id=r.study_id)) then ops:=ops||jsonb_build_array('share.create');end if;
   end if;
  end if;
 end if;return ops;
exception when raise_exception then return '[]'::jsonb;end$$;

ALTER FUNCTION "private"."study_review_actions"("p_type" "text", "p_id" "uuid", "p_actor" "uuid", "p_client" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_review_actions"("p_type" "text", "p_id" "uuid", "p_actor" "uuid", "p_client" "text") FROM PUBLIC;
