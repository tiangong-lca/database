CREATE OR REPLACE FUNCTION "private"."study_method_report_command"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '15s'
    AS $$
declare op text:=p_request->>'operation';actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');sid uuid;rid uuid;
 r private.study_report_revisions%rowtype;i private.study_report_intents%rowtype;cfg private.study_method_config%rowtype;previous private.study_command_receipts%rowtype;
 req jsonb:=(p_request-'schemaVersion'-'requestId'-'idempotencyKey')||jsonb_build_object('_verifiedClientId',client);refs jsonb;result jsonb;allowed text[];parent uuid;
begin
 perform private.study_method_envelope(p_request,true);
 perform private.study_require(op in ('report.create','report.save','report.freeze'),'CAPABILITY_UNAVAILABLE');
 perform private.study_require(private.study_client_allowed(client,'STUDY-WRITE-01'),'FORBIDDEN');
 case op
 when 'report.create' then
  allowed:=array['schemaVersion','requestId','idempotencyKey','operation','studyId','parentReportRevisionId','runIds','methodAssessmentIds','content','templateId'];sid:=(p_request->>'studyId')::uuid;
 when 'report.save','report.freeze' then
  allowed:=array['schemaVersion','requestId','idempotencyKey','operation','target']||case when op='report.save' then array['content'] else array['expectedContentHash'] end;
  perform private.study_require(private.study_keys(p_request->'target',array['type','id','expectedRevision']) and p_request->'target'->>'type'='reportRevision'
   and jsonb_typeof(p_request->'target'->'expectedRevision')='number' and (p_request->'target'->>'expectedRevision')::numeric between 1 and 9007199254740991
   and trunc((p_request->'target'->>'expectedRevision')::numeric)=(p_request->'target'->>'expectedRevision')::numeric,'INVALID_REQUEST');
  rid:=(p_request->'target'->>'id')::uuid;select study_id into sid from private.study_report_revisions where id=rid;
 else perform private.study_require(false,'CAPABILITY_UNAVAILABLE');end case;
 perform private.study_require(private.study_keys(p_request,allowed),'INVALID_REQUEST');
 perform private.study_authorize(sid,actor,client,case when op='export.request' then 'read' else 'write' end);
 -- The first lookup routes only by immutable Study ownership. A command may
 -- have waited for a producer holding the Study lock; reload and lock the
 -- mutable report before rights, replay recovery, CAS/hash checks or snapshot.
 if op<>'report.create' then
  select * into r from private.study_report_revisions where study_id=sid and id=rid for update;
  perform private.study_require(found and r.template_id='lca.study-method-report.v1','NOT_FOUND');
 end if;
 if op='report.create' then refs:=private.study_method_report_rights(sid,p_request->'runIds',p_request->'methodAssessmentIds',actor,client);
 else refs:=private.study_method_report_rights(sid,r.run_ids,r.method_assessment_ids,actor,client);end if;
 select * into previous from private.study_command_receipts where actor_id=actor and operation='method.'||op and scope=sid::text and idempotency_key=p_request->>'idempotencyKey';
 if found then
  perform private.study_require(previous.request=req,'IDEMPOTENCY_CONFLICT');
  if previous.response->'data'->>'kind'='reportMethodCommandIntent' then
   i:=private.study_method_report_intent_check((previous.response->'data'->>'intentId')::uuid);if i.response is not null then return i.response;end if;
  end if;
  if op='export.request' then perform private.study_report_export_authorize((previous.response->'data'->'value'->>'exportId')::uuid,actor,client);end if;return previous.response;
 end if;
 perform private.study_analysis_require_current(sid,jsonb_build_object('runIds',case when op='report.create' then p_request->'runIds' else r.run_ids end));
 perform private.study_require((select status='active' from private.studies where id=sid),'FROZEN_REVISION');
 select * into cfg from private.study_method_config where singleton for share;
 perform private.study_require(cfg.report_enabled,'CAPABILITY_UNAVAILABLE');
 if op in ('report.create','report.save') then
  perform private.study_require(private.study_method_report_content_valid(p_request->'content'),'INVALID_REQUEST');
  perform private.study_require(not exists(select 1 from jsonb_array_elements(p_request->'content'->'claims')c where not refs @> jsonb_build_array(c->'bundleRef')),'REFERENCE_MISMATCH');
 end if;
 if op='report.create' then
  perform private.study_require(p_request->>'templateId'='lca.study-method-report.v1','INVALID_REQUEST');parent:=(p_request->>'parentReportRevisionId')::uuid;
  if parent is not null then perform private.study_require(exists(select 1 from private.study_report_revisions where study_id=sid and id=parent and status='frozen' and template_id='lca.study-method-report.v1'),'REFERENCE_MISMATCH');end if;
  rid:=gen_random_uuid();
 else
   perform private.study_require(r.revision=(p_request->'target'->>'expectedRevision')::bigint,'REVISION_CONFLICT');
   perform private.study_require(r.status='draft','FROZEN_REVISION');
   if op='report.freeze' then perform private.study_require(r.content_hash=p_request->>'expectedContentHash','REFERENCE_MISMATCH');end if;
 end if;
 -- Bounded, actor-serialized intent retention. No placeholder public row exists.
 perform pg_advisory_xact_lock(hashtextextended('study-report-intent:'||actor::text,904));
 perform private.study_require((select count(*) from private.study_report_intents where actor_id=actor and expires_at>clock_timestamp() and response is null)<64,'CAPABILITY_UNAVAILABLE');
 insert into private.study_report_intents(study_id,actor_id,client_id,operation,request,report_id,content_artifact_id,export_id,projection_artifact_id,resources_artifact_id,bundle_artifact_id,grant_epoch,config_revision,report_snapshot,family)
 values(sid,actor,client,op,p_request,rid,case when op in ('report.create','report.save') then gen_random_uuid() end,
 case when op='export.request' then gen_random_uuid() end,case when op='export.request' then gen_random_uuid() end,
 case when op='export.request' then gen_random_uuid() end,case when op='export.request' then gen_random_uuid() end,
 (select grant_epoch from private.studies where id=sid),cfg.revision,case when op<>'report.create' then private.study_method_report_record(rid) end,'method') returning * into i;
 result:=jsonb_build_object('ok',true,'data',jsonb_build_object('kind','reportMethodCommandIntent','intentId',i.id,'expiresAt',i.expires_at,'operation',op));
 insert into private.study_command_receipts values(actor,'method.'||op,sid::text,p_request->>'idempotencyKey',req,result,clock_timestamp());return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range or check_violation or not_null_violation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');
end$$;

ALTER FUNCTION "private"."study_method_report_command"("p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_method_report_command"("p_request" "jsonb") FROM PUBLIC;
