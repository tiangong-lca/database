CREATE OR REPLACE FUNCTION "private"."study_method_review_actions"("p_type" "text", "p_id" "uuid", "p_actor" "uuid", "p_client" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare r private.study_report_revisions%rowtype;role text;ops jsonb:='[]'::jsonb;st jsonb;s private.study_report_shares%rowtype;begin
 if p_type='share' then
  s:=private.study_review_share_check(p_id,p_actor,p_client,false);ops:='["share.read"]';
  if s.issuer_id=p_actor and private.study_client_allowed(p_client,'STUDY-WRITE-01')
   and (select status='active' from private.studies where id=s.study_id) then
   begin perform private.study_review_authorize(s.study_id,p_actor,p_client,'manage');ops:=ops||jsonb_build_array('share.revoke');exception when raise_exception then null;end;
  end if;
  begin perform private.study_review_share_check(p_id,p_actor,p_client,true);ops:=ops||jsonb_build_array('share.view','share.download');exception when raise_exception then null;end;return ops;
 elsif p_type='export' then
  perform private.study_review_export_check(p_id,p_actor,p_client);return '["export.read","export.download"]'::jsonb;
 end if;
 perform private.study_require(p_type='reportRevision','INVALID_REQUEST');select * into r from private.study_report_revisions where id=p_id;
 role:=private.study_review_authorize(r.study_id,p_actor,p_client,'read');perform private.study_review_disclosure(r.id);
 ops:='["report.current","report.view","comment.list","review.list"]';
 if private.study_client_allowed(p_client,'STUDY-WRITE-01') then
  -- Lists retain their existing read authority on archived Studies. Only
  -- availability of new commands follows the common active-Study guard.
  if role='reviewer' then ops:=ops||jsonb_build_array('review.delegation.list');end if;
  if role='owner' then ops:=ops||jsonb_build_array('share.list');end if;
  if not (select status='active' from private.studies where id=r.study_id) then return ops;end if;
  if role in ('owner','editor','reviewer') then ops:=ops||jsonb_build_array('comment.append');end if;
  if role='reviewer' then ops:=ops||jsonb_build_array('review.record');if p_client is null then ops:=ops||jsonb_build_array('review.delegation.issue','review.delegation.revoke');end if;end if;
  if role='owner' then
   ops:=ops||jsonb_build_array('report.finalize');st:=private.study_review_state(r.id);
   if st->>'acceptance'='current' then
    if (select export_enabled and export_profile is not null from private.study_method_review_config where singleton) and not exists(select 1 from private.study_runs where id in(select jsonb_array_elements_text(r.run_ids)::uuid) and validity<>'current') then ops:=ops||jsonb_build_array('export.request');end if;
    if exists(select 1 from private.study_review_exports e where e.report_id=r.id and e.finalization_id=(st->'finalization'->>'finalizationId')::uuid and e.actor_id=p_actor
     and e.grant_epoch=(select grant_epoch from private.studies where id=r.study_id) and private.study_client_allowed(e.client_id,'STUDY-WRITE-01')) then ops:=ops||jsonb_build_array('share.create');end if;
   end if;
  end if;
 end if;return ops;
exception when raise_exception then return '[]'::jsonb;end$$;

ALTER FUNCTION "private"."study_method_review_actions"("p_type" "text", "p_id" "uuid", "p_actor" "uuid", "p_client" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_method_review_actions"("p_type" "text", "p_id" "uuid", "p_actor" "uuid", "p_client" "text") FROM PUBLIC;
