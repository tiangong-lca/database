CREATE OR REPLACE FUNCTION "private"."study_method_evidence_create"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '15s'
    AS $$
declare sid uuid:=(p_request->>'studyId')::uuid;actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');cfg private.study_method_config%rowtype;
 previous private.study_command_receipts%rowtype;i private.study_method_evidence_intents%rowtype;result jsonb;
 req jsonb:=(p_request-'schemaVersion'-'requestId'-'idempotencyKey')||jsonb_build_object('_verifiedClientId',client);
begin
 perform private.study_method_envelope(p_request,true);perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','idempotencyKey','operation','studyId','content'])
 and p_request->>'operation'='method.evidence.create' and private.study_method_evidence_body_valid(p_request->'content'),'INVALID_REQUEST');
 perform private.study_authorize(sid,actor,client,'write');
 select * into previous from private.study_command_receipts where actor_id=actor and operation='method.evidence.create' and scope=sid::text and idempotency_key=p_request->>'idempotencyKey';
 if found then
  perform private.study_require(previous.request=req,'IDEMPOTENCY_CONFLICT');
  if previous.response->'data'->>'kind'='methodEvidenceCommandIntent' then
   i:=private.study_method_evidence_intent_check((previous.response->'data'->>'intentId')::uuid);if i.response is not null then return i.response;end if;
  end if;return previous.response;
 end if;
 perform private.study_require((select status='active' from private.studies where id=sid),'FROZEN_REVISION');
 select * into cfg from private.study_method_config where singleton for share;perform private.study_require(cfg.execution_enabled,'CAPABILITY_UNAVAILABLE');
 perform pg_advisory_xact_lock(hashtextextended('study-method-evidence-intent:'||actor::text,912));
 with expired as(select id from private.study_method_evidence_intents where actor_id=actor and response is null and expires_at<=clock_timestamp() order by expires_at,id limit 256 for update skip locked)
 delete from private.study_method_evidence_intents target using expired e where target.id=e.id;
 perform private.study_require((select count(*) from private.study_method_evidence_intents where actor_id=actor and response is null and expires_at>clock_timestamp())<64,'CAPABILITY_UNAVAILABLE');
 insert into private.study_method_evidence_intents(study_id,actor_id,client_id,request,evidence_id,artifact_id,grant_epoch,config_revision)
 values(sid,actor,client,p_request,gen_random_uuid(),gen_random_uuid(),(select grant_epoch from private.studies where id=sid),cfg.revision) returning * into i;
 result:=jsonb_build_object('ok',true,'data',jsonb_build_object('kind','methodEvidenceCommandIntent','intentId',i.id,'expiresAt',i.expires_at,'operation','method.evidence.create'));
 insert into private.study_command_receipts values(actor,'method.evidence.create',sid::text,p_request->>'idempotencyKey',req,result,clock_timestamp());return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or numeric_value_out_of_range or not_null_violation or check_violation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');end$$;

ALTER FUNCTION "private"."study_method_evidence_create"("p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_method_evidence_create"("p_request" "jsonb") FROM PUBLIC;
