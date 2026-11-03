-- Database #904: independently negotiated v3 analysis/reporting. All new
-- submission gates default off; no OAuth/environment grants are installed.
begin;
create table private.study_reporting_config (
 singleton boolean primary key default true check(singleton), revision bigint not null default 1 check(revision>0),
 analysis_enabled boolean not null default false, report_enabled boolean not null default false,
 export_enabled boolean not null default false, qualification_evidence_ref text
);
insert into private.study_reporting_config(singleton) values(true);

-- Closed Worker config permits no arbitrary strings: the exact compact sorted
-- serialization below is byte-identical to its canonical JSON hash contract.
create function private.study_analysis_config_valid(p_config jsonb) returns boolean
language plpgsql immutable set search_path='' as $$ declare x jsonb; seen uuid[]:='{}'::uuid[]; rid uuid; begin
 if not private.study_keys(p_config,array['schemaVersion','kind','runIds'])
  or p_config->>'schemaVersion' is distinct from 'lca.study-analysis-config.v1'
  or coalesce(p_config->>'kind' not in ('contribution','comparison'),true) or jsonb_typeof(p_config->'runIds') is distinct from 'array' then return false; end if;
 if jsonb_array_length(p_config->'runIds')<>(case p_config->>'kind' when 'contribution' then 1 else 2 end) then return false; end if;
 for x in select * from jsonb_array_elements(p_config->'runIds') loop
  if jsonb_typeof(x)<>'string' or x#>>'{}' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return false; end if;
  rid:=(x#>>'{}')::uuid; if rid=any(seen) then return false; end if; seen:=seen||rid;
 end loop; return true;
exception when invalid_text_representation then return false;
end $$;
create function private.study_analysis_config_hash(p_config jsonb) returns text
language sql immutable set search_path='' as $$
 select encode(extensions.digest(convert_to('study.analysis-config.v1','UTF8')||decode('00','hex')||convert_to(
 '{"kind":'||to_jsonb(p_config->>'kind')::text||',"runIds":['||
 (select string_agg(to_jsonb(x#>>'{}')::text,',' order by n) from jsonb_array_elements(p_config->'runIds') with ordinality e(x,n))||
 '],"schemaVersion":"lca.study-analysis-config.v1"}','UTF8'),'sha256'),'hex')
$$;
create function private.study_comparability_valid(p_value jsonb) returns boolean
language plpgsql immutable set search_path='' as $$ declare x jsonb; seen text[]:='{}'::text[]; begin
 if not private.study_keys(p_value,array['status','reasonCodes']) or coalesce(p_value->>'status' not in ('not_assessed','comparable','not_comparable'),true)
 or jsonb_typeof(p_value->'reasonCodes') is distinct from 'array' then return false; end if;
 if jsonb_array_length(p_value->'reasonCodes')>32 then return false; end if;
 for x in select * from jsonb_array_elements(p_value->'reasonCodes') loop
  if not private.study_text(x,128,'^[a-z][a-z0-9_]*$') or (x#>>'{}')=any(seen) then return false; end if;
  seen:=seen||(x#>>'{}');
 end loop; return true;
end $$;
create table private.study_analyses (
 id uuid primary key, study_id uuid not null references private.studies(id),
 profile_id text not null check(profile_id='lca.study-analysis-explicit-v1'),
 config jsonb not null check(private.study_analysis_config_valid(config)),
 config_hash text not null check(config_hash=private.study_analysis_config_hash(config)),
 job_id uuid not null unique references private.worker_jobs(id), requested_by uuid not null references auth.users(id), requested_client_id text,
 comparability jsonb not null default '{"status":"not_assessed","reasonCodes":[]}' check(private.study_comparability_valid(comparability)),
 facts_artifact_id uuid, unique(study_id,id), foreign key(study_id,facts_artifact_id) references private.study_artifacts(study_id,id)
);
create table private.study_analysis_runs (
 study_id uuid not null, analysis_id uuid not null, ordinal integer not null check(ordinal between 1 and 2), run_id uuid not null,
 primary key(analysis_id,ordinal), unique(analysis_id,run_id),
 foreign key(study_id,analysis_id) references private.study_analyses(study_id,id),
 foreign key(study_id,run_id) references private.study_runs(study_id,id)
);
create index study_analysis_actor_idx on private.study_analyses(requested_by);
create index study_analysis_facts_idx on private.study_analyses(facts_artifact_id);
create index study_analysis_run_idx on private.study_analysis_runs(study_id,run_id);
create index study_analysis_study_idx on private.study_analysis_runs(study_id,analysis_id);
insert into private.worker_job_kinds(job_kind,worker_runtime,worker_queue,default_visibility,payload_schema_version,result_schema_version,user_visible,description)
 values('study.analysis','calculator','solver','user','study.analysis.request.v1','lca.study-job-receipt.v1',false,'Study ordered exact-Run analysis; separately qualified default-off admission');

create function private.study_analysis_record(p_id uuid) returns jsonb
language sql security definer set search_path='' as $$
 select jsonb_build_object('analysisId',a.id,'studyId',a.study_id,'profileId',a.profile_id,'config',a.config,'configHash',a.config_hash,
 'execution',jsonb_build_object('jobId',a.job_id,'status',j.status),'comparability',a.comparability,
 'factsRef',case when j.status='completed' then f.ref else null end)
 from private.study_analyses a join private.worker_jobs j on j.id=a.job_id left join private.study_artifacts f on f.id=a.facts_artifact_id where a.id=p_id
$$;
-- P2 locks protect the final current-source decision through commit. They
-- confer no visibility: the existing original-actor NOBYPASS check runs after
-- every exact row is locked. NOWAIT prevents cycles with root-first legacy
-- writers; contention fails closed and an authorized caller can retry its key.
create function private.study_reporting_snapshot_rights(p_snapshot uuid,p_actor uuid,p_client text) returns void
language plpgsql security definer set search_path='' set lock_timeout='2s' as $$
declare scope jsonb;d record;t text;seen_row integer;deadline timestamptz:=clock_timestamp()+interval '10 seconds';begin
 select source_authorization->'sourceScope' into scope from private.study_source_snapshots where id=p_snapshot;
 perform private.study_require(jsonb_typeof(scope)='array' and jsonb_array_length(scope) between 1 and 512,'DISCLOSURE_DENIED');
 for d in select distinct x->>'kind' kind,coalesce(x->>'id',x->'identity'->>'id') id,coalesce(x->>'version',x->'identity'->>'version') version
  from jsonb_array_elements(scope)e(x) order by kind,id,version loop
  perform private.study_require(clock_timestamp()<deadline,'CAPABILITY_UNAVAILABLE');
  t:=case d.kind when 'lifecyclemodel' then 'lifecyclemodels' when 'process' then 'processes' when 'flow' then 'flows' when 'flowproperty' then 'flowproperties' when 'unitgroup' then 'unitgroups' end;
  perform private.study_require(t is not null,'REFERENCE_MISMATCH');
  execute format('select 1 from public.%I where id=$1 and version=$2 for share nowait',t) into seen_row using d.id::uuid,d.version;
  perform private.study_require(seen_row=1,'DISCLOSURE_DENIED');
 end loop;
 perform private.study_snapshot_rights(p_snapshot,p_actor,p_client);
exception when lock_not_available or deadlock_detected then raise exception using errcode='P0001',message='CAPABILITY_UNAVAILABLE';
end $$;
create function private.study_analysis_rights(p_study uuid,p_config jsonb,p_actor uuid,p_client text) returns void
language plpgsql security definer set search_path='' as $$ declare rid text; r private.study_runs%rowtype; begin
 perform private.study_authorize(p_study,p_actor,p_client,'read');
 for rid in select jsonb_array_elements_text(p_config->'runIds') loop
  select * into r from private.study_runs where study_id=p_study and id=rid::uuid for share;
  perform private.study_require(found and r.result_artifact_id is not null
   and exists(select 1 from private.worker_jobs where id=r.job_id and status='completed'),'REFERENCE_MISMATCH');
  perform private.study_require(exists(select 1 from private.study_revisions where study_id=p_study and id=r.study_revision_id and status='frozen')
   and exists(select 1 from private.study_scenarios where study_id=p_study and id=r.scenario_id and status='frozen' and study_revision_id=r.study_revision_id
    and preparation_id=r.preparation_id and effective_model_ref=r.model_ref),'REFERENCE_MISMATCH');
  perform private.study_require(exists(select 1 from private.study_model_preparations p join private.worker_jobs j on j.id=p.job_id where p.study_id=p_study and p.id=r.preparation_id
   and p.model_ref=r.model_ref and p.input_hash=r.input_hash and p.profile_id=r.profile_id and p.calculation_contract_ref=r.calculation_contract_ref and p.input_artifact_id is not null and j.status='completed'),'REFERENCE_MISMATCH');
  perform private.study_reporting_snapshot_rights(private.study_preparation_snapshot(p_study,r.preparation_id),p_actor,p_client);
 end loop;
end $$;
-- Scientific validity gates new producers, independently of access rights.
create function private.study_analysis_require_current(p_study uuid,p_config jsonb) returns void
language plpgsql security definer set search_path='' as $$begin
 perform private.study_require(not exists(select 1 from jsonb_array_elements_text(p_config->'runIds')e(id)
  left join private.study_runs r on r.study_id=p_study and r.id=e.id::uuid where r.id is null or r.validity<>'current'),'CAPABILITY_UNAVAILABLE');
end $$;
create function private.study_reporting_envelope(p_request jsonb,p_write boolean) returns void
language plpgsql set search_path='' as $$ begin
 perform private.study_require(auth.uid() is not null and not coalesce(util.is_service_request(),false),'AUTH_REQUIRED');
 perform private.study_require(p_request->>'schemaVersion'='lca.study-api.v3' and octet_length(p_request::text)<=262144
  and private.study_text(p_request->'requestId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');
 if p_write then perform private.study_require(private.study_text(p_request->'idempotencyKey',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST'); end if;
end $$;
create function private.study_analysis_request(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' set statement_timeout='15s' as $$
declare sid uuid:=(p_request->>'studyId')::uuid; actor uuid:=auth.uid(); client text:=nullif(auth.jwt()->>'client_id','');
 req jsonb:=p_request-'schemaVersion'-'requestId'-'idempotencyKey'; key text:=p_request->>'idempotencyKey';
 previous private.study_command_receipts%rowtype; aid uuid:=gen_random_uuid(); job uuid; result jsonb;
 old_role text; old_context text; s private.studies%rowtype;
begin
 perform private.study_reporting_envelope(p_request,true);
 perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','idempotencyKey','operation','studyId','profileId','config','configHash'])
  and p_request->>'operation'='analysis.request' and p_request->>'profileId'='lca.study-analysis-explicit-v1'
  and private.study_analysis_config_valid(p_request->'config'),'INVALID_REQUEST');
 perform private.study_require(p_request->>'configHash'=private.study_analysis_config_hash(p_request->'config'),'REFERENCE_MISMATCH');
 perform private.study_authorize(sid,actor,client,'write');
 -- Live input rights precede receipt recovery as well as fresh admission.
 perform private.study_analysis_rights(sid,p_request->'config',actor,client);
 select * into previous from private.study_command_receipts where actor_id=actor and operation='analysis.request' and scope=sid::text and idempotency_key=key;
 if found then perform private.study_require(previous.request=req,'IDEMPOTENCY_CONFLICT'); return previous.response; end if;
 perform private.study_analysis_require_current(sid,p_request->'config');
 select * into s from private.studies where id=sid;
 perform private.study_require(s.status='active','FROZEN_REVISION');
 perform private.study_require((select analysis_enabled from private.study_reporting_config where singleton),'CAPABILITY_UNAVAILABLE');
 old_role:=current_setting('request.jwt.claim.role',true); old_context:=current_setting('app.study.task_context',true);
 perform set_config('request.jwt.claim.role','service_role',true); perform set_config('app.study.task_context','enqueue',true);
 result:=private.worker_enqueue_job('study.analysis',jsonb_build_object('schemaVersion','study.analysis.request.v1','studyId',sid,'analysisId',aid),
 'study.analysis.request.v1','study',aid,null,actor,'user',s.team_id,actor::text||':'||sid::text||':study.analysis:'||key,
 private.study_content_hash('lca.study-job-request.v1',req),null,0,null,null,'user');
 perform set_config('request.jwt.claim.role',coalesce(old_role,''),true); perform set_config('app.study.task_context',coalesce(old_context,''),true);
 perform private.study_require((result->>'ok')::boolean,'CAPABILITY_UNAVAILABLE'); job:=(result->'data'->>'id')::uuid;
 insert into private.study_analyses(id,study_id,profile_id,config,config_hash,job_id,requested_by,requested_client_id)
 values(aid,sid,p_request->>'profileId',p_request->'config',p_request->>'configHash',job,actor,client);
 insert into private.study_analysis_runs(study_id,analysis_id,ordinal,run_id)
 select sid,aid,n,(v#>>'{}')::uuid from jsonb_array_elements(p_request->'config'->'runIds') with ordinality e(v,n);
 result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','analysis','value',private.study_analysis_record(aid)));
 insert into private.study_command_receipts values(actor,'analysis.request',sid::text,key,req,result,clock_timestamp()); return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range or not_null_violation or check_violation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');
end $$;

create function private.study_analysis_lock_job(p_study uuid,p_job uuid,p_token uuid,p_analysis uuid) returns void
language plpgsql security definer set search_path='' as $$begin
 perform private.study_lock_job(p_study,p_job,p_token,'study.analysis','analysisId',p_analysis);
 perform private.study_require(exists(select 1 from private.worker_jobs j join private.study_analyses a on a.job_id=j.id
 where a.id=p_analysis and a.study_id=p_study and j.id=p_job and j.subject_type='study' and j.subject_id=p_analysis
 and j.worker_queue='solver' and j.payload_schema_version='study.analysis.request.v1' and j.requested_by=a.requested_by
 and j.payload_json=jsonb_build_object('schemaVersion','study.analysis.request.v1','studyId',p_study,'analysisId',p_analysis)),'REFERENCE_MISMATCH');
end $$;
create function api.svc_study_analysis_read_input_v1(p_analysis_id uuid,p_job_id uuid,p_lease_token uuid) returns jsonb
language plpgsql security definer set search_path='' as $$ declare a private.study_analyses%rowtype; inputs jsonb; begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 select * into a from private.study_analyses where id=p_analysis_id;
 perform private.study_require(found and a.job_id=p_job_id,'REFERENCE_MISMATCH');
 perform private.study_authorize(a.study_id,a.requested_by,a.requested_client_id,'write');
 perform private.study_analysis_rights(a.study_id,a.config,a.requested_by,a.requested_client_id);
 perform private.study_analysis_require_current(a.study_id,a.config);
 perform private.study_analysis_lock_job(a.study_id,p_job_id,p_lease_token,p_analysis_id);
 select jsonb_agg(jsonb_build_object('run',private.study_record('run',r.id),'revision',private.study_record('studyRevision',r.study_revision_id),
 'scenario',private.study_record('scenarioRevision',r.scenario_id),'preparation',private.study_record('modelPreparation',r.preparation_id),
 'preparedArtifact',private.study_private_artifact(a.study_id,p.input_artifact_id),'resultArtifact',private.study_private_artifact(a.study_id,r.result_artifact_id)) order by l.ordinal)
 into inputs from private.study_analysis_runs l join private.study_runs r on r.study_id=l.study_id and r.id=l.run_id
 join private.study_model_preparations p on p.study_id=r.study_id and p.id=r.preparation_id where l.analysis_id=a.id;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('schemaVersion','lca.study-analysis-input.v1','analysis',private.study_analysis_record(a.id)-'comparability'-'factsRef','runs',inputs));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end $$;
create function api.svc_study_analysis_complete_v1(p_analysis_id uuid,p_job_id uuid,p_lease_token uuid,p_completion jsonb,p_idempotency_key text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a private.study_analyses%rowtype; previous private.study_service_receipts%rowtype; request jsonb; result jsonb; artifact uuid; old_context text;
begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 perform private.study_require(private.study_text(to_jsonb(p_idempotency_key),128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');
 select * into a from private.study_analyses where id=p_analysis_id;
 perform private.study_require(found and a.job_id=p_job_id,'REFERENCE_MISMATCH');
 perform private.study_authorize(a.study_id,a.requested_by,a.requested_client_id,'write');
 perform private.study_analysis_rights(a.study_id,a.config,a.requested_by,a.requested_client_id);
 request:=jsonb_build_object('id',p_analysis_id,'jobId',p_job_id,'leaseToken',p_lease_token,'completion',p_completion);
 select * into previous from private.study_service_receipts where operation='analysis' and study_id=a.study_id and idempotency_key=p_idempotency_key;
 if found then perform private.study_require(previous.request=request and previous.job_id=p_job_id and previous.lease_token=p_lease_token,'IDEMPOTENCY_CONFLICT'); return previous.response; end if;
 perform private.study_analysis_require_current(a.study_id,a.config);
 perform private.study_analysis_lock_job(a.study_id,p_job_id,p_lease_token,p_analysis_id);
 perform private.study_require(a.facts_artifact_id is null and private.study_keys(p_completion,array['profileId','configHash','comparability','factsRef','storageBucket','storageObjectPath'])
 and p_completion->>'profileId'=a.profile_id and p_completion->>'configHash'=a.config_hash and private.study_comparability_valid(p_completion->'comparability')
 and p_completion->'factsRef'->>'schemaVersion'='lca.study-analysis-facts.v1' and p_completion->'factsRef'->>'mediaType'='application/json','REFERENCE_MISMATCH');
 artifact:=private.study_store_artifact(a.study_id,p_completion->'factsRef',p_completion->>'storageBucket',p_completion->>'storageObjectPath','analysisFacts');
 update private.study_analyses set facts_artifact_id=artifact,comparability=p_completion->'comparability' where id=p_analysis_id;
 old_context:=current_setting('app.study.task_context',true); perform set_config('app.study.task_context','complete',true);
 result:=private.worker_record_job_result(p_job_id,p_lease_token,'completed',jsonb_build_object('schemaVersion','lca.study-job-receipt.v1','studyId',a.study_id,'resourceType','analysis','resourceId',a.id),'lca.study-job-receipt.v1',p_completion->'factsRef');
 perform set_config('app.study.task_context',coalesce(old_context,''),true); perform private.study_require((result->>'ok')::boolean,'FORBIDDEN');
 result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','analysis','value',private.study_analysis_record(a.id)));
 insert into private.study_service_receipts values('analysis',a.study_id,p_idempotency_key,p_job_id,p_lease_token,request,result); return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or numeric_value_out_of_range or check_violation or not_null_violation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');
end $$;

create function private.study_reporting_task(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare sid uuid:=(p_request->>'studyId')::uuid; actor uuid:=auth.uid(); client text:=nullif(auth.jwt()->>'client_id','');
 op text:=p_request->>'operation'; a private.study_analyses%rowtype; j private.worker_jobs%rowtype; result jsonb;
 old_role text; old_context text; previous private.study_command_receipts%rowtype; req jsonb:=p_request-'schemaVersion'-'requestId'-'idempotencyKey';
begin
 perform private.study_reporting_envelope(p_request,op='task.cancel');
 perform private.study_require(private.study_keys(p_request->'resource',array['type','id']) and p_request->'resource'->>'type'='analysis','INVALID_REQUEST');
 perform private.study_authorize(sid,actor,client,case when op='task.cancel' then 'write' else 'read' end);
 select * into a from private.study_analyses where study_id=sid and id=(p_request->'resource'->>'id')::uuid;
 perform private.study_require(found,'FORBIDDEN');
 if op='task.cancel' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','idempotencyKey','studyId','resource','reason']) and private.study_text(p_request->'reason',512),'INVALID_REQUEST');
  select * into previous from private.study_command_receipts where actor_id=actor and operation=op and scope=sid::text and idempotency_key=p_request->>'idempotencyKey';
  if found then perform private.study_require(previous.request=req,'IDEMPOTENCY_CONFLICT'); return previous.response; end if;
  old_role:=current_setting('request.jwt.claim.role',true); old_context:=current_setting('app.study.task_context',true);
  perform set_config('request.jwt.claim.role','service_role',true); perform set_config('app.study.task_context','cancel',true);
  result:=private.worker_cancel_job(a.job_id,actor,'Study task cancelled');
  perform set_config('request.jwt.claim.role',coalesce(old_role,''),true); perform set_config('app.study.task_context',coalesce(old_context,''),true);
  perform private.study_require((result->>'ok')::boolean,'REVISION_CONFLICT');
 else perform private.study_require(op='task.read' and private.study_keys(p_request,array['schemaVersion','requestId','operation','studyId','resource']),'INVALID_REQUEST'); end if;
 select * into j from private.worker_jobs where id=a.job_id;
 result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','task','value',jsonb_build_object('studyId',sid,'resource',p_request->'resource',
 'execution',jsonb_build_object('jobId',j.id,'status',j.status,'phase',case when j.phase in ('queued','complete','cancelled','study_start','study_native','study_artifact','study_publish') then j.phase else null end,'progress',j.progress),
 'errorCode',case when j.error_code=any(array['source_invalid','boundary_undeclared','normalization_underflow','normalization_overflow','numeric_invalid','resource_limit','model_not_solvable','native_execution_failed','job_timeout','job_lease_lost','runtime_unavailable','runtime_failed']) then j.error_code else null end)));
 if op='task.cancel' then insert into private.study_command_receipts values(actor,op,sid::text,p_request->>'idempotencyKey',req,result,clock_timestamp()); end if;
 return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
end $$;
create function private.study_reporting_artifact_authorize(p_study uuid,p_ref jsonb,p_actor uuid,p_client text) returns jsonb
language plpgsql security definer set search_path='' as $$ declare a private.study_analyses%rowtype; artifact private.study_artifacts%rowtype; begin
 if p_ref->>'type'<>'analysisFacts' then return private.study_artifact_authorize(p_study,p_ref,p_actor,p_client); end if;
 perform private.study_authorize(p_study,p_actor,p_client,'read');
 perform private.study_require((select disclosure_enabled from private.study_runtime_config where singleton),'CAPABILITY_UNAVAILABLE');
 select * into artifact from private.study_artifacts where study_id=p_study and id=(p_ref->>'id')::uuid;
 perform private.study_require(found and artifact.ref=p_ref,'REFERENCE_MISMATCH');
 select * into a from private.study_analyses where study_id=p_study and facts_artifact_id=artifact.id;
 perform private.study_require(found and exists(select 1 from private.worker_jobs where id=a.job_id and status='completed'),'DISCLOSURE_DENIED');
 perform private.study_analysis_rights(p_study,a.config,p_actor,p_client);
 return jsonb_build_object('kind','artifactCapability','studyId',p_study,'artifactRef',artifact.ref,'storageBucket',artifact.bucket,'storageObjectPath',artifact.object_path);
end $$;
create function private.study_reporting_artifact_intent(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare sid uuid:=(p_request->>'studyId')::uuid; actor uuid:=auth.uid(); client text:=nullif(auth.jwt()->>'client_id',''); intent uuid; expiry timestamptz; begin
 perform private.study_reporting_envelope(p_request,false);
 perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','studyId','artifactRef']) and p_request->>'operation'='artifact.read','INVALID_REQUEST');
 perform private.study_reporting_artifact_authorize(sid,p_request->'artifactRef',actor,client);
 perform pg_advisory_xact_lock(hashtextextended('study-artifact-intent:'||actor::text,895));
 with expired as(select id from private.study_artifact_read_intents where expires_at<=clock_timestamp() order by expires_at,id limit 256 for update skip locked)
 delete from private.study_artifact_read_intents i using expired e where i.id=e.id;
 perform private.study_require((select count(*) from private.study_artifact_read_intents where actor_id=actor and expires_at>clock_timestamp())<64,'CAPABILITY_UNAVAILABLE');
 insert into private.study_artifact_read_intents(study_id,artifact_id,artifact_ref,actor_id,client_id)
 values(sid,(p_request->'artifactRef'->>'id')::uuid,p_request->'artifactRef',actor,client) returning id,expires_at into intent,expiry;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('kind','artifactReadIntent','intentId',intent,'expiresAt',expiry,'studyId',sid,'artifactRef',p_request->'artifactRef'));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
end $$;
-- The v2 actor gate remains unchanged. Service resolution recognizes a v3 intent
-- while rechecking the same original live actor/client/source authorization.
create or replace function api.svc_study_artifact_read_resolve_v1(p_intent_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$ declare i private.study_artifact_read_intents%rowtype; begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 select * into i from private.study_artifact_read_intents where id=p_intent_id;
 perform private.study_require(found and i.expires_at>clock_timestamp(),'CAPABILITY_UNAVAILABLE');
 return jsonb_build_object('ok',true,'data',private.study_reporting_artifact_authorize(i.study_id,i.artifact_ref,i.actor_id,i.client_id));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end $$;

create function api.svc_study_reporting_configure_v1(p_expected_revision bigint,p_configuration jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$ declare cfg private.study_reporting_config%rowtype; begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 perform private.study_require(private.study_keys(p_configuration,array['schemaVersion','analysisEnabled','reportEnabled','exportEnabled','qualificationEvidenceRef'])
 and p_configuration->>'schemaVersion'='lca.study-reporting-qualification.v1'
 and jsonb_typeof(p_configuration->'analysisEnabled')='boolean' and jsonb_typeof(p_configuration->'reportEnabled')='boolean' and jsonb_typeof(p_configuration->'exportEnabled')='boolean'
 and private.study_text(p_configuration->'qualificationEvidenceRef',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');
 select * into cfg from private.study_reporting_config where singleton for update;
 perform private.study_require(cfg.revision=p_expected_revision,'REVISION_CONFLICT');
 update private.study_reporting_config set revision=revision+1,analysis_enabled=(p_configuration->>'analysisEnabled')::boolean,
 report_enabled=(p_configuration->>'reportEnabled')::boolean,export_enabled=(p_configuration->>'exportEnabled')::boolean,
 qualification_evidence_ref=p_configuration->>'qualificationEvidenceRef' where singleton;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('revision',cfg.revision+1));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end $$;

create function api.cmd_study_reporting_v1(p_request jsonb) returns jsonb language plpgsql security definer set search_path='' as $$ begin
 if p_request->>'operation'='analysis.request' then return private.study_analysis_request(p_request); end if;
 if p_request->>'operation'='task.cancel' then return private.study_reporting_task(p_request); end if;
 return jsonb_build_object('ok',false,'code','CAPABILITY_UNAVAILABLE');
end $$;
create function api.qry_study_reporting_v1(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare client text:=nullif(auth.jwt()->>'client_id',''); actor uuid:=auth.uid(); a private.study_analyses%rowtype; ops jsonb; cfg private.study_reporting_config%rowtype; begin
 perform private.study_reporting_envelope(p_request,false);
 perform private.study_require(private.study_client_allowed(client,'STUDY-READ-01'),'FORBIDDEN');
 case p_request->>'operation'
 when 'capability.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation']),'INVALID_REQUEST');
  select * into cfg from private.study_reporting_config where singleton;
  ops:=jsonb_build_array('capability.read','analysis.read','task.read');
  if private.study_client_allowed(client,'STUDY-WRITE-01') then
   ops:=ops||jsonb_build_array('task.cancel');
   if cfg.analysis_enabled and private.study_client_allowed(client,'DB-CORE-READ-01') then ops:=ops||jsonb_build_array('analysis.request'); end if;
  end if;
  if (select disclosure_enabled from private.study_runtime_config where singleton) and private.study_client_allowed(client,'DB-CORE-READ-01') then ops:=ops||jsonb_build_array('artifact.read'); end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','capabilities','contractVersion','3.0.0','runtimeEnabled',cfg.analysis_enabled or cfg.report_enabled or cfg.export_enabled,'operations',ops,'analysisProfiles',case when cfg.analysis_enabled then jsonb_build_array('lca.study-analysis-explicit-v1') else '[]'::jsonb end,'reportTemplates',case when cfg.report_enabled then jsonb_build_array('lca.study-report.v1') else '[]'::jsonb end));
 when 'analysis.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','analysisId']),'INVALID_REQUEST');
  select * into a from private.study_analyses where id=(p_request->>'analysisId')::uuid;
  perform private.study_require(found,'FORBIDDEN'); perform private.study_authorize(a.study_id,actor,client,'read');
  perform private.study_analysis_rights(a.study_id,a.config,actor,client);
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','analysis','value',private.study_analysis_record(a.id)));
 when 'task.read' then return private.study_reporting_task(p_request);
 when 'artifact.read' then return private.study_reporting_artifact_intent(p_request);
 else return jsonb_build_object('ok',false,'code','CAPABILITY_UNAVAILABLE');
 end case;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
end $$;

-- New immutable identities share the existing service callback transaction.
create function private.study_analysis_immutable() returns trigger language plpgsql set search_path='' as $$ begin
 if tg_op='DELETE' or tg_table_name='study_analysis_runs' then raise exception 'FROZEN_REVISION'; end if;
 if (to_jsonb(old)-'facts_artifact_id'-'comparability') is distinct from (to_jsonb(new)-'facts_artifact_id'-'comparability')
 or old.facts_artifact_id is not null then raise exception 'FROZEN_REVISION'; end if;
 return new;
end $$;
create trigger study_analysis_immutable before update or delete on private.study_analyses for each row execute function private.study_analysis_immutable();
create trigger study_analysis_runs_immutable before update or delete on private.study_analysis_runs for each row execute function private.study_analysis_immutable();

-- Extend the two service reconciliation seams, without broadening actor v2
-- dispatch or generic job APIs (the existing study.% fence already covers it).
do $$ declare definition text; replacement text; begin
 select pg_get_functiondef('api.svc_study_task_reconcile_v1(text,uuid,uuid,uuid,text,uuid)'::regprocedure) into definition;
 replacement:=replace(definition,$n$when 'run' then select study_id,job_id into sid,bound_job from private.study_runs where id=p_resource_id;$n$,
 $r$when 'run' then select study_id,job_id into sid,bound_job from private.study_runs where id=p_resource_id;
 when 'analysis' then select study_id,job_id into sid,bound_job from private.study_analyses where id=p_resource_id;$r$);
 replacement:=replace(replacement,$n$select * into j from private.worker_jobs where id=p_job_id for update;$n$,$r$select * into j from private.worker_jobs where id=p_job_id for update;
 if p_resource_type='analysis' then
  perform private.study_require(j.job_kind='study.analysis' and j.worker_runtime='calculator' and j.worker_queue='solver' and j.subject_type='study' and j.subject_id=p_resource_id
   and j.payload_schema_version='study.analysis.request.v1' and j.payload_json=jsonb_build_object('schemaVersion','study.analysis.request.v1','studyId',sid,'analysisId',p_resource_id)
   and exists(select 1 from private.study_analyses a where a.id=p_resource_id and a.study_id=sid and a.job_id=p_job_id and a.requested_by=j.requested_by),'REFERENCE_MISMATCH');
 end if;$r$);
 perform private.study_require(replacement<>definition,'REFERENCE_MISMATCH'); execute replacement;
 select pg_get_functiondef('api.svc_study_task_fail_v1(text,uuid,uuid,uuid,text,text)'::regprocedure) into definition;
 replacement:=replace(definition,$n$when 'run' then select study_id,job_id into sid,job from private.study_runs where id=p_resource_id; kind:='study.run'; subject:='runId';$n$,
 $r$when 'run' then select study_id,job_id into sid,job from private.study_runs where id=p_resource_id; kind:='study.run'; subject:='runId';
 when 'analysis' then select study_id,job_id into sid,job from private.study_analyses where id=p_resource_id; kind:='study.analysis'; subject:='analysisId';$r$);
 replacement:=replace(replacement,$n$perform private.study_lock_job(sid,p_job_id,p_lease_token,kind,subject,p_resource_id);$n$,$r$if p_resource_type='analysis' then perform private.study_analysis_lock_job(sid,p_job_id,p_lease_token,p_resource_id);
 else perform private.study_lock_job(sid,p_job_id,p_lease_token,kind,subject,p_resource_id);end if;$r$);
 replacement:=replace(replacement,$n$private.study_record(p_resource_type,p_resource_id)$n$,$r$case when p_resource_type='analysis' then private.study_analysis_record(p_resource_id) else private.study_record(p_resource_type,p_resource_id) end$r$);
 perform private.study_require(replacement<>definition,'REFERENCE_MISMATCH'); execute replacement;
end $$;

do $$ declare n text; f record; ident text; begin
 foreach n in array array['study_reporting_config','study_analyses','study_analysis_runs'] loop
  execute format('alter table private.%I enable row level security',n); execute format('alter table private.%I force row level security',n);
  execute format('revoke all on private.%I from public,anon,authenticated,service_role',n);
 end loop;
 for f in select p.oid::regprocedure id from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname like 'study_%' and p.proname<>'study_source_visible_row' loop
  execute format('revoke all on function %s from public,anon,authenticated,service_role',f.id);
 end loop;
 for f in select p.oid::regprocedure id,p.proname,pg_catalog.oidvectortypes(p.proargtypes) args from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='api' and p.proname in ('cmd_study_reporting_v1','qry_study_reporting_v1','svc_study_analysis_read_input_v1','svc_study_analysis_complete_v1','svc_study_reporting_configure_v1') loop
  execute format('revoke all on function %s from public,anon,authenticated,service_role',f.id);
  execute format('grant execute on function %s to %I',f.id,case when f.proname like 'svc_%' then 'service_role' else 'authenticated' end);
  ident:=format('api.%I(%s)',f.proname,f.args);
  insert into private.api_capability_grants values(ident,case when f.proname like 'svc_%' then 'STUDY-SERVICE-01' when f.proname like 'cmd_%' then 'STUDY-WRITE-01' else 'STUDY-READ-01' end,false,f.proname not like 'svc_%',f.proname like 'svc_%');
 end loop;
end $$;
notify pgrst,'reload schema';
commit;
