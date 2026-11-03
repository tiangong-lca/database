-- Database #895, stacked on #894. Source/task rollout remains disabled until
-- an explicit service qualification activation; no client grants are installed.
begin;
create temp table study895_owner_authority on commit drop as select
  (select to_jsonb(m) from pg_auth_members m where m.roleid='api_internal_executor'::regrole and m.member='postgres'::regrole and m.grantor=current_user::regrole) own_grant,
  (select coalesce(jsonb_agg(to_jsonb(m) order by m.grantor,m.oid),'[]'::jsonb) from pg_auth_members m where m.roleid='api_internal_executor'::regrole and m.member='postgres'::regrole) memberships,
  has_schema_privilege('api_internal_executor','private','CREATE') had_create;
grant api_internal_executor to postgres with inherit false,set true;
grant create on schema private to api_internal_executor;
create table private.study_runtime_config (
  singleton boolean primary key default true check(singleton), revision bigint not null default 1 check(revision>0),
  source_enabled boolean not null default false, compute_enabled boolean not null default false,
  disclosure_enabled boolean not null default false, qualification_evidence_ref text,
  method_refs jsonb not null default '[]'::jsonb check(jsonb_typeof(method_refs)='array'),
  compiler_version text not null default 'study.compiler.v1' check(compiler_version='study.compiler.v1')
);
insert into private.study_runtime_config(singleton) values(true);
alter table private.study_runtime_config enable row level security;
alter table private.study_runtime_config force row level security;
revoke all on private.study_runtime_config from public,anon,authenticated,service_role;
alter table private.study_source_acquisitions add column requested_client_id text, add column source_packet jsonb;
alter table private.study_model_preparations add column requested_client_id text;
alter table private.study_runs add column requested_client_id text;
create table private.study_artifact_read_intents (
  id uuid primary key default gen_random_uuid(), study_id uuid not null references private.studies(id),
  artifact_id uuid not null, artifact_ref jsonb not null, actor_id uuid not null references auth.users(id), client_id text,
  expires_at timestamptz not null default clock_timestamp()+interval '2 minutes',
  foreign key(study_id,artifact_id) references private.study_artifacts(study_id,id)
);
create index study_artifact_intent_actor_idx on private.study_artifact_read_intents(actor_id);
create index study_artifact_intent_artifact_idx on private.study_artifact_read_intents(study_id,artifact_id);
create index study_artifact_intent_expiry_idx on private.study_artifact_read_intents(expires_at,id);
alter table private.study_artifact_read_intents enable row level security;
alter table private.study_artifact_read_intents force row level security;
revoke all on private.study_artifact_read_intents from public,anon,authenticated,service_role;

insert into private.worker_job_kinds(job_kind,worker_runtime,worker_queue,default_visibility,payload_schema_version,result_schema_version,user_visible,description)
values
 ('study.source_acquire','calculator','solver','user','study.source_acquire.request.v1','lca.study-job-receipt.v1',false,'Qualified Study JSON snapshot export; admission is rollout gated'),
 ('study.model_prepare','calculator','solver','user','study.model_prepare.request.v1','lca.study-job-receipt.v1',false,'Study exact-source model preparation'),
 ('study.run','calculator','solver','user','study.run.request.v1','lca.study-job-receipt.v1',false,'Study immutable frozen input execution')
on conflict(job_kind) do update set payload_schema_version=excluded.payload_schema_version,result_schema_version=excluded.result_schema_version,user_visible=false;

-- All raw source facts originate in the actual caller-visible row. The kernel
-- runs under the existing NOBYPASSRLS executor, never the service/definer role.
create function private.study_source_visible_row(p_kind text,p_id uuid,p_version text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare t text; v jsonb;
begin
  t:=case p_kind when 'lifecyclemodel' then 'lifecyclemodels' when 'process' then 'processes'
    when 'flow' then 'flows' when 'flowproperty' then 'flowproperties' when 'unitgroup' then 'unitgroups' end;
  if t is null then return null; end if;
  execute format('select jsonb_build_object(''text'',json_ordered::text,''stateCode'',state_code,''ownerActorId'',user_id) from public.%I where id=$1 and version=$2',t)
    into v using p_id,p_version;
  return v;
end $$;

create function private.study_artifact_authorize(p_study uuid,p_ref jsonb,p_actor uuid,p_client text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a private.study_artifacts%rowtype; snapshot uuid; p uuid;
begin
  perform private.study_authorize(p_study,p_actor,p_client,'read');
  perform private.study_require((select disclosure_enabled from private.study_runtime_config where singleton),'CAPABILITY_UNAVAILABLE');
  perform private.study_require(p_ref->>'type' in ('modelInput','runResult'),'DISCLOSURE_DENIED');
  select * into a from private.study_artifacts where study_id=p_study and id=(p_ref->>'id')::uuid;
  perform private.study_require(found and a.ref=p_ref,'REFERENCE_MISMATCH');
  if a.ref->>'type'='modelInput' then select id into p from private.study_model_preparations where study_id=p_study and input_artifact_id=a.id;
  else select preparation_id into p from private.study_runs where study_id=p_study and result_artifact_id=a.id; end if;
  perform private.study_require(p is not null,'DISCLOSURE_DENIED'); snapshot:=private.study_preparation_snapshot(p_study,p);
  perform private.study_snapshot_rights(snapshot,p_actor,p_client);
  return jsonb_build_object('kind','artifactCapability','studyId',p_study,'artifactRef',a.ref,'storageBucket',a.bucket,'storageObjectPath',a.object_path);
end $$;
create function private.study_artifact_capability(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); client text:=nullif(auth.jwt()->>'client_id',''); sid uuid:=(p_request->>'studyId')::uuid; capability jsonb; intent uuid; expiry timestamptz;
begin
  perform private.study_require(actor is not null and not coalesce(util.is_service_request(),false),'AUTH_REQUIRED');
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','studyId','artifactRef'])
    and p_request->>'schemaVersion'='lca.study-api.v2' and p_request->>'operation'='artifact.read','INVALID_REQUEST');
  capability:=private.study_artifact_authorize(sid,p_request->'artifactRef',actor,client);
  perform pg_advisory_xact_lock(hashtextextended('study-artifact-intent:'||actor::text,895));
  with expired as (select id from private.study_artifact_read_intents where expires_at<=clock_timestamp()
    order by expires_at,id limit 256 for update skip locked)
    delete from private.study_artifact_read_intents i using expired e where i.id=e.id;
  perform private.study_require((select count(*) from private.study_artifact_read_intents where actor_id=actor and expires_at>clock_timestamp())<64,'CAPABILITY_UNAVAILABLE');
  insert into private.study_artifact_read_intents(study_id,artifact_id,artifact_ref,actor_id,client_id)
    values(sid,(p_request->'artifactRef'->>'id')::uuid,p_request->'artifactRef',actor,client) returning id,expires_at into intent,expiry;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('kind','artifactReadIntent','intentId',intent,'expiresAt',expiry,'studyId',sid,'artifactRef',p_request->'artifactRef'));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
