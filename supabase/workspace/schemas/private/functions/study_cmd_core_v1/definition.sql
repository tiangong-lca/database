CREATE OR REPLACE FUNCTION "private"."study_cmd_core_v1"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '15s'
    AS $_$
declare
  op text:=p_request->>'operation'; actor uuid:=auth.uid(); client text:=nullif(auth.jwt()->>'client_id','');
  sid uuid; rid uuid; pid uuid; parent uuid; result jsonb; response jsonb; previous private.study_command_receipts%rowtype;
  req jsonb:=p_request-'requestId'-'schemaVersion'-'idempotencyKey'; allowed text[]; s private.studies%rowtype;
  r private.study_revisions%rowtype; c private.study_scenarios%rowtype; prep private.study_model_preparations%rowtype;
  replay_intent private.study_validation_intents%rowtype;
  intent uuid; normalized jsonb; key text:=p_request->>'idempotencyKey'; scope_key text; member uuid; field text;
begin
  perform private.study_require(actor is not null and not coalesce(util.is_service_request(),false),'AUTH_REQUIRED');
  perform private.study_require(private.study_client_allowed(client,'STUDY-WRITE-01'),'FORBIDDEN');
  perform private.study_require(p_request->>'schemaVersion'='lca.study-api.v2' and jsonb_typeof(p_request)='object'
    and octet_length(p_request::text)<=262144 and length(key) between 1 and 128
    and private.study_text(p_request->'requestId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$')
    and private.study_text(p_request->'idempotencyKey',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');
  case op
    when 'study.create' then allowed:=array['scope','title'];
    when 'member.set' then allowed:=array['target','memberId','role'];
    when 'study.archive' then allowed:=array['target'];
    when 'study.select_revision' then allowed:=array['target','revisionId'];
    when 'revision.create' then allowed:=array['studyId','parentRevisionId','definition','modelPreparationId','modelRef'];
    when 'revision.save' then allowed:=array['target','definition','modelPreparationId','modelRef'];
    when 'revision.freeze' then allowed:=array['target','expectedContentHash'];
    when 'scenario.create' then allowed:=array['studyRevisionId','parentScenarioRevisionId','overrides'];
    when 'scenario.save' then allowed:=array['target','overrides'];
    when 'scenario.freeze' then allowed:=array['target','expectedContentHash','modelPreparationId'];
    else perform private.study_require(false,'CAPABILITY_UNAVAILABLE');
  end case;
  perform private.study_require(not exists(select 1 from jsonb_object_keys(p_request) k where k<>all(allowed||array['operation','schemaVersion','requestId','idempotencyKey'])),'INVALID_REQUEST');
  perform private.study_require(p_request ?& allowed,'INVALID_REQUEST');
  foreach field in array allowed loop
    if right(field,2)='Id' then
      perform private.study_require((left(field,6)='parent' and p_request->field='null'::jsonb)
        or private.study_text(p_request->field,128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');
    elsif right(field,4)='Hash' then
      perform private.study_require(private.study_text(p_request->field,64,'^[0-9a-f]{64}$'),'INVALID_REQUEST');
    end if;
  end loop;
  if p_request ? 'target' then
    perform private.study_require(private.study_keys(p_request->'target',array['type','id','expectedRevision'])
      and private.study_text(p_request->'target'->'id',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$')
      and jsonb_typeof(p_request->'target'->'expectedRevision')='number','INVALID_REQUEST');
    perform private.study_require((p_request->'target'->>'expectedRevision')::numeric between 1 and 9007199254740991
      and trunc((p_request->'target'->>'expectedRevision')::numeric)=(p_request->'target'->>'expectedRevision')::numeric,'INVALID_REQUEST');
  end if;
  if op='study.create' then
    perform private.study_require(p_request->'scope'->>'kind' in ('personal','team') and private.study_text(p_request->'title',512)
      and private.study_keys(p_request->'scope',case when p_request->'scope'->>'kind'='personal' then array['kind'] else array['kind','teamId'] end),'INVALID_REQUEST');
    if p_request->'scope'->>'kind'='team' then
      perform private.study_require(private.study_text(p_request->'scope'->'teamId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');
      sid:=(p_request->'scope'->>'teamId')::uuid;
      perform 1 from private.roles where user_id=actor and team_id=sid and role in ('owner','admin') for share;
      perform private.study_require(found,'FORBIDDEN');
    end if;
    scope_key:='create';
    perform pg_advisory_xact_lock(hashtextextended('study:create:'||actor::text||':'||key,894));
  else
    if p_request ? 'studyId' then sid:=(p_request->>'studyId')::uuid;
    elsif op like 'revision.%' then rid:=(p_request->'target'->>'id')::uuid; select study_id into sid from private.study_revisions where id=rid;
    elsif op='scenario.create' then rid:=(p_request->>'studyRevisionId')::uuid; select study_id into sid from private.study_revisions where id=rid;
    elsif op like 'scenario.%' then rid:=(p_request->'target'->>'id')::uuid; select study_id into sid from private.study_scenarios where id=rid;
    else sid:=(p_request->'target'->>'id')::uuid; end if;
    perform private.study_authorize(sid,actor,client,case when op in ('study.archive','member.set') then 'manage' else 'write' end);
    select * into s from private.studies where id=sid;
    scope_key:=sid::text;
  end if;
  select * into previous from private.study_command_receipts where actor_id=actor and operation=op and scope=scope_key and idempotency_key=key;
  if found then
    perform private.study_require(previous.request=req,'IDEMPOTENCY_CONFLICT');
    -- Creation replay also rechecks current access to the originally allocated Study.
    if op='study.create' then perform private.study_authorize((previous.response->'data'->'value'->>'studyId')::uuid,actor,client,'manage'); end if;
    if op='revision.freeze' and previous.response->'data'->>'kind'='revisionValidationIntent' then
      select * into replay_intent from private.study_validation_intents
        where id=(previous.response->'data'->>'intentId')::uuid and study_id=sid and actor_id=actor for update;
      perform private.study_require(found,'CAPABILITY_UNAVAILABLE');
      -- The initial receipt is an intermediate acknowledgement. A committed
      -- freeze supersedes that response for recovery, even after intent TTL.
      -- Current caller authorization above still precedes every replay.
      if replay_intent.response is not null then return replay_intent.response; end if;
      perform private.study_require(replay_intent.expires_at>clock_timestamp(),'CAPABILITY_UNAVAILABLE');
    end if;
    return previous.response;
  end if;
  if op<>'study.create' then perform private.study_require(s.status='active','FROZEN_REVISION'); end if;
  if p_request ? 'target' then
    perform private.study_require(jsonb_typeof(p_request->'target'->'expectedRevision')='number','INVALID_REQUEST');
    if op like 'revision.%' then
      perform private.study_require(p_request->'target'->>'type'='studyRevision','REFERENCE_MISMATCH');
      select * into r from private.study_revisions where id=rid for update;
      perform private.study_require(r.revision=(p_request->'target'->>'expectedRevision')::numeric::bigint,'REVISION_CONFLICT');
      perform private.study_require(r.status='draft','FROZEN_REVISION');
    elsif op like 'scenario.%' then
      perform private.study_require(p_request->'target'->>'type'='scenarioRevision','REFERENCE_MISMATCH');
      select * into c from private.study_scenarios where id=rid for update;
      perform private.study_require(c.revision=(p_request->'target'->>'expectedRevision')::numeric::bigint,'REVISION_CONFLICT');
      perform private.study_require(c.status='draft','FROZEN_REVISION');
    else
      perform private.study_require(p_request->'target'->>'type'='study','REFERENCE_MISMATCH');
      perform private.study_require(s.revision=(p_request->'target'->>'expectedRevision')::numeric::bigint,'REVISION_CONFLICT');
    end if;
  end if;
  case op
  when 'study.create' then
    insert into private.studies(owner_id,team_id,title) values(actor,sid,p_request->>'title') returning id into sid;
    insert into private.study_members values(sid,actor,'owner');
    result:=jsonb_build_object('type','study','value',private.study_record('study',sid));
  when 'member.set' then
    member:=(p_request->>'memberId')::uuid;
    perform private.study_require(s.team_id is not null and member<>s.owner_id,'FORBIDDEN');
    perform private.study_require(p_request->'role'='null'::jsonb or p_request->>'role' in ('editor','viewer'),'INVALID_REQUEST');
    if p_request->'role'='null'::jsonb then delete from private.study_members where study_id=sid and actor_id=member;
    else
      perform 1 from private.roles where user_id=member and team_id=s.team_id and role in ('owner','admin','member') for share;
      perform private.study_require(found,'FORBIDDEN');
      insert into private.study_members values(sid,member,p_request->>'role') on conflict(study_id,actor_id) do update set role=excluded.role;
    end if;
    update private.studies set revision=revision+1,grant_epoch=grant_epoch+1 where id=sid;
    result:=jsonb_build_object('type','study','value',private.study_record('study',sid));
  when 'study.archive' then
    update private.studies set revision=revision+1,status='archived' where id=sid;
    result:=jsonb_build_object('type','study','value',private.study_record('study',sid));
  when 'study.select_revision' then
    perform private.study_require(exists(select 1 from private.study_revisions where study_id=sid and id=(p_request->>'revisionId')::uuid and status='frozen'),'REFERENCE_MISMATCH');
    update private.studies set revision=revision+1,current_revision_id=(p_request->>'revisionId')::uuid where id=sid;
    result:=jsonb_build_object('type','study','value',private.study_record('study',sid));
  when 'revision.create','revision.save' then
    prep:=private.study_qualified_preparation(sid,(p_request->>'modelPreparationId')::uuid);
    perform private.study_require(prep.model_ref=p_request->'modelRef','REFERENCE_MISMATCH');
    perform private.study_require(private.study_definition_valid(p_request->'definition'),'INVALID_REQUEST');
    perform private.study_require(prep.method_refs=p_request->'definition'->'methodRefs','REFERENCE_MISMATCH');
    normalized:=jsonb_build_object('definition',p_request->'definition','modelPreparationId',prep.id,'modelRef',prep.model_ref);
    if op='revision.create' then
      parent:=nullif(p_request->>'parentRevisionId','')::uuid;
      if parent is not null then perform private.study_require(exists(select 1 from private.study_revisions where study_id=sid and id=parent and status='frozen'),'REFERENCE_MISMATCH'); end if;
      insert into private.study_revisions(study_id,parent_revision_id,content_hash,definition,preparation_id,model_ref)
        values(sid,parent,private.study_content_hash('lca.study-definition.v1',normalized),p_request->'definition',prep.id,prep.model_ref) returning id into rid;
    else
      update private.study_revisions set revision=revision+1,content_hash=private.study_content_hash('lca.study-definition.v1',normalized),definition=p_request->'definition',preparation_id=prep.id,model_ref=prep.model_ref where id=rid;
    end if;
    perform private.study_assert_provenance(sid);
    result:=jsonb_build_object('type','studyRevision','value',private.study_record('studyRevision',rid));
  when 'revision.freeze' then
    perform private.study_require(r.content_hash=p_request->>'expectedContentHash','REFERENCE_MISMATCH');
    prep:=private.study_qualified_preparation(sid,r.preparation_id);
    normalized:=jsonb_build_object('revisionId',rid,'expectedRevision',r.revision,'contentHash',r.content_hash,'modelPreparationId',r.preparation_id,'modelRef',r.model_ref,'definition',r.definition);
    insert into private.study_validation_intents(study_id,revision_id,actor_id,client_id,binding) values(sid,rid,actor,client,normalized) returning id into intent;
    result:=jsonb_build_object('kind','revisionValidationIntent','intentId',intent,'expiresAt',(select expires_at from private.study_validation_intents where id=intent),'revision',private.study_record('studyRevision',rid),'preparation',private.study_record('modelPreparation',prep.id));
  when 'scenario.create','scenario.save' then
    perform private.study_require(private.study_overrides_valid(p_request->'overrides'),'INVALID_REQUEST');
    if op='scenario.create' then
      select * into r from private.study_revisions where id=(p_request->>'studyRevisionId')::uuid;
      perform private.study_require(r.study_id=sid and r.status='frozen','REFERENCE_MISMATCH');
      parent:=nullif(p_request->>'parentScenarioRevisionId','')::uuid;
      if parent is not null then
        select * into c from private.study_scenarios where id=parent and study_id=sid and status='frozen';
        perform private.study_require(found,'REFERENCE_MISMATCH');
      end if;
      insert into private.study_scenarios(scenario_id,study_id,study_revision_id,parent_scenario_id,overrides,content_hash)
        values(case when parent is null then gen_random_uuid() else c.scenario_id end,sid,r.id,parent,p_request->'overrides',private.study_content_hash('lca.study-scenario.v1',jsonb_build_object('studyRevisionId',r.id,'overrides',p_request->'overrides'))) returning id into rid;
    else update private.study_scenarios set revision=revision+1,overrides=p_request->'overrides',content_hash=private.study_content_hash('lca.study-scenario.v1',jsonb_build_object('studyRevisionId',c.study_revision_id,'overrides',p_request->'overrides')) where id=rid; end if;
    perform private.study_assert_provenance(sid);
    result:=jsonb_build_object('type','scenarioRevision','value',private.study_record('scenarioRevision',rid));
  when 'scenario.freeze' then
    perform private.study_require(c.content_hash=p_request->>'expectedContentHash','REFERENCE_MISMATCH');
    prep:=private.study_qualified_preparation(sid,(p_request->>'modelPreparationId')::uuid);
    perform private.study_require(prep.source=jsonb_build_object('type','scenarioRevision','scenarioRevisionId',rid,'expectedRevision',c.revision,'contentHash',c.content_hash) and prep.input_hash is not null,'REFERENCE_MISMATCH');
    update private.study_scenarios set revision=revision+1,status='frozen',preparation_id=prep.id,effective_model_ref=prep.model_ref where id=rid;
    perform private.study_assert_provenance(sid);
    result:=jsonb_build_object('type','scenarioRevision','value',private.study_record('scenarioRevision',rid));
  end case;
  response:=jsonb_build_object('ok',true,'data',result);
  insert into private.study_command_receipts values(actor,op,scope_key,key,req,response,clock_timestamp());
  return response;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range or not_null_violation or check_violation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');
end $_$;

ALTER FUNCTION "private"."study_cmd_core_v1"("p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_cmd_core_v1"("p_request" "jsonb") FROM PUBLIC;
