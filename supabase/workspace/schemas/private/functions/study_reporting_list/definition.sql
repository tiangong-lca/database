CREATE OR REPLACE FUNCTION "private"."study_reporting_list"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare sid uuid:=(p_request->>'studyId')::uuid;actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');kind text:=p_request->>'kind';lim integer;
 selection jsonb;cur private.study_cursors%rowtype;after_id uuid;ids uuid[];resource_id uuid;items jsonb:='[]'::jsonb;v jsonb;nextid uuid;more boolean;epoch text;r private.study_report_revisions%rowtype;a private.study_analyses%rowtype;e private.study_report_exports%rowtype;
begin
 perform private.study_reporting_envelope(p_request,false);
 perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','studyId','kind','limit','cursor']) and kind in ('analysis','reportRevision','export')
 and jsonb_typeof(p_request->'limit')='number' and (p_request->>'limit')::numeric between 1 and 100 and (p_request->>'limit')::numeric=trunc((p_request->>'limit')::numeric),'INVALID_REQUEST');lim:=(p_request->>'limit')::integer;
 perform private.study_authorize(sid,actor,client,'read');epoch:=private.study_access_epoch(actor,sid);
 selection:=p_request-'requestId'-'cursor';
 if p_request->'cursor'<>'null'::jsonb then
  select * into cur from private.study_cursors where study_cursors.id=(p_request->>'cursor')::uuid;
  perform private.study_require(found and cur.actor_id=actor and cur.client_id is not distinct from client and cur.selection=selection and cur.access_epoch=epoch and cur.expires_at>clock_timestamp(),'INVALID_REQUEST');after_id:=cur.after_id;
 end if;
 if kind='analysis' then select array_agg(t.id order by t.id) into ids from(select study_analyses.id from private.study_analyses where study_id=sid and (after_id is null or study_analyses.id>after_id) order by study_analyses.id limit lim+1)t;
 elsif kind='reportRevision' then select array_agg(t.id order by t.id) into ids from(select study_report_revisions.id from private.study_report_revisions where study_id=sid and (after_id is null or study_report_revisions.id>after_id) order by study_report_revisions.id limit lim+1)t;
 else select array_agg(t.id order by t.id) into ids from(select study_report_exports.id from private.study_report_exports where study_id=sid and actor_id=actor and client_id is not distinct from client and grant_epoch=(select grant_epoch from private.studies where studies.id=sid) and (after_id is null or study_report_exports.id>after_id) order by study_report_exports.id limit lim+1)t;end if;
 more:=coalesce(cardinality(ids)>lim,false);
 foreach resource_id in array coalesce(ids[1:lim],'{}') loop
  if kind='analysis' then select * into a from private.study_analyses where study_analyses.id=resource_id;perform private.study_analysis_rights(sid,a.config,actor,client);v:=private.study_analysis_record(resource_id);
  elsif kind='reportRevision' then select * into r from private.study_report_revisions where study_report_revisions.id=resource_id;perform private.study_report_rights(sid,r.run_ids,r.analysis_ids,actor,client);v:=private.study_report_record(resource_id);
  else e:=private.study_report_export_authorize(resource_id,actor,client);v:=e.record;end if;
  items:=items||jsonb_build_array(jsonb_build_object('type',kind,'value',v));
 end loop;
 if more then
  insert into private.study_cursors(actor_id,client_id,selection,access_epoch,after_id) values(actor,client,selection,epoch,ids[lim]) returning study_cursors.id into nextid;
 end if;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('type','resourcePage','studyId',sid,'kind',kind,'items',items,'nextCursor',nextid));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
end$$;

ALTER FUNCTION "private"."study_reporting_list"("p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_reporting_list"("p_request" "jsonb") FROM PUBLIC;