end $$;
create function api.svc_study_artifact_read_resolve_v1(p_intent_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$ declare i private.study_artifact_read_intents%rowtype; capability jsonb; begin
  perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
  select * into i from private.study_artifact_read_intents where id=p_intent_id;
  perform private.study_require(found and i.expires_at>clock_timestamp(),'CAPABILITY_UNAVAILABLE');
  capability:=private.study_artifact_authorize(i.study_id,i.artifact_ref,i.actor_id,i.client_id);
  return jsonb_build_object('ok',true,'data',capability);
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end $$;

create function private.study_resource_job(p_study uuid,p_type text,p_id uuid) returns uuid
language plpgsql stable security definer set search_path='' as $$ declare job uuid; begin
  case p_type
    when 'modelSourceAcquisition' then select job_id into job from private.study_source_acquisitions where study_id=p_study and id=p_id;
    when 'modelPreparation' then select job_id into job from private.study_model_preparations where study_id=p_study and id=p_id;
    when 'run' then select job_id into job from private.study_runs where study_id=p_study and id=p_id;
    else perform private.study_require(false,'INVALID_REQUEST');
  end case;
  perform private.study_require(job is not null,'FORBIDDEN'); return job;
end $$;
create function private.study_task_control(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); client text:=nullif(auth.jwt()->>'client_id',''); sid uuid:=(p_request->>'studyId')::uuid;
  op text:=p_request->>'operation'; rid uuid:=(p_request->'resource'->>'id')::uuid; typ text:=p_request->'resource'->>'type'; job uuid;
  j private.worker_jobs%rowtype; old_role text; old_context text; result jsonb; previous private.study_command_receipts%rowtype;
  request jsonb:=p_request-'schemaVersion'-'requestId'-'idempotencyKey'; key text:=p_request->>'idempotencyKey';
begin
  perform private.study_require(actor is not null and not coalesce(util.is_service_request(),false),'AUTH_REQUIRED');
  perform private.study_require(p_request->>'schemaVersion'='lca.study-api.v2' and private.study_keys(p_request->'resource',array['type','id'])
    and op in ('task.read','task.cancel'),'INVALID_REQUEST');
  perform private.study_authorize(sid,actor,client,case op when 'task.read' then 'read' else 'write' end);
  job:=private.study_resource_job(sid,typ,rid);
  if op='task.cancel' then
    perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','idempotencyKey','studyId','resource','reason'])
      and private.study_text(p_request->'reason',512) and private.study_text(p_request->'idempotencyKey',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');
    select * into previous from private.study_command_receipts where actor_id=actor and operation=op and scope=sid::text and idempotency_key=key;
    if found then perform private.study_require(previous.request=request,'IDEMPOTENCY_CONFLICT'); return previous.response; end if;
    old_role:=current_setting('request.jwt.claim.role',true); old_context:=current_setting('app.study.task_context',true);
    perform set_config('request.jwt.claim.role','service_role',true); perform set_config('app.study.task_context','cancel',true);
    result:=private.worker_cancel_job(job,actor,'Study task cancelled');
    perform set_config('request.jwt.claim.role',coalesce(old_role,''),true); perform set_config('app.study.task_context',coalesce(old_context,''),true);
    perform private.study_require((result->>'ok')::boolean,'REVISION_CONFLICT');
  else
    perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','studyId','resource']),'INVALID_REQUEST');
  end if;
  select * into j from private.worker_jobs where id=job;
  result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','task','value',jsonb_build_object('studyId',sid,'resource',p_request->'resource',
    'execution',jsonb_build_object('jobId',job,'status',j.status,'phase',case when j.phase in ('queued','source_capture','model_prepare','solve','complete','cancelled','study_start','study_native','study_artifact','study_publish') then j.phase else null end,'progress',j.progress),
    'errorCode',case when j.error_code=any(array['source_invalid','boundary_undeclared','normalization_underflow','normalization_overflow','numeric_invalid','resource_limit','model_not_solvable','native_execution_failed','job_timeout','job_lease_lost','runtime_unavailable','runtime_failed']) then j.error_code else null end)));
  if op='task.cancel' then insert into private.study_command_receipts values(actor,op,sid::text,key,request,result,clock_timestamp()); end if;
  return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
end $$;

