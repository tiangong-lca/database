CREATE OR REPLACE FUNCTION "private"."study_task_command"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '15s'
    AS $_$
declare op text:=p_request->>'operation'; actor uuid:=auth.uid(); client text:=nullif(auth.jwt()->>'client_id',''); req jsonb:=p_request-'requestId'-'schemaVersion'-'idempotencyKey';
  sid uuid; id uuid:=gen_random_uuid(); job uuid; snapshot uuid; p private.study_model_preparations%rowtype; base private.study_model_preparations%rowtype;
  r private.study_revisions%rowtype; c private.study_scenarios%rowtype; run private.study_runs%rowtype; s private.studies%rowtype; cfg private.study_runtime_config%rowtype;
  previous private.study_command_receipts%rowtype; methods jsonb; cuts jsonb; document jsonb; source_ref jsonb:=p_request->'source'; result jsonb; response jsonb; allowed text[]; key text:=p_request->>'idempotencyKey'; old_role text; old_context text;
begin
  perform private.study_require(actor is not null and not coalesce(util.is_service_request(),false),'AUTH_REQUIRED');
  perform private.study_require(private.study_client_allowed(client,'STUDY-WRITE-01'),'FORBIDDEN');
  perform private.study_require(p_request->>'schemaVersion'='lca.study-api.v2' and octet_length(p_request::text)<=262144
    and private.study_text(p_request->'requestId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$')
    and private.study_text(p_request->'idempotencyKey',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');
  case op
    when 'model.source.resolve' then allowed:=array['studyId','originRef']; sid:=(p_request->>'studyId')::uuid;
    when 'model.prepare' then
      allowed:=array['studyId','source','profileId','calculationContractRef']; sid:=(p_request->>'studyId')::uuid;
      if p_request->'source'->>'type'='modelSourceSnapshot' then
        allowed:=allowed||array['methodRefs','cutoffs']; cuts:=coalesce(p_request->'cutoffs','[]'::jsonb); req:=jsonb_set(req,'{cutoffs}',cuts);
        perform private.study_require(p_request ? 'methodRefs' and private.study_method_refs_valid(p_request->'methodRefs') and private.study_cutoffs_valid(cuts),'INVALID_REQUEST');
      else perform private.study_require(not(p_request ? 'methodRefs') and not(p_request ? 'cutoffs'),'INVALID_REQUEST'); end if;
    when 'run.submit' then
      allowed:=array['studyRevisionId','scenarioRevisionId','expectedInputHash','calculationContractRef','profileId'];
      select * into r from private.study_revisions where study_revisions.id=(p_request->>'studyRevisionId')::uuid; sid:=r.study_id;
    when 'run.cancel' then
      allowed:=array['runId','reason']; select * into run from private.study_runs where study_runs.id=(p_request->>'runId')::uuid; sid:=run.study_id;
    else perform private.study_require(false,'CAPABILITY_UNAVAILABLE');
  end case;
  perform private.study_require(not exists(select 1 from jsonb_object_keys(p_request)k where k<>all(allowed||array['schemaVersion','requestId','idempotencyKey','operation'])),'INVALID_REQUEST');
  perform private.study_authorize(sid,actor,client,'write'); select * into s from private.studies where studies.id=sid;
  select * into previous from private.study_command_receipts where actor_id=actor and operation=op and scope=sid::text and idempotency_key=key;
  if found then perform private.study_require(previous.request=req,'IDEMPOTENCY_CONFLICT'); return previous.response; end if;
  if op<>'run.cancel' then perform private.study_require(s.status='active','FROZEN_REVISION'); end if;
  select * into cfg from private.study_runtime_config where singleton;
  case op
  when 'model.source.resolve' then
    perform private.study_require(cfg.source_enabled,'CAPABILITY_UNAVAILABLE');
    perform private.study_require(jsonb_typeof(p_request->'originRef'->'id')='string'
      and jsonb_typeof(p_request->'originRef'->'version')='string','INVALID_REQUEST');
    perform private.study_require(private.study_keys(p_request->'originRef',array['type','datasetType','id','version'])
      and p_request->'originRef'->>'type'='datasetRevision' and p_request->'originRef'->>'datasetType'='lifecyclemodel','REFERENCE_MISMATCH');
    perform private.study_source_document('lifecyclemodel',p_request->'originRef'->>'id',p_request->'originRef'->>'version',actor,client);
    job:=private.study_enqueue('study.source_acquire',sid,id,actor,s.team_id,key,req);
    insert into private.study_source_acquisitions(id,study_id,origin_ref,requested_by,job_id,requested_client_id) values(id,sid,p_request->'originRef',actor,job,client);
    result:=jsonb_build_object('type','modelSourceAcquisition','value',private.study_record('modelSourceAcquisition',id));
  when 'model.prepare' then
    perform private.study_require(cfg.compute_enabled,'CAPABILITY_UNAVAILABLE');
    if p_request->'source'->>'type'='modelSourceSnapshot' then
      perform private.study_require(private.study_keys(p_request->'source',array['type','snapshotId','contentHash','digestScope']),'INVALID_REQUEST');
      snapshot:=(p_request->'source'->>'snapshotId')::uuid;
      perform private.study_require(exists(select 1 from private.study_source_snapshots ss join private.study_artifacts a on a.id=ss.artifact_id
        where ss.id=snapshot and ss.study_id=sid and a.ref->>'contentHash'=p_request->'source'->>'contentHash' and p_request->'source'->>'digestScope'='artifact_bytes_sha256'),'REFERENCE_MISMATCH');
      methods:=p_request->'methodRefs';
      document:=jsonb_build_object('schemaVersion','lca.study-preparation-input.v1','sourceSnapshot',private.study_record('modelSourceSnapshot',snapshot),
        'sourceArtifact',private.study_private_artifact(sid,(select artifact_id from private.study_source_snapshots where study_source_snapshots.id=snapshot)),
        'basePreparedArtifact',null,'basePreparedPreparationId',null,'studyBinding',null,'overrides','[]'::jsonb,'cutoffs',cuts);
    elsif p_request->'source'->>'type'='scenarioRevision' then
      perform private.study_require(private.study_keys(p_request->'source',array['type','scenarioRevisionId','expectedRevision','contentHash'])
        and jsonb_typeof(p_request->'source'->'expectedRevision')='number','INVALID_REQUEST');
      perform private.study_require((p_request->'source'->>'expectedRevision')::numeric between 1 and 9007199254740991
        and trunc((p_request->'source'->>'expectedRevision')::numeric)=(p_request->'source'->>'expectedRevision')::numeric,'INVALID_REQUEST');
      select * into c from private.study_scenarios where study_scenarios.id=(p_request->'source'->>'scenarioRevisionId')::uuid and study_id=sid for update;
      perform private.study_require(found and c.status='draft','REFERENCE_MISMATCH');
      perform private.study_require(c.revision=(p_request->'source'->>'expectedRevision')::numeric,'REVISION_CONFLICT');
      -- Persist the same integer spelling consumed by typed Worker/API clients.
      source_ref:=jsonb_set(source_ref,'{expectedRevision}',to_jsonb(c.revision));
      perform private.study_require(c.content_hash=p_request->'source'->>'contentHash','REFERENCE_MISMATCH');
      select * into r from private.study_revisions where study_revisions.id=c.study_revision_id and status='frozen';
      base:=private.study_qualified_preparation(sid,r.preparation_id); snapshot:=private.study_preparation_snapshot(sid,base.id);
      methods:=r.definition->'methodRefs'; cuts:=coalesce(base.source_document->'cutoffs','[]'::jsonb);
      document:=jsonb_build_object('schemaVersion','lca.study-preparation-input.v1','sourceSnapshot',private.study_record('modelSourceSnapshot',snapshot),
        'sourceArtifact',private.study_private_artifact(sid,(select artifact_id from private.study_source_snapshots where study_source_snapshots.id=snapshot)),
        'basePreparedArtifact',private.study_private_artifact(sid,base.input_artifact_id),'basePreparedPreparationId',base.id,
        'studyBinding',jsonb_build_object('studyRevisionId',r.id,'studyRevisionContentHash',r.content_hash,'definition',r.definition),'overrides',c.overrides,'cutoffs',cuts);
    else perform private.study_require(false,'INVALID_REQUEST'); end if;
    perform private.study_snapshot_rights(snapshot,actor,client);
    perform private.study_require(private.study_method_refs_valid(methods) and jsonb_array_length(methods)<=25,'CAPABILITY_UNAVAILABLE');
    perform private.study_require(not exists(select 1 from jsonb_array_elements(methods)m where not cfg.method_refs @> jsonb_build_array(m)),'CAPABILITY_UNAVAILABLE');
    perform private.study_require(exists(select 1 from private.study_profiles where enabled and profile_id=p_request->>'profileId'
      and calculation_fingerprint=p_request->'calculationContractRef'->>'sha256') and private.study_keys(p_request->'calculationContractRef',array['kind','schema','sha256'])
      and p_request->'calculationContractRef'->>'kind'='calculation_contract' and p_request->'calculationContractRef'->>'schema'='lca.calculation-contract.v1','REFERENCE_MISMATCH');
    job:=private.study_enqueue('study.model_prepare',sid,id,actor,s.team_id,key,req);
    insert into private.study_model_preparations(id,study_id,source,source_document,source_snapshot_id,source_scenario_id,source_study_revision_id,source_parent_scenario_id,method_refs,profile_id,calculation_contract_ref,job_id,requested_client_id)
      values(id,sid,source_ref,document,case when c.id is null then snapshot else null end,c.id,c.study_revision_id,c.parent_scenario_id,methods,p_request->>'profileId',p_request->'calculationContractRef',job,client);
    perform private.study_assert_provenance(sid);
    result:=jsonb_build_object('type','modelPreparation','value',private.study_record('modelPreparation',id));
  when 'run.submit' then
    perform private.study_require(cfg.compute_enabled,'CAPABILITY_UNAVAILABLE');
    select * into c from private.study_scenarios where study_scenarios.id=(p_request->>'scenarioRevisionId')::uuid and study_id=sid;
    perform private.study_require(r.status='frozen' and c.status='frozen' and c.study_revision_id=r.id,'REFERENCE_MISMATCH');
    p:=private.study_qualified_preparation(sid,c.preparation_id); snapshot:=private.study_preparation_snapshot(sid,p.id);
    perform private.study_snapshot_rights(snapshot,actor,client);
    perform private.study_require(p.input_hash=p_request->>'expectedInputHash' and p.model_ref=c.effective_model_ref
      and p.profile_id=p_request->>'profileId' and p.calculation_contract_ref=p_request->'calculationContractRef','REFERENCE_MISMATCH');
    job:=private.study_enqueue('study.run',sid,id,actor,s.team_id,key,req);
    insert into private.study_runs(id,study_id,study_revision_id,scenario_id,preparation_id,input_hash,model_ref,profile_id,calculation_contract_ref,job_id,requested_client_id)
      values(id,sid,r.id,c.id,p.id,p.input_hash,p.model_ref,p.profile_id,p.calculation_contract_ref,job,client);
    result:=jsonb_build_object('type','run','value',private.study_record('run',id));
  when 'run.cancel' then
    perform private.study_require(private.study_text(p_request->'reason',512),'INVALID_REQUEST');
    old_role:=current_setting('request.jwt.claim.role',true); old_context:=current_setting('app.study.task_context',true);
    perform set_config('request.jwt.claim.role','service_role',true); perform set_config('app.study.task_context','cancel',true);
    response:=private.worker_cancel_job(run.job_id,actor,'Study task cancelled');
    perform set_config('request.jwt.claim.role',coalesce(old_role,''),true); perform set_config('app.study.task_context',coalesce(old_context,''),true);
    perform private.study_require((response->>'ok')::boolean,'REVISION_CONFLICT');
    result:=jsonb_build_object('type','run','value',private.study_record('run',run.id));
  end case;
  response:=jsonb_build_object('ok',true,'data',result);
  insert into private.study_command_receipts values(actor,op,sid::text,key,req,response,clock_timestamp()); return response;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range or not_null_violation or check_violation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');
end $_$;

ALTER FUNCTION "private"."study_task_command"("p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_task_command"("p_request" "jsonb") FROM PUBLIC;
