CREATE OR REPLACE FUNCTION "private"."study_advanced_list"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare sid uuid:=(p_request->>'studyId')::uuid;actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');kind text:=p_request->>'kind';lim integer;
 selection jsonb;cur private.study_cursors%rowtype;afterid uuid;ids uuid[];resourceid uuid;items jsonb:='[]'::jsonb;v jsonb;nextid uuid;more boolean;epoch text;a private.study_advanced_analyses%rowtype;r private.study_report_revisions%rowtype;
begin
 perform private.study_advanced_envelope(p_request,false);
 perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','studyId','kind','limit','cursor']) and kind in ('analysis','reportRevision')
 and jsonb_typeof(p_request->'limit')='number' and (p_request->>'limit')::numeric between 1 and 100 and trunc((p_request->>'limit')::numeric)=(p_request->>'limit')::numeric,'INVALID_REQUEST');lim:=(p_request->>'limit')::integer;
 perform private.study_authorize(sid,actor,client,'read');epoch:=private.study_access_epoch(actor,sid);selection:=p_request-'requestId'-'cursor';
 if p_request->'cursor'<>'null'::jsonb then
  select * into cur from private.study_cursors where id=(p_request->>'cursor')::uuid;
  perform private.study_require(found and cur.actor_id=actor and cur.client_id is not distinct from client and cur.selection=selection and cur.access_epoch=epoch and cur.expires_at>clock_timestamp(),'INVALID_REQUEST');afterid:=cur.after_id;
 end if;
 if kind='analysis' then
  select array_agg(t.id order by t.id) into ids from(select id from private.study_advanced_analyses where study_id=sid and(afterid is null or id>afterid) order by id limit lim+1)t;
 else
  select array_agg(t.id order by t.id) into ids from(select id from private.study_report_revisions where study_id=sid and template_id='lca.study-report.v2' and(afterid is null or id>afterid) order by id limit lim+1)t;
 end if;more:=coalesce(cardinality(ids)>lim,false);
 foreach resourceid in array coalesce(ids[1:lim],'{}') loop
  if kind='analysis' then
   select * into a from private.study_advanced_analyses where id=resourceid;perform private.study_advanced_rights(sid,a.baseline_run_id,actor,client);v:=private.study_advanced_record(resourceid);
  else
   select * into r from private.study_report_revisions where id=resourceid;perform private.study_report_advanced_rights(sid,r.run_ids,r.analysis_ids,actor,client);v:=private.study_report_record(resourceid);
  end if;items:=items||jsonb_build_array(jsonb_build_object('type',kind,'value',v));
 end loop;
 if more then insert into private.study_cursors(actor_id,client_id,selection,access_epoch,after_id) values(actor,client,selection,epoch,ids[lim]) returning id into nextid;end if;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('type','resourcePage','studyId',sid,'kind',kind,'items',items,'nextCursor',nextid));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');end$$;

ALTER FUNCTION "private"."study_advanced_list"("p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_advanced_list"("p_request" "jsonb") FROM PUBLIC;