alter function api.qry_study_v1(jsonb) rename to study_qry_core_v1;
alter function api.study_qry_core_v1(jsonb) set schema private;
revoke all on function private.study_qry_core_v1(jsonb) from public,anon,authenticated,service_role;
create function api.qry_study_v1(p_request jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; ops jsonb; profiles jsonb:='[]'; cfg private.study_runtime_config%rowtype; client text:=nullif(auth.jwt()->>'client_id','');
begin
  if p_request->>'operation'='task.read' then return private.study_task_control(p_request); end if;
  if p_request->>'operation'='artifact.read' then return private.study_artifact_capability(p_request); end if;
  result:=private.study_qry_core_v1(p_request);
  if p_request->>'operation'='capability.read' and result->>'ok'='true' then
    select * into cfg from private.study_runtime_config where singleton;
    ops:=result->'data'->'operations'||jsonb_build_array('task.read');
    if private.study_client_allowed(client,'STUDY-WRITE-01') then
      ops:=ops||jsonb_build_array('run.cancel','task.cancel');
      if private.study_client_allowed(client,'DB-CORE-READ-01') then
        if cfg.source_enabled then ops:=ops||jsonb_build_array('model.source.resolve'); end if;
        if cfg.compute_enabled then ops:=ops||jsonb_build_array('model.prepare','run.submit'); end if;
      end if;
    end if;
    if cfg.disclosure_enabled and private.study_client_allowed(client,'DB-CORE-READ-01') then ops:=ops||jsonb_build_array('artifact.read'); end if;
    if cfg.compute_enabled then
      select coalesce(jsonb_agg(jsonb_build_object('profileId',profile_id,'calculationContractRef',jsonb_build_object('kind','calculation_contract','schema','lca.calculation-contract.v1','sha256',calculation_fingerprint))),'[]') into profiles from private.study_profiles where enabled;
    end if;
    result:=jsonb_set(jsonb_set(result,'{data,operations}',ops),'{data,profiles}',profiles);
  end if;
  return result;
end $$;

create function private.study_cutoffs_valid(p_value jsonb) returns boolean
language plpgsql immutable set search_path='' as $$ declare x jsonb; seen text[]:='{}'; k text; begin
  if jsonb_typeof(p_value) is distinct from 'array' or jsonb_array_length(p_value)>256 then return false; end if;
  for x in select * from jsonb_array_elements(p_value) loop
    if not private.study_keys(x,array['port','reason']) or not private.study_keys(x->'port',array['instanceId','exchangeId'])
      or not private.study_text(x->'port'->'instanceId',128,'^[A-Za-z0-9_-]+$')
      or not private.study_text(x->'port'->'exchangeId',128,'^[A-Za-z0-9_-]+$') or not private.study_text(x->'reason',1024) then return false; end if;
    k:=x->'port'->>'instanceId'||':'||(x->'port'->>'exchangeId');
    if k=any(seen) then return false; end if; seen:=seen||k;
  end loop; return true;
end $$;
create function private.study_private_artifact(p_study uuid,p_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$ declare v jsonb; begin
  select jsonb_build_object('studyId',study_id,'artifactRef',ref,'storageBucket',bucket,'storageObjectPath',object_path)
    into v from private.study_artifacts where study_id=p_study and id=p_id;
  perform private.study_require(v is not null,'REFERENCE_MISMATCH'); return v;
end $$;
create function private.study_preparation_snapshot(p_study uuid,p_preparation uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare p private.study_model_preparations%rowtype; v_id uuid:=p_preparation; seen uuid[]:='{}'; result uuid;
begin
  loop
    perform private.study_require(v_id is not null and not v_id=any(seen) and cardinality(seen)<512,'REFERENCE_MISMATCH'); seen:=seen||v_id;
    select * into p from private.study_model_preparations where study_id=p_study and study_model_preparations.id=v_id;
    perform private.study_require(found,'REFERENCE_MISMATCH');
    if p.source_snapshot_id is not null then return p.source_snapshot_id; end if;
    select preparation_id into v_id from private.study_revisions where study_id=p_study and study_revisions.id=p.source_study_revision_id and status='frozen';
  end loop;
end $$;
create function private.study_snapshot_rights(p_snapshot uuid,p_actor uuid,p_client text) returns void
language plpgsql security definer set search_path='' as $$ declare s private.study_source_snapshots%rowtype; begin
  select * into s from private.study_source_snapshots where id=p_snapshot;
  perform private.study_require(found,'REFERENCE_MISMATCH');
  perform private.study_source_rights(s.source_authorization->'sourceScope',p_actor,p_client);
end $$;

create function private.study_enqueue(p_kind text,p_study uuid,p_resource uuid,p_actor uuid,p_team uuid,p_key text,p_request jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare old_role text:=current_setting('request.jwt.claim.role',true); old_context text:=current_setting('app.study.task_context',true); result jsonb; subject text;
begin
  subject:=case p_kind when 'study.source_acquire' then 'acquisitionId' when 'study.model_prepare' then 'preparationId' when 'study.run' then 'runId' end;
  perform private.study_require(subject is not null,'INVALID_REQUEST');
  -- This closed postgres-only helper is reached only after actor admission.
  -- Reuse the canonical enqueuer under scoped service context, restoring it
  -- before returning; public requests cannot select either context setting.
  perform set_config('request.jwt.claim.role','service_role',true); perform set_config('app.study.task_context','enqueue',true);
  result:=private.worker_enqueue_job(p_kind,jsonb_build_object('schemaVersion',p_kind||'.request.v1','studyId',p_study,subject,p_resource),
    p_kind||'.request.v1','study',p_resource,null,p_actor,'user',p_team,p_actor::text||':'||p_study::text||':'||p_kind||':'||p_key,
    private.study_content_hash('lca.study-job-request.v1',p_request),null,0,null,null,'user');
  perform set_config('request.jwt.claim.role',coalesce(old_role,''),true); perform set_config('app.study.task_context',coalesce(old_context,''),true);
  perform private.study_require((result->>'ok')::boolean,'CAPABILITY_UNAVAILABLE');
  return (result->'data'->>'id')::uuid;
exception when others then
  perform set_config('request.jwt.claim.role',coalesce(old_role,''),true); perform set_config('app.study.task_context',coalesce(old_context,''),true); raise;
end $$;

create function private.study_task_command(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' set statement_timeout='15s' as $$
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
end $$;

-- Preserve the reviewed core unchanged behind private delegation, with a closed
-- new façade rather than copying its frozen CAS/validation-intent implementation.
alter function api.cmd_study_v1(jsonb) rename to study_cmd_core_v1;
alter function api.study_cmd_core_v1(jsonb) set schema private;
revoke all on function private.study_cmd_core_v1(jsonb) from public,anon,authenticated,service_role;
create function api.cmd_study_v1(p_request jsonb) returns jsonb language plpgsql security definer set search_path='' as $$ begin
  if p_request->>'operation'='task.cancel' then return private.study_task_control(p_request); end if;
  if p_request->>'operation' in ('model.source.resolve','model.prepare','run.submit','run.cancel') then return private.study_task_command(p_request); end if;
  return private.study_cmd_core_v1(p_request);
end $$;

create function api.svc_study_runtime_configure_v1(p_expected_revision bigint,p_configuration jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$ declare cfg private.study_runtime_config%rowtype; enabled boolean; v_fingerprint text; begin
  perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
  perform private.study_require(private.study_keys(p_configuration,array['schemaVersion','sourceEnabled','computeEnabled','disclosureEnabled','profileId','calculationContractRef','compilerVersion','qualificationEvidenceRef','methodRefs'])
    and p_configuration->>'schemaVersion'='lca.study-runtime-qualification.v1' and p_configuration->>'compilerVersion'='study.compiler.v1'
    and p_configuration->>'profileId'='lca.study-explicit-v1' and private.study_text(p_configuration->'qualificationEvidenceRef',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$')
    and jsonb_typeof(p_configuration->'sourceEnabled')='boolean' and jsonb_typeof(p_configuration->'computeEnabled')='boolean'
    and jsonb_typeof(p_configuration->'disclosureEnabled')='boolean','INVALID_REQUEST');
  v_fingerprint:=p_configuration->'calculationContractRef'->>'sha256'; enabled:=(p_configuration->>'computeEnabled')::boolean;
  perform private.study_require(private.study_keys(p_configuration->'calculationContractRef',array['kind','schema','sha256'])
    and p_configuration->'calculationContractRef'->>'kind'='calculation_contract' and p_configuration->'calculationContractRef'->>'schema'='lca.calculation-contract.v1'
    and exists(select 1 from private.lca_calculation_contracts where lca_calculation_contracts.fingerprint=v_fingerprint),'REFERENCE_MISMATCH');
  if enabled then perform private.study_require(private.study_method_refs_valid(p_configuration->'methodRefs') and jsonb_array_length(p_configuration->'methodRefs')<=25,'INVALID_REQUEST');
  else perform private.study_require(jsonb_typeof(p_configuration->'methodRefs')='array','INVALID_REQUEST'); end if;
  select * into cfg from private.study_runtime_config where singleton for update;
  perform private.study_require(cfg.revision=p_expected_revision,'REVISION_CONFLICT');
  insert into private.study_profiles(profile_id,calculation_fingerprint,enabled) values('lca.study-explicit-v1',v_fingerprint,enabled)
    on conflict(profile_id) do update set calculation_fingerprint=excluded.calculation_fingerprint,enabled=excluded.enabled;
  update private.study_runtime_config set revision=revision+1,source_enabled=(p_configuration->>'sourceEnabled')::boolean,
    compute_enabled=enabled,disclosure_enabled=(p_configuration->>'disclosureEnabled')::boolean,
    qualification_evidence_ref=p_configuration->>'qualificationEvidenceRef',method_refs=p_configuration->'methodRefs' where singleton;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('revision',cfg.revision+1));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end $$;

create or replace function private.study_read_worker_input(p_kind text,p_id uuid,p_job uuid,p_token uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p private.study_model_preparations%rowtype; r private.study_runs%rowtype; sid uuid; actor uuid; client text; snapshot uuid; result jsonb;
begin
  perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
  if p_kind='modelPreparation' then
    select * into p from private.study_model_preparations where id=p_id; sid:=p.study_id; client:=p.requested_client_id;
    perform private.study_require(p.job_id=p_job,'REFERENCE_MISMATCH');
  else
    select * into r from private.study_runs where id=p_id; sid:=r.study_id; client:=r.requested_client_id;
    perform private.study_require(r.job_id=p_job,'REFERENCE_MISMATCH');
  end if;
  select requested_by into actor from private.worker_jobs where id=p_job;
  perform private.study_authorize(sid,actor,client,'write');
  perform private.study_lock_job(sid,p_job,p_token,case p_kind when 'modelPreparation' then 'study.model_prepare' else 'study.run' end,
    case p_kind when 'modelPreparation' then 'preparationId' else 'runId' end,p_id);
  if p_kind='modelPreparation' then
    snapshot:=case when p.source_snapshot_id is not null then p.source_snapshot_id else private.study_preparation_snapshot(sid,(select preparation_id from private.study_revisions where id=p.source_study_revision_id)) end;
    perform private.study_snapshot_rights(snapshot,actor,client);
    result:=jsonb_build_object('preparation',private.study_record('modelPreparation',p.id),'sourceDocument',p.source_document,'methodRefs',p.method_refs);
  else
    snapshot:=private.study_preparation_snapshot(sid,r.preparation_id); perform private.study_snapshot_rights(snapshot,actor,client);
    result:=jsonb_build_object('run',private.study_record('run',r.id),'preparation',private.study_record('modelPreparation',r.preparation_id),
      'revision',private.study_record('studyRevision',r.study_revision_id),'scenario',private.study_record('scenarioRevision',r.scenario_id),
      'preparedArtifact',private.study_private_artifact(sid,(select input_artifact_id from private.study_model_preparations where id=r.preparation_id)));
  end if;
  return jsonb_build_object('ok',true,'data',result);
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end $$;

create function private.study_validate_task_completion(p_kind text,p_id uuid,p_completion jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare sid uuid; actor uuid; client text; snapshot uuid; a private.study_source_acquisitions%rowtype; p private.study_model_preparations%rowtype; r private.study_runs%rowtype;
begin
  if p_kind='modelSourceAcquisition' then
    select * into a from private.study_source_acquisitions where id=p_id; sid:=a.study_id; actor:=a.requested_by; client:=a.requested_client_id;
    perform private.study_authorize(sid,actor,client,'write');
    perform private.study_require(a.source_packet is not null and p_completion->'sourceAuthorization'=a.source_packet->'sourceAuthorization'
      and p_completion->'originRef'=a.source_packet->'originRef' and p_completion->>'licenseRef'=a.source_packet->>'licenseRef'
      and p_completion->>'issuerId'=a.source_packet->>'issuerId' and p_completion->>'observedAt'=a.source_packet->>'observedAt'
      and p_completion->'sourceArtifactRef'->>'schemaVersion'='lca.study-source-snapshot.v1'
      and p_completion->'sourceArtifactRef'->>'mediaType'='application/json','REFERENCE_MISMATCH');
    perform private.study_source_rights(a.source_packet->'sourceAuthorization'->'sourceScope',actor,client);
  elsif p_kind='modelPreparation' then
    select * into p from private.study_model_preparations where id=p_id; sid:=p.study_id; client:=p.requested_client_id;
    select requested_by into actor from private.worker_jobs where id=p.job_id;
    perform private.study_authorize(sid,actor,client,'write');
    snapshot:=case when p.source_snapshot_id is not null then p.source_snapshot_id else private.study_preparation_snapshot(sid,(select preparation_id from private.study_revisions where id=p.source_study_revision_id)) end;
    perform private.study_snapshot_rights(snapshot,actor,client);
  elsif p_kind='run' then
    select * into r from private.study_runs where id=p_id; sid:=r.study_id; client:=r.requested_client_id;
    select requested_by into actor from private.worker_jobs where id=r.job_id;
    perform private.study_authorize(sid,actor,client,'write'); snapshot:=private.study_preparation_snapshot(sid,r.preparation_id);
    perform private.study_snapshot_rights(snapshot,actor,client);
  else perform private.study_require(false,'INVALID_REQUEST'); end if;
end $$;

create function api.svc_study_task_reconcile_v1(p_resource_type text,p_resource_id uuid,p_job_id uuid,p_lease_token uuid,p_idempotency_key text,p_artifact_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare sid uuid; bound_job uuid; j private.worker_jobs%rowtype; receipt private.study_service_receipts%rowtype; state text; resource jsonb;
begin
  perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
  case p_resource_type
    when 'modelSourceAcquisition' then select study_id,job_id into sid,bound_job from private.study_source_acquisitions where id=p_resource_id;
    when 'modelPreparation' then select study_id,job_id into sid,bound_job from private.study_model_preparations where id=p_resource_id;
    when 'run' then select study_id,job_id into sid,bound_job from private.study_runs where id=p_resource_id;
    else perform private.study_require(false,'INVALID_REQUEST');
  end case;
  perform private.study_require(sid is not null and bound_job=p_job_id,'REFERENCE_MISMATCH');
  perform 1 from private.studies where id=sid for update;
  select * into j from private.worker_jobs where id=p_job_id for update;
  perform private.study_require(p_lease_token is not null and (j.lease_token=p_lease_token or exists(
    select 1 from private.worker_job_events where job_id=p_job_id and lease_token=p_lease_token)),'FORBIDDEN');
  select * into receipt from private.study_service_receipts where operation=p_resource_type and study_id=sid and idempotency_key=p_idempotency_key;
  if found then
    perform private.study_require(receipt.job_id=p_job_id and receipt.lease_token=p_lease_token and receipt.request->>'id'=p_resource_id::text,'IDEMPOTENCY_CONFLICT');
    state:='committed'; resource:=receipt.response->'data';
  elsif p_artifact_id is not null and exists(select 1 from private.study_artifacts where id=p_artifact_id) then state:='referenced';
  elsif j.status in ('completed','failed','cancelled','blocked') and j.lease_token is null then state:='unreferenced';
  else state:='pending'; end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('state',state,'resource',resource,'jobStatus',j.status));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end $$;
create function api.svc_study_task_fail_v1(p_resource_type text,p_resource_id uuid,p_job_id uuid,p_lease_token uuid,p_error_code text,p_idempotency_key text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare sid uuid; job uuid; kind text; subject text; result jsonb; old_context text; receipt private.study_service_receipts%rowtype; request jsonb;
begin
  perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
  perform private.study_require(p_error_code=any(array['source_invalid','boundary_undeclared','normalization_underflow','normalization_overflow','numeric_invalid','resource_limit','model_not_solvable','native_execution_failed','job_timeout','job_lease_lost','runtime_unavailable','runtime_failed']) and length(p_idempotency_key) between 1 and 128,'INVALID_REQUEST');
  case p_resource_type
    when 'modelSourceAcquisition' then select study_id,job_id into sid,job from private.study_source_acquisitions where id=p_resource_id; kind:='study.source_acquire'; subject:='acquisitionId';
    when 'modelPreparation' then select study_id,job_id into sid,job from private.study_model_preparations where id=p_resource_id; kind:='study.model_prepare'; subject:='preparationId';
    when 'run' then select study_id,job_id into sid,job from private.study_runs where id=p_resource_id; kind:='study.run'; subject:='runId';
    else perform private.study_require(false,'INVALID_REQUEST');
  end case;
  perform private.study_require(sid is not null and job=p_job_id,'REFERENCE_MISMATCH'); perform 1 from private.studies where id=sid for update;
  request:=jsonb_build_object('id',p_resource_id,'jobId',p_job_id,'leaseToken',p_lease_token,'errorCode',p_error_code);
  select * into receipt from private.study_service_receipts where operation=p_resource_type and study_id=sid and idempotency_key=p_idempotency_key;
  if found then perform private.study_require(receipt.request=request,'IDEMPOTENCY_CONFLICT'); return receipt.response; end if;
  perform private.study_lock_job(sid,p_job_id,p_lease_token,kind,subject,p_resource_id);
  old_context:=current_setting('app.study.task_context',true); perform set_config('app.study.task_context','complete',true);
  result:=private.worker_record_job_result(p_job_id,p_lease_token,'failed',jsonb_build_object('schemaVersion','lca.study-job-receipt.v1','studyId',sid,'resourceType',p_resource_type,'resourceId',p_resource_id),
    'lca.study-job-receipt.v1',null,null,p_error_code,'Study task failed',null,null,null,false);
  perform set_config('app.study.task_context',coalesce(old_context,''),true); perform private.study_require((result->>'ok')::boolean,'FORBIDDEN');
  result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type',p_resource_type,'value',private.study_record(p_resource_type,p_resource_id)));
  insert into private.study_service_receipts values(p_resource_type,sid,p_idempotency_key,p_job_id,p_lease_token,request,result); return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end $$;
alter function private.study_source_visible_row(text,uuid,text) owner to api_internal_executor;
set local role api_internal_executor;
revoke all on function private.study_source_visible_row(text,uuid,text) from public,anon,authenticated,service_role;
grant execute on function private.study_source_visible_row(text,uuid,text) to postgres;
reset role;

create function private.study_source_document(p_kind text,p_id text,p_version text,p_actor uuid,p_client text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare t text; raw text; state integer; owner_id uuid; visible jsonb; claims text; sub text; role_claim text; root_key text; body jsonb;
begin
  perform private.study_require(private.study_client_allowed(p_client,'DB-CORE-READ-01'),'FORBIDDEN');
  perform private.study_require(p_version ~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$','REFERENCE_MISMATCH');
  t:=case p_kind when 'lifecyclemodel' then 'lifecyclemodels' when 'process' then 'processes'
    when 'flow' then 'flows' when 'flowproperty' then 'flowproperties' when 'unitgroup' then 'unitgroups' end;
  perform private.study_require(t is not null,'REFERENCE_MISMATCH');
  execute format('select json_ordered::text,state_code,user_id from public.%I where id=$1 and version=$2 for share',t)
    into raw,state,owner_id using p_id::uuid,p_version;
  perform private.study_require(found and raw is not null and(state=100 or(state=0 and owner_id=p_actor)),'DISCLOSURE_DENIED');
  -- Bound a single stored row before JSONB projection, parsing or hashing.
  perform private.study_require(octet_length(raw)<=4194304,'CAPABILITY_UNAVAILABLE');
  claims:=current_setting('request.jwt.claims',true); sub:=current_setting('request.jwt.claim.sub',true); role_claim:=current_setting('request.jwt.claim.role',true);
  perform set_config('request.jwt.claims',jsonb_strip_nulls(jsonb_build_object('sub',p_actor,'role','authenticated','client_id',p_client))::text,true);
  perform set_config('request.jwt.claim.sub',p_actor::text,true); perform set_config('request.jwt.claim.role','authenticated',true);
  visible:=private.study_source_visible_row(p_kind,p_id::uuid,p_version);
  perform set_config('request.jwt.claims',coalesce(claims,''),true); perform set_config('request.jwt.claim.sub',coalesce(sub,''),true); perform set_config('request.jwt.claim.role',coalesce(role_claim,''),true);
  perform private.study_require(visible is not null and visible->>'text'=raw and (visible->>'stateCode')::integer=state
    and nullif(visible->>'ownerActorId','')::uuid is not distinct from owner_id,'DISCLOSURE_DENIED');
  body:=raw::jsonb; perform private.study_require(jsonb_typeof(body)='object','INVALID_REQUEST');
  root_key:=case p_kind when 'lifecyclemodel' then 'lifeCycleModelDataSet' when 'process' then 'processDataSet'
    when 'flow' then 'flowDataSet' when 'flowproperty' then 'flowPropertyDataSet' when 'unitgroup' then 'unitGroupDataSet' end;
  perform private.study_require(jsonb_typeof(body->root_key)='object','REFERENCE_MISMATCH');
  return jsonb_build_object('kind',p_kind,'identity',jsonb_build_object('id',p_id,'version',p_version),'stateCode',state,
    'ownerActorId',owner_id,'sha256',encode(extensions.digest(convert_to(raw,'UTF8'),'sha256'),'hex'),'json',raw);
exception when others then
  if claims is not null then perform set_config('request.jwt.claims',claims,true); end if;
  if sub is not null then perform set_config('request.jwt.claim.sub',sub,true); end if;
  if role_claim is not null then perform set_config('request.jwt.claim.role',role_claim,true); end if;
  raise;
end $$;
create function private.study_source_items(p_value jsonb) returns setof jsonb
language plpgsql immutable set search_path='' as $$ begin
  if p_value is null or p_value='null'::jsonb then return; end if;
  if jsonb_typeof(p_value)='array' then return query select * from jsonb_array_elements(p_value);
  elsif jsonb_typeof(p_value)='object' then return next p_value;
  else raise exception 'INVALID_REQUEST'; end if;
end $$;
create function private.study_source_ref(p_kind text,p_ref jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$ begin
  perform private.study_require(jsonb_typeof(p_ref)='object' and private.study_text(p_ref->'@refObjectId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$')
    and private.study_text(p_ref->'@version',9,'^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$'),'REFERENCE_MISMATCH');
  return jsonb_build_object('kind',p_kind,'id',p_ref->>'@refObjectId','version',p_ref->>'@version');
end $$;
create function private.study_capture_source(p_origin jsonb,p_actor uuid,p_client text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare queue jsonb:=jsonb_build_array(jsonb_build_object('kind','lifecyclemodel','id',p_origin->>'id','version',p_origin->>'version'));
  seen text[]:='{}'; item jsonb; doc jsonb; data jsonb; x jsonb; selected jsonb; docs jsonb:='[]'; scope jsonb; key text; pivot text; count_items integer; root_key text; size_bytes bigint:=0;
begin
  perform private.study_require(private.study_keys(p_origin,array['type','datasetType','id','version']) and p_origin->>'type'='datasetRevision'
    and p_origin->>'datasetType'='lifecyclemodel','REFERENCE_MISMATCH');
  while jsonb_array_length(queue)>0 loop
    item:=queue->0; queue:=queue-0; key:=(item->>'kind')||':'||(item->>'id')||':'||(item->>'version');
    if key=any(seen) then continue; end if;
    perform private.study_require(cardinality(seen)<512,'CAPABILITY_UNAVAILABLE'); seen:=seen||key;
    doc:=private.study_source_document(item->>'kind',item->>'id',item->>'version',p_actor,p_client);
    size_bytes:=size_bytes+octet_length(doc->>'json'); perform private.study_require(size_bytes<=4194304,'CAPABILITY_UNAVAILABLE');
    docs:=docs||jsonb_build_array(doc); data:=(doc->>'json')::jsonb;
    case item->>'kind'
    when 'lifecyclemodel' then
      select count(*) into count_items from private.study_source_items(data#>'{lifeCycleModelDataSet,lifeCycleModelInformation,technology,processes,processInstance}');
      perform private.study_require(count_items between 1 and 64,'CAPABILITY_UNAVAILABLE');
      for x in select * from private.study_source_items(data#>'{lifeCycleModelDataSet,lifeCycleModelInformation,technology,processes,processInstance}') loop
        queue:=queue||jsonb_build_array(private.study_source_ref('process',x->'referenceToProcess'));
      end loop;
    when 'process' then
      for x in select * from private.study_source_items(data#>'{processDataSet,exchanges,exchange}') loop
        queue:=queue||jsonb_build_array(private.study_source_ref('flow',x->'referenceToFlowDataSet'));
      end loop;
    when 'flow' then
      pivot:=data#>>'{flowDataSet,flowInformation,quantitativeReference,referenceToReferenceFlowProperty}';
      select count(*),jsonb_agg(v) into count_items,selected from private.study_source_items(data#>'{flowDataSet,flowProperties,flowProperty}')v where v->>'@dataSetInternalID'=pivot;
      perform private.study_require(count_items=1,'REFERENCE_MISMATCH');
      queue:=queue||jsonb_build_array(private.study_source_ref('flowproperty',selected->0->'referenceToFlowPropertyDataSet'));
    when 'flowproperty' then
      queue:=queue||jsonb_build_array(private.study_source_ref('unitgroup',data#>'{flowPropertyDataSet,flowPropertiesInformation,quantitativeReference,referenceToReferenceUnitGroup}'));
    when 'unitgroup' then null;
    end case;
    perform private.study_require(jsonb_array_length(queue)<=8192,'CAPABILITY_UNAVAILABLE');
  end loop;
  select jsonb_agg(v order by v->>'kind',v->'identity'->>'id',v->'identity'->>'version') into docs from jsonb_array_elements(docs)v;
  select jsonb_agg((v-'json')||jsonb_build_object('id',v->'identity'->>'id','version',v->'identity'->>'version',
    'sourceEncoding','postgresql.json-text.utf8.v1','licenseEvidence',coalesce((v->>'json')::jsonb#>array[case v->>'kind' when 'lifecyclemodel' then 'lifeCycleModelDataSet' when 'process' then 'processDataSet' when 'flow' then 'flowDataSet' when 'flowproperty' then 'flowPropertyDataSet' when 'unitgroup' then 'unitGroupDataSet' end,'administrativeInformation','publicationAndOwnership'],'{}'::jsonb)))
    into scope from jsonb_array_elements(docs)v;
  return jsonb_build_object('schemaVersion','lca.study-source-snapshot.v1','originRef',p_origin,'licenseRef','study-source-access.actor-data-rights.v1',
    'issuerId','database.study-source.v1','observedAt',clock_timestamp(),'sourceAuthorization',jsonb_build_object('schemaVersion','lca.study-source-authorization.v1',
      'requestedBy',p_actor,'originRef',p_origin,'sourceEncoding','postgresql.json-text.utf8.v1','sourceScope',scope),
    'source',jsonb_build_object('schemaVersion','lca.study-source.v1','origin',jsonb_build_object('id',p_origin->>'id','version',p_origin->>'version'),
      'actorId',p_actor,'documents',docs,'methodRefs','[]'::jsonb,'cutoffs','[]'::jsonb,'overrides','[]'::jsonb,'studyBinding',null,'qualityFindings','[]'::jsonb));
end $$;
create function private.study_source_rights(p_scope jsonb,p_actor uuid,p_client text) returns void
language plpgsql security definer set search_path='' as $$ declare d jsonb; actual jsonb; captured_owner uuid; begin
  perform private.study_require(jsonb_typeof(p_scope)='array' and jsonb_array_length(p_scope) between 1 and 512,'DISCLOSURE_DENIED');
  for d in select * from jsonb_array_elements(p_scope) loop
    actual:=private.study_source_document(d->>'kind',coalesce(d->>'id',d->'identity'->>'id'),coalesce(d->>'version',d->'identity'->>'version'),p_actor,p_client);
    captured_owner:=nullif(d->>'ownerActorId','')::uuid;
    -- Current visibility does not retroactively publish historical draft bytes.
    -- Captured private data remains owner-bound. A nonowner may read captured
    -- public bytes only while the exact captured bytes are still public now.
    perform private.study_require(
      ((d->>'stateCode')::integer=0 and captured_owner=p_actor and nullif(actual->>'ownerActorId','')::uuid=p_actor)
      or ((d->>'stateCode')::integer=100 and (
        ((actual->>'stateCode')::integer=100 and actual->>'sha256'=d->>'sha256')
        or (captured_owner=p_actor and nullif(actual->>'ownerActorId','')::uuid=p_actor))),
      'DISCLOSURE_DENIED');
  end loop;
end $$;

-- A first source read freezes the authorized export once; retries retain exact
-- byte strings/time/facts rather than silently adopting a later mutable draft.
create function api.svc_study_source_acquisition_read_input_v1(p_acquisition_id uuid,p_job_id uuid,p_lease_token uuid) returns jsonb
language plpgsql security definer set search_path='' set statement_timeout='15s' as $$
declare a private.study_source_acquisitions%rowtype; packet jsonb;
begin
  perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
  select * into a from private.study_source_acquisitions where id=p_acquisition_id;
  perform private.study_require(a.job_id=p_job_id,'REFERENCE_MISMATCH');
  perform private.study_authorize(a.study_id,a.requested_by,a.requested_client_id,'write');
  perform private.study_lock_job(a.study_id,p_job_id,p_lease_token,'study.source_acquire','acquisitionId',a.id);
  -- A same-lease request may have captured while this caller waited for the
  -- ordered Study/job locks. Use the committed packet, never the pre-lock row.
  select * into a from private.study_source_acquisitions where id=p_acquisition_id;
  perform private.study_require(found and a.job_id=p_job_id,'REFERENCE_MISMATCH');
  if a.source_packet is null then
    packet:=private.study_capture_source(a.origin_ref,a.requested_by,a.requested_client_id);
    perform private.study_require(octet_length(packet::text)<=4194304,'CAPABILITY_UNAVAILABLE');
    update private.study_source_acquisitions set source_packet=packet where id=a.id;
  else packet:=a.source_packet; perform private.study_source_rights(packet->'sourceAuthorization'->'sourceScope',a.requested_by,a.requested_client_id); end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('acquisition',private.study_record('modelSourceAcquisition',a.id),'sourcePacket',packet));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or numeric_value_out_of_range or invalid_parameter_value then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
end $$;

-- Existing raw source packets are sensitive even when a research model is
-- shared. Ordinary storage access is closed for this bucket independently of
-- every existing permissive policy; the Edge service performs scoped delivery.
do $$ begin
  if exists(select 1 from storage.buckets where id='study-artifacts' and(public or file_size_limit is distinct from 4194304::bigint)) then
    raise exception 'study_storage_precondition_drift';
  end if;
end $$;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('study-artifacts','study-artifacts',false,4194304,array['application/json','application/zip','text/html']) on conflict(id) do nothing;
create policy study_artifacts_raw_closed on storage.objects as restrictive for all to anon,authenticated
  using(bucket_id<>'study-artifacts') with check(bucket_id<>'study-artifacts');

-- Keep the complete canonical queue implementation and its OIDs/ACL/settings;
-- inject only a closed Study routing guard. A client cannot choose the local
-- context; only postgres-owned scoped admission/complete/cancel helpers set it.
create function private.study_generic_job_allowed(p_kind text,p_job uuid,p_action text) returns boolean
language plpgsql stable security definer set search_path='' as $$ declare kind text:=p_kind; begin
  if kind is null and p_job is not null then select job_kind into kind from private.worker_jobs where id=p_job; end if;
  -- Match the canonical enqueuer's normalization before classifying its route.
  kind:=lower(trim(kind));
  return kind is null or kind not like 'study.%' or coalesce(current_setting('app.study.task_context',true)=p_action,false);
end $$;
do $$ declare f record; definition text; injected text; action text; condition text; before_text text; after_text text; begin
  for f in select p.oid,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname in('worker_enqueue_job','worker_read_job','worker_cancel_job','worker_retry_job','worker_record_job_result') loop
    definition:=pg_get_functiondef(f.oid);
    action:=case f.proname when 'worker_enqueue_job' then 'enqueue' when 'worker_cancel_job' then 'cancel' when 'worker_record_job_result' then 'complete' when 'worker_retry_job' then 'retry' else 'read' end;
    condition:=case f.proname when 'worker_enqueue_job' then 'p_job_kind,null' else 'null,p_job_id' end;
    injected:=format(E'\nbegin\n  if not private.study_generic_job_allowed(%s,%L) then return jsonb_build_object(''ok'',false,''code'',''STUDY_SCOPED_ROUTE_REQUIRED'',''status'',403,''message'',''Study task requires scoped authorization''); end if;\n',condition,action);
    perform private.study_require(position('private.study_generic_job_allowed' in definition)=0,'REFERENCE_MISMATCH');
    after_text:=regexp_replace(definition,E'\nbegin\n',injected,'i'); perform private.study_require(after_text<>definition,'REFERENCE_MISMATCH'); execute after_text;
  end loop;
  select pg_get_functiondef('private.worker_list_jobs(uuid,text,uuid,text[],text,integer,boolean)'::regprocedure) into definition;
  after_text:=replace(definition,'where (p_requested_by is null or requested_by = p_requested_by)',E'where job_kind not like ''study.%''\n      and (p_requested_by is null or requested_by = p_requested_by)');
  perform private.study_require(after_text<>definition,'REFERENCE_MISMATCH'); execute after_text;
  select pg_get_functiondef('private.worker_read_latest_job(uuid,text,uuid,text,text,text[],boolean)'::regprocedure) into definition;
  after_text:=replace(definition,'where (p_requested_by is null or requested_by = p_requested_by)',E'where job_kind not like ''study.%'' and (p_requested_by is null or requested_by = p_requested_by)');
  perform private.study_require(after_text<>definition,'REFERENCE_MISMATCH'); execute after_text;
  select pg_get_functiondef('private.get_task_summary_v2_feed_unversioned(text,text[],text[],timestamp with time zone,timestamp with time zone,uuid,integer,boolean)'::regprocedure) into definition;
  after_text:=replace(definition,'where j.requested_by = a',E'where j.job_kind not like ''study.%'' and j.requested_by = a');
  perform private.study_require(after_text<>definition,'REFERENCE_MISMATCH'); execute after_text;
  -- Domain completion validates the frozen source context only for a new write,
  -- while an exact committed receipt remains recoverable under service authority.
  select pg_get_functiondef('private.study_complete(text,uuid,uuid,uuid,jsonb,text)'::regprocedure) into definition;
  after_text:=replace(definition,'perform private.study_lock_job(sid,p_job,p_token,expected_kind,subject,p_id);',E'perform private.study_validate_task_completion(p_kind,p_id,p_completion);\n  perform private.study_lock_job(sid,p_job,p_token,expected_kind,subject,p_id);');
  after_text:=replace(after_text,'jresult:=private.worker_record_job_result',E'perform set_config(''app.study.task_context'',''complete'',true);\n  jresult:=private.worker_record_job_result');
  after_text:=replace(after_text,'perform private.study_require((jresult->>''ok'')::boolean,''FORBIDDEN'');',E'perform set_config(''app.study.task_context'','''',true);\n  perform private.study_require((jresult->>''ok'')::boolean,''FORBIDDEN'');');
  perform private.study_require(after_text<>definition,'REFERENCE_MISMATCH'); execute after_text;
end $$;

-- Capture is a one-time field; all original source/preparation/run bindings
-- remain immutable. The first snapshot publication remains separately fenced.
do $$ declare definition text; replacement text; begin
  select pg_get_functiondef('private.study_guard_immutable()'::regprocedure) into definition;
  replacement:=replace(definition,$needle$(to_jsonb(old)-'snapshot_id') is distinct from (to_jsonb(new)-'snapshot_id')$needle$,$replacement$(to_jsonb(old)-'snapshot_id'-'source_packet') is distinct from (to_jsonb(new)-'snapshot_id'-'source_packet')$replacement$);
  replacement:=replace(replacement,$needle$if old.snapshot_id is not null and old.snapshot_id is distinct from new.snapshot_id then raise exception 'FROZEN_REVISION'; end if;$needle$,$replacement$if old.snapshot_id is not null and old.snapshot_id is distinct from new.snapshot_id then raise exception 'FROZEN_REVISION'; end if; if old.source_packet is not null and old.source_packet is distinct from new.source_packet then raise exception 'FROZEN_REVISION'; end if;$replacement$);
  perform private.study_require(replacement<>definition,'REFERENCE_MISMATCH'); execute replacement;
end $$;

do $$ declare f record; identity text; begin
  for f in select p.oid::regprocedure as id from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname like 'study_%' and p.proname<>'study_source_visible_row' loop
    execute format('revoke all on function %s from public,anon,authenticated,service_role',f.id);
  end loop;
  for f in select p.oid::regprocedure as id,n.nspname,p.proname,pg_catalog.oidvectortypes(p.proargtypes) args
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='api' and (p.proname like 'svc_study_%' or p.proname in('cmd_study_v1','qry_study_v1')) loop
    execute format('revoke all on function %s from public,anon,authenticated,service_role',f.id);
    if f.proname like 'svc_%' then
      execute format('grant execute on function %s to service_role',f.id); identity:=format('%I.%I(%s)',f.nspname,f.proname,f.args);
      insert into private.api_capability_grants values(identity,'STUDY-SERVICE-01',false,false,true) on conflict(routine_identity) do nothing;
    else execute format('grant execute on function %s to authenticated',f.id); end if;
  end loop;
end $$;
notify pgrst,'reload schema';
do $$ declare a record; memberships_after jsonb; begin
  select * into a from study895_owner_authority;
  if not a.had_create then revoke create on schema private from api_internal_executor; end if;
  if a.own_grant is null then revoke api_internal_executor from postgres;
  else execute format('grant api_internal_executor to postgres with admin %s,inherit %s,set %s',a.own_grant->>'admin_option',a.own_grant->>'inherit_option',a.own_grant->>'set_option'); end if;
  select coalesce(jsonb_agg(to_jsonb(m) order by m.grantor,m.oid),'[]'::jsonb) into memberships_after from pg_auth_members m where m.roleid='api_internal_executor'::regrole and m.member='postgres'::regrole;
  if memberships_after is distinct from a.memberships then raise exception 'study_role_authority_restore_failed'; end if;
end $$;
commit;
