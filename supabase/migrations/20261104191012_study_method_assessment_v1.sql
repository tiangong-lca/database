-- Database #912: distinct V6 method assessment and declared evidence. No scientific approval.
begin;
create function private.study_method_uuid(p_value jsonb) returns boolean language sql immutable set search_path='' as $$
 select jsonb_typeof(p_value)='string' and (p_value#>>'{}') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' and (p_value#>>'{}')<>'00000000-0000-0000-0000-000000000000'$$;
create function private.study_method_text(p_value jsonb,p_max integer) returns boolean language plpgsql immutable set search_path='' as $$declare v text;begin
 if jsonb_typeof(p_value) is distinct from 'string' then return false;end if;v:=p_value#>>'{}';
 return octet_length(v) between 1 and p_max and v !~ U&'[\0001-\001F\007F-\009F]'
 and btrim(v,U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000')<>'';
end$$;
create function private.study_method_uint(p_value jsonb,p_min integer,p_max integer) returns boolean
language plpgsql immutable set search_path='' as $$begin
 return coalesce(jsonb_typeof(p_value)='number' and p_value::text ~ '^(0|[1-9][0-9]*)$' and(p_value#>>'{}')::numeric between p_min and p_max,false);
exception when invalid_text_representation or numeric_value_out_of_range then return false;end$$;
create function private.study_method_artifact_valid(p_ref jsonb,p_type text,p_schema text,p_max integer default 4194304) returns boolean
language plpgsql immutable set search_path='' as $$begin
 return coalesce(private.study_keys(p_ref,array['type','id','contentHash','digestScope','byteSize','mediaType','schemaVersion'])
 and private.study_method_uuid(p_ref->'id') and p_ref->>'type'=p_type and p_ref->>'schemaVersion'=p_schema
 and p_ref->>'digestScope'='artifact_bytes_sha256' and p_ref->>'mediaType'='application/json'
 and private.study_text(p_ref->'contentHash',64,'^[0-9a-f]{64}$') and private.study_method_uint(p_ref->'byteSize',1,p_max),false);
 exception when invalid_text_representation or numeric_value_out_of_range then return false;end$$;
create function private.study_method_module() returns jsonb language sql immutable set search_path='' as $module$select '{"repository":"tiangong-lca/pcr","sourceCommit":"51c0842c67b14ba886e2edee2846e26eefac030f","moduleId":"method.pef-2021-ef31","moduleVersion":"0.1.0","artifactSha256":"b19ba5754b0bc20c44c8c65966bafafd5984cd74636f2c805c0fa4373f5554ad","reviewBasisSha256":"989391423c7f31bdf77e18ea4438fab1a27ff6708c0f44ecad8ab8813763a165","sourceBindingsSha256":"3fd9b1dc68228db3e146b6d23daac853b27b9f504f9445a0cc5a971d53257ce2"}'::jsonb$module$;
create function private.study_method_config_valid(p_config jsonb) returns boolean
language plpgsql stable set search_path='' as $$declare d jsonb;rule jsonb;e jsonb;seen text[]:='{}'::text[];k text;begin
 if not private.study_keys(p_config,array['schemaVersion','baselineRunId','moduleRef','declarations','evidenceRefs'])
 or p_config->>'schemaVersion' is distinct from 'lca.study-method-assessment-config.v1'
 or not private.study_method_uuid(p_config->'baselineRunId') or p_config->'moduleRef' is distinct from private.study_method_module()
 or octet_length(private.study_reporting_canonical(p_config))>262144 then return false;end if;
 d:=p_config->'declarations';rule:=d->'categoryRule';
 if not private.study_keys(d,array['productRole','studyPhase','referenceUnitBasis','categoryRule'])
 or d->>'productRole' is distinct from 'finishedCementIntermediate' or d->>'studyPhase' not in('screening','finalStudy')
 or jsonb_typeof(d->'studyPhase') is distinct from 'string' or d->>'referenceUnitBasis' is distinct from 'declaredMass' then return false;end if;
 if rule->>'kind'='noneEstablished' then if not private.study_keys(rule,array['kind']) then return false;end if;
 elsif rule->>'kind'='commissionDeveloped' then
  if not private.study_keys(rule,array['kind','referenceId','version','evidenceId']) or not private.study_method_text(rule->'referenceId',256)
   or not private.study_method_text(rule->'version',128) or not private.study_method_uuid(rule->'evidenceId') then return false;end if;
 else return false;end if;
 if jsonb_typeof(p_config->'evidenceRefs') is distinct from 'array' then return false;end if;
 if jsonb_array_length(p_config->'evidenceRefs')>128 then return false;end if;
 for e in select * from jsonb_array_elements(p_config->'evidenceRefs') loop
  if not private.study_keys(e,array['requirementId','declaredKind','artifactRef']) or e->>'requirementId' !~ '^PEF-(0[1-9]|1[0-9]|20)$'
   or not private.study_method_text(e->'requirementId',6) or not private.study_method_text(e->'declaredKind',32) or e->>'declaredKind' not in('sourceRecord','applicabilityRecord','professionalRecord')
   or not private.study_method_artifact_valid(e->'artifactRef','methodEvidence','lca.study-method-evidence.v1') then return false;end if;
  k:=(e->>'requirementId')||':'||(e->'artifactRef'->>'id');if k=any(seen) then return false;end if;seen:=seen||k;
 end loop;return true;
exception when invalid_text_representation or numeric_value_out_of_range then return false;end$$;
create function private.study_method_config_hash(p_config jsonb) returns text language sql stable set search_path='' as $$select private.study_reporting_digest('study.method-assessment-config.v1',p_config)$$;
create table private.study_method_config(
 singleton boolean primary key default true check(singleton),revision bigint not null default 1 check(revision>0),
 execution_enabled boolean not null default false,report_enabled boolean not null default false,
 max_evidence_refs integer check(max_evidence_refs between 0 and 128),max_selected_factor_records integer check(max_selected_factor_records between 1 and 8192),qualification_evidence_ref text,
 check(not(execution_enabled or report_enabled) or(max_evidence_refs is not null and max_selected_factor_records is not null and qualification_evidence_ref is not null and coalesce(private.study_method_text(to_jsonb(qualification_evidence_ref),2048),false)))
);
insert into private.study_method_config(singleton) values(true);
create table private.study_method_evidence(
 id uuid primary key,study_id uuid not null references private.studies(id),requirement_id text not null check(requirement_id ~ '^PEF-(0[1-9]|1[0-9]|20)$'),
 declared_kind text not null check(declared_kind in('sourceRecord','applicabilityRecord','professionalRecord')),artifact_id uuid not null,
 recorded_by uuid not null references auth.users(id),recorded_client_id text,recorded_at timestamptz not null default clock_timestamp(),
 unique(study_id,id),unique(study_id,artifact_id),foreign key(study_id,artifact_id) references private.study_artifacts(study_id,id)
);
create index study_method_evidence_actor_idx on private.study_method_evidence(recorded_by);
create trigger study_method_evidence_immutable before update or delete on private.study_method_evidence for each row execute function private.study_report_immutable();
create table private.study_method_evidence_intents(
 id uuid primary key default gen_random_uuid(),study_id uuid not null references private.studies(id),actor_id uuid not null references auth.users(id),client_id text,
 request jsonb not null,evidence_id uuid not null,artifact_id uuid not null,grant_epoch bigint not null,config_revision bigint not null,
 created_at timestamptz not null default clock_timestamp(),expires_at timestamptz not null default clock_timestamp()+interval '2 minutes',response jsonb
);
create index study_method_evidence_intent_study_idx on private.study_method_evidence_intents(study_id);
create index study_method_evidence_intent_actor_idx on private.study_method_evidence_intents(actor_id,expires_at);
create table private.study_method_assessments(
 id uuid primary key,study_id uuid not null references private.studies(id),profile_id text not null check(profile_id='lca.study-method-pef-2021-ef31-cement-intermediate.v1'),
 config jsonb not null check(private.study_method_config_valid(config)),config_hash text not null check(config_hash ~ '^[0-9a-f]{64}$'),
 baseline_run_id uuid not null,source_snapshot_id uuid not null,job_id uuid not null unique references private.worker_jobs(id),requested_by uuid not null references auth.users(id),requested_client_id text,
 admitted_max_evidence_refs integer not null check(admitted_max_evidence_refs between 0 and 128),admitted_max_selected_factor_records integer not null check(admitted_max_selected_factor_records between 1 and 8192),
 facts_artifact_id uuid,selected_factor_record_count integer check(selected_factor_record_count between 0 and admitted_max_selected_factor_records),unique(study_id,id),
 foreign key(study_id,baseline_run_id) references private.study_runs(study_id,id),foreign key(study_id,source_snapshot_id) references private.study_source_snapshots(study_id,id),foreign key(study_id,facts_artifact_id) references private.study_artifacts(study_id,id),
 check(config_hash=private.study_method_config_hash(config)),check(config->>'baselineRunId'=baseline_run_id::text),check((facts_artifact_id is null)=(selected_factor_record_count is null))
);
create index study_method_assessment_actor_idx on private.study_method_assessments(requested_by);
create index study_method_assessment_baseline_idx on private.study_method_assessments(study_id,baseline_run_id);
create index study_method_assessment_source_idx on private.study_method_assessments(study_id,source_snapshot_id);
create index study_method_assessment_facts_idx on private.study_method_assessments(study_id,facts_artifact_id);
create function private.study_method_immutable() returns trigger language plpgsql set search_path='' as $$begin
 if tg_op='DELETE' or(to_jsonb(old)-'facts_artifact_id'-'selected_factor_record_count') is distinct from(to_jsonb(new)-'facts_artifact_id'-'selected_factor_record_count')
 or old.facts_artifact_id is not null or new.facts_artifact_id is null or new.selected_factor_record_count is null then raise exception 'FROZEN_REVISION';end if;return new;end$$;
create trigger study_method_assessment_immutable before update or delete on private.study_method_assessments for each row execute function private.study_method_immutable();
insert into private.worker_job_kinds(job_kind,worker_runtime,worker_queue,default_visibility,payload_schema_version,result_schema_version,user_visible,description)
 values('study.method_assessment','calculator','solver','user','study.method_assessment.request.v1','lca.study-job-receipt.v1',false,'V6 source-bound method assessment; no professional approval');
create function private.study_method_record(p_id uuid) returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('assessmentId',a.id,'studyId',a.study_id,'profileId',a.profile_id,'config',a.config,'configHash',a.config_hash,
 'execution',jsonb_build_object('jobId',a.job_id,'status',j.status),'factsRef',case when j.status='completed' then f.ref else null end)
 from private.study_method_assessments a join private.worker_jobs j on j.id=a.job_id left join private.study_artifacts f on f.id=a.facts_artifact_id where a.id=p_id$$;
create function private.study_method_evidence_record(p_id uuid) returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('schemaVersion','lca.study-method-evidence-record.v1','evidenceId',e.id,'studyId',e.study_id,'requirementId',e.requirement_id,'declaredKind',e.declared_kind,
 'artifactRef',a.ref,'recordedAt',e.recorded_at,'status','recorded_unverified') from private.study_method_evidence e join private.study_artifacts a on a.study_id=e.study_id and a.id=e.artifact_id where e.id=p_id$$;
create function private.study_method_evidence_refs(p_study uuid,p_config jsonb,p_actor uuid,p_client text) returns void
language plpgsql security definer set search_path='' as $$declare r jsonb;e private.study_method_evidence%rowtype;begin
 perform private.study_authorize(p_study,p_actor,p_client,'read');
 for r in select * from jsonb_array_elements(p_config->'evidenceRefs') loop
  select * into e from private.study_method_evidence where study_id=p_study and artifact_id=(r->'artifactRef'->>'id')::uuid;
  perform private.study_require(found and e.requirement_id=r->>'requirementId' and e.declared_kind=r->>'declaredKind'
   and exists(select 1 from private.study_artifacts where study_id=p_study and id=e.artifact_id and ref=r->'artifactRef'),'REFERENCE_MISMATCH');
 end loop;
 if p_config->'declarations'->'categoryRule'->>'kind'='commissionDeveloped' then
  select * into e from private.study_method_evidence where study_id=p_study and id=(p_config->'declarations'->'categoryRule'->>'evidenceId')::uuid;
  perform private.study_require(found and e.requirement_id='PEF-01' and e.declared_kind='applicabilityRecord' and exists(select 1 from jsonb_array_elements(p_config->'evidenceRefs') declared(ref) where declared.ref->'artifactRef'->>'id'=e.artifact_id::text),'REFERENCE_MISMATCH');
 end if;
end$$;
create function private.study_method_envelope(p_request jsonb,p_write boolean) returns void
language plpgsql set search_path='' as $$declare field text;value jsonb;entry jsonb;begin
 perform private.study_require(auth.uid() is not null and not coalesce(util.is_service_request(),false),'AUTH_REQUIRED');
 perform private.study_require(jsonb_typeof(p_request)='object' and p_request->>'schemaVersion'='lca.study-api.v6' and octet_length(p_request::text)<=262144
 and private.study_text(p_request->'requestId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');
 if p_write then perform private.study_require(private.study_text(p_request->'idempotencyKey',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');end if;
 foreach field in array array['target','resource','artifactRef'] loop
  if p_request ? field then perform private.study_require(jsonb_typeof(p_request->field)='object' and private.study_method_uuid(p_request->field->'id'),'INVALID_REQUEST');end if;
 end loop;
 foreach field in array array['studyId','assessmentId','evidenceId','baselineRunId','reportRevisionId','parentReportRevisionId','cursor'] loop
  if not p_request ? field then continue;end if;value:=p_request->field;
  if value='null'::jsonb and field in('parentReportRevisionId','cursor') then continue;end if;
  perform private.study_require(private.study_method_uuid(value),'INVALID_REQUEST');
 end loop;
 foreach field in array array['runIds','methodAssessmentIds'] loop
  if not p_request ? field then continue;end if;
  perform private.study_require(jsonb_typeof(p_request->field)='array','INVALID_REQUEST');
  perform private.study_require(jsonb_array_length(p_request->field)<=1,'INVALID_REQUEST');
  for entry in select * from jsonb_array_elements(p_request->field) loop perform private.study_require(private.study_method_uuid(entry),'INVALID_REQUEST');end loop;
 end loop;
end$$;
create function private.study_method_lock_job(p_study uuid,p_job uuid,p_token uuid,p_assessment uuid) returns void
language plpgsql security definer set search_path='' as $$begin
 perform private.study_lock_job(p_study,p_job,p_token,'study.method_assessment','assessmentId',p_assessment);
 perform private.study_require(exists(select 1 from private.worker_jobs j join private.study_method_assessments a on a.job_id=j.id
 where a.id=p_assessment and a.study_id=p_study and j.id=p_job and j.subject_type='study' and j.subject_id=p_assessment and j.worker_queue='solver'
 and j.payload_schema_version='study.method_assessment.request.v1' and j.requested_by=a.requested_by
 and j.payload_json=jsonb_build_object('schemaVersion','study.method_assessment.request.v1','studyId',p_study,'assessmentId',p_assessment)),'REFERENCE_MISMATCH');end$$;
create function private.study_method_request(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' set statement_timeout='15s' as $$
declare sid uuid:=(p_request->>'studyId')::uuid;actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');
 req jsonb:=(p_request-'schemaVersion'-'requestId'-'idempotencyKey')||jsonb_build_object('_verifiedClientId',client);
 previous private.study_command_receipts%rowtype;cfg private.study_method_config%rowtype;s private.studies%rowtype;aid uuid:=gen_random_uuid();job uuid;snapshot uuid;result jsonb;old_role text;old_context text;
begin
 perform private.study_method_envelope(p_request,true);
 perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','idempotencyKey','operation','studyId','profileId','config','configHash'])
 and p_request->>'operation'='method.assessment.request' and private.study_method_config_valid(p_request->'config'),'INVALID_REQUEST');
 perform private.study_require(p_request->>'profileId'='lca.study-method-pef-2021-ef31-cement-intermediate.v1'
 and p_request->>'configHash'=private.study_method_config_hash(p_request->'config'),'REFERENCE_MISMATCH');
 perform private.study_authorize(sid,actor,client,'write');snapshot:=private.study_advanced_rights(sid,(p_request->'config'->>'baselineRunId')::uuid,actor,client);
 perform private.study_method_evidence_refs(sid,p_request->'config',actor,client);
 select * into previous from private.study_command_receipts where actor_id=actor and operation='methodAssessment.request' and scope=sid::text and idempotency_key=p_request->>'idempotencyKey';
 if found then perform private.study_require(previous.request=req,'IDEMPOTENCY_CONFLICT');return previous.response;end if;
 perform private.study_analysis_require_current(sid,jsonb_build_object('runIds',jsonb_build_array(p_request->'config'->'baselineRunId')));
 select * into s from private.studies where id=sid;perform private.study_require(s.status='active','FROZEN_REVISION');select * into cfg from private.study_method_config where singleton for share;
 perform private.study_require(cfg.execution_enabled and jsonb_array_length(p_request->'config'->'evidenceRefs')<=cfg.max_evidence_refs,'CAPABILITY_UNAVAILABLE');
 old_role:=current_setting('request.jwt.claim.role',true);old_context:=current_setting('app.study.task_context',true);
 perform set_config('request.jwt.claim.role','service_role',true);perform set_config('app.study.task_context','enqueue',true);
 result:=private.worker_enqueue_job('study.method_assessment',jsonb_build_object('schemaVersion','study.method_assessment.request.v1','studyId',sid,'assessmentId',aid),
 'study.method_assessment.request.v1','study',aid,null,actor,'user',s.team_id,actor::text||':'||sid::text||':study.method_assessment:'||(p_request->>'idempotencyKey'),
 private.study_content_hash('lca.study-job-request.v1',req),null,0,null,null,'user');
 perform set_config('request.jwt.claim.role',coalesce(old_role,''),true);perform set_config('app.study.task_context',coalesce(old_context,''),true);
 perform private.study_require((result->>'ok')::boolean,'CAPABILITY_UNAVAILABLE');job:=(result->'data'->>'id')::uuid;
 insert into private.study_method_assessments(id,study_id,profile_id,config,config_hash,baseline_run_id,source_snapshot_id,job_id,requested_by,requested_client_id,admitted_max_evidence_refs,admitted_max_selected_factor_records)
 values(aid,sid,p_request->>'profileId',p_request->'config',p_request->>'configHash',(p_request->'config'->>'baselineRunId')::uuid,snapshot,job,actor,client,cfg.max_evidence_refs,cfg.max_selected_factor_records);
 result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','methodAssessment','value',private.study_method_record(aid)));
 insert into private.study_command_receipts values(actor,'methodAssessment.request',sid::text,p_request->>'idempotencyKey',req,result,clock_timestamp());return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range or not_null_violation or check_violation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');end$$;
create function api.svc_study_method_assessment_read_input_v1(p_assessment_id uuid,p_job_id uuid,p_lease_token uuid) returns jsonb
language plpgsql security definer set search_path='' as $$declare a private.study_method_assessments%rowtype;snapshot uuid;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');select * into a from private.study_method_assessments where id=p_assessment_id;
 perform private.study_require(found and a.job_id=p_job_id,'REFERENCE_MISMATCH');perform private.study_authorize(a.study_id,a.requested_by,a.requested_client_id,'write');
 snapshot:=private.study_advanced_rights(a.study_id,a.baseline_run_id,a.requested_by,a.requested_client_id);perform private.study_require(snapshot=a.source_snapshot_id,'REFERENCE_MISMATCH');
 perform private.study_method_evidence_refs(a.study_id,a.config,a.requested_by,a.requested_client_id);
 perform private.study_analysis_require_current(a.study_id,jsonb_build_object('runIds',jsonb_build_array(a.baseline_run_id)));perform private.study_method_lock_job(a.study_id,p_job_id,p_lease_token,a.id);
 return jsonb_build_object('ok',true,'data',jsonb_build_object('schemaVersion','lca.study-method-job-context.v1',
 'input',jsonb_build_object('schemaVersion','lca.study-method-assessment-input.v1','assessment',private.study_method_record(a.id)-'factsRef',
 'baseline',private.study_advanced_baseline(a.study_id,a.baseline_run_id),'sourceSnapshot',private.study_record('modelSourceSnapshot',snapshot),
 'sourceArtifact',private.study_private_artifact(a.study_id,(select artifact_id from private.study_source_snapshots where id=snapshot))),
 'budget',jsonb_build_object('maxSelectedFactorRecords',a.admitted_max_selected_factor_records,'maxFactsBytes',4194304)));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);end$$;
create function api.svc_study_method_assessment_complete_v1(p_assessment_id uuid,p_job_id uuid,p_lease_token uuid,p_completion jsonb,p_idempotency_key text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a private.study_method_assessments%rowtype;previous private.study_service_receipts%rowtype;request jsonb;result jsonb;artifact uuid;old_context text;snapshot uuid;selected_count integer;
begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');perform private.study_require(private.study_text(to_jsonb(p_idempotency_key),128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');
 select * into a from private.study_method_assessments where id=p_assessment_id;perform private.study_require(found and a.job_id=p_job_id,'REFERENCE_MISMATCH');
 perform private.study_authorize(a.study_id,a.requested_by,a.requested_client_id,'write');snapshot:=private.study_advanced_rights(a.study_id,a.baseline_run_id,a.requested_by,a.requested_client_id);
 perform private.study_method_evidence_refs(a.study_id,a.config,a.requested_by,a.requested_client_id);
 perform private.study_require(snapshot=a.source_snapshot_id,'REFERENCE_MISMATCH');request:=jsonb_build_object('id',p_assessment_id,'jobId',p_job_id,'leaseToken',p_lease_token,'completion',p_completion);
 select * into previous from private.study_service_receipts where operation='methodAssessment' and study_id=a.study_id and idempotency_key=p_idempotency_key;
 if found then perform private.study_require(previous.request=request and previous.job_id=p_job_id and previous.lease_token=p_lease_token,'IDEMPOTENCY_CONFLICT');return previous.response;end if;
 perform private.study_analysis_require_current(a.study_id,jsonb_build_object('runIds',jsonb_build_array(a.baseline_run_id)));perform private.study_method_lock_job(a.study_id,p_job_id,p_lease_token,a.id);
 select * into a from private.study_method_assessments where id=p_assessment_id for update;
 perform private.study_require(a.facts_artifact_id is null and private.study_keys(p_completion,array['profileId','configHash','selectedFactorRecordCount','factsRef','storageBucket','storageObjectPath'])
 and p_completion->>'profileId'=a.profile_id and p_completion->>'configHash'=a.config_hash
 and private.study_method_artifact_valid(p_completion->'factsRef','methodAssessmentFacts','lca.study-method-assessment-facts.v1')
 and private.study_method_uint(p_completion->'selectedFactorRecordCount',0,a.admitted_max_selected_factor_records),'REFERENCE_MISMATCH');
 selected_count:=(p_completion->>'selectedFactorRecordCount')::integer;
 artifact:=private.study_store_artifact(a.study_id,p_completion->'factsRef',p_completion->>'storageBucket',p_completion->>'storageObjectPath','methodAssessmentFacts');
 update private.study_method_assessments set facts_artifact_id=artifact,selected_factor_record_count=selected_count where id=a.id;
 old_context:=current_setting('app.study.task_context',true);perform set_config('app.study.task_context','complete',true);
 result:=private.worker_record_job_result(p_job_id,p_lease_token,'completed',jsonb_build_object('schemaVersion','lca.study-job-receipt.v1','studyId',a.study_id,'resourceType','methodAssessment','resourceId',a.id),'lca.study-job-receipt.v1',p_completion->'factsRef');
 perform set_config('app.study.task_context',coalesce(old_context,''),true);perform private.study_require((result->>'ok')::boolean,'FORBIDDEN');
 result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','methodAssessment','value',private.study_method_record(a.id)));
 insert into private.study_service_receipts values('methodAssessment',a.study_id,p_idempotency_key,p_job_id,p_lease_token,request,result);return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or numeric_value_out_of_range or not_null_violation or check_violation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');end$$;
create function api.svc_study_method_configure_v1(p_expected_revision bigint,p_configuration jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$declare cfg private.study_method_config%rowtype;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 perform private.study_require(private.study_keys(p_configuration,array['executionEnabled','reportEnabled','maxEvidenceRefs','maxSelectedFactorRecords','qualificationEvidenceRef'])
 and jsonb_typeof(p_configuration->'executionEnabled')='boolean' and jsonb_typeof(p_configuration->'reportEnabled')='boolean'
 and(p_configuration->'maxEvidenceRefs'='null'::jsonb or(jsonb_typeof(p_configuration->'maxEvidenceRefs')='number' and(p_configuration->>'maxEvidenceRefs')::numeric between 0 and 128 and trunc((p_configuration->>'maxEvidenceRefs')::numeric)=(p_configuration->>'maxEvidenceRefs')::numeric))
 and(p_configuration->'maxSelectedFactorRecords'='null'::jsonb or(jsonb_typeof(p_configuration->'maxSelectedFactorRecords')='number' and(p_configuration->>'maxSelectedFactorRecords')::numeric between 1 and 8192 and trunc((p_configuration->>'maxSelectedFactorRecords')::numeric)=(p_configuration->>'maxSelectedFactorRecords')::numeric))
 and(p_configuration->'qualificationEvidenceRef'='null'::jsonb or private.study_method_text(p_configuration->'qualificationEvidenceRef',2048)),'INVALID_REQUEST');
 select * into cfg from private.study_method_config where singleton for update;perform private.study_require(cfg.revision=p_expected_revision,'REVISION_CONFLICT');
 update private.study_method_config set revision=revision+1,execution_enabled=(p_configuration->>'executionEnabled')::boolean,report_enabled=(p_configuration->>'reportEnabled')::boolean,
 max_evidence_refs=(p_configuration->>'maxEvidenceRefs')::integer,max_selected_factor_records=(p_configuration->>'maxSelectedFactorRecords')::integer,qualification_evidence_ref=p_configuration->>'qualificationEvidenceRef' where singleton;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('revision',cfg.revision+1));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or numeric_value_out_of_range or not_null_violation or check_violation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');end$$;


create function private.study_method_evidence_plain(p_value jsonb,p_max integer) returns boolean
language plpgsql immutable set search_path='' as $$declare v text;begin
 if jsonb_typeof(p_value) is distinct from 'string' then return false;end if;v:=p_value#>>'{}';
 return length(v) between 1 and p_max and v !~ U&'[\0001-\001F\007F-\009F]' and v !~ '[<>]'
 and btrim(v,U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000')<>'';
end$$;
create function private.study_method_evidence_body_valid(p_value jsonb) returns boolean language plpgsql stable set search_path='' as $$declare c jsonb;seen jsonb:='[]'::jsonb;begin
 if not private.study_keys(p_value,array['schemaVersion','requirementId','declaredKind','title','statement','citations'])
 or p_value->>'schemaVersion' is distinct from 'lca.study-method-evidence.v1' or p_value->>'requirementId' !~ '^PEF-(0[1-9]|1[0-9]|20)$'
 or not private.study_method_text(p_value->'requirementId',6) or not private.study_method_text(p_value->'declaredKind',32) or p_value->>'declaredKind' not in('sourceRecord','applicabilityRecord','professionalRecord')
 or not private.study_method_evidence_plain(p_value->'title',256) or not private.study_method_evidence_plain(p_value->'statement',8192)
 or jsonb_typeof(p_value->'citations') is distinct from 'array' then return false;end if;
 if jsonb_array_length(p_value->'citations')>32 or octet_length(private.study_reporting_canonical(p_value))>65536 then return false;end if;
 for c in select * from jsonb_array_elements(p_value->'citations') loop
  if not private.study_keys(c,array['kind','identity','version','contentHash','locator'])
  or not private.study_method_text(c->'kind',32) or c->>'kind' not in('normativeSource','datasetRevision','document','professionalRecord','otherDeclaredSource')
  or not private.study_method_evidence_plain(c->'identity',256) or not private.study_method_evidence_plain(c->'version',128)
  or not private.study_method_evidence_plain(c->'locator',512) or(c->'contentHash'<>'null'::jsonb and not private.study_text(c->'contentHash',64,'^[0-9a-f]{64}$'))
  or seen @> jsonb_build_array(c) then return false;end if;
  seen:=seen||jsonb_build_array(c);
 end loop;return true;
end$$;
create function private.study_method_evidence_intent_check(p_id uuid) returns private.study_method_evidence_intents
language plpgsql security definer set search_path='' as $$declare i private.study_method_evidence_intents%rowtype;cfg private.study_method_config%rowtype;begin
 select * into i from private.study_method_evidence_intents where id=p_id;perform private.study_require(found,'CAPABILITY_UNAVAILABLE');
 perform private.study_authorize(i.study_id,i.actor_id,i.client_id,'write');
 select * into i from private.study_method_evidence_intents where id=p_id;
 if i.response is not null then return i;end if;
 select * into cfg from private.study_method_config where singleton for share;
 perform private.study_require(i.expires_at>clock_timestamp() and cfg.execution_enabled and cfg.revision=i.config_revision,'CAPABILITY_UNAVAILABLE');
 perform private.study_require(i.grant_epoch=(select grant_epoch from private.studies where id=i.study_id),'FORBIDDEN');
 perform private.study_require((select status='active' from private.studies where id=i.study_id),'FROZEN_REVISION');return i;
end$$;
create function private.study_method_evidence_create(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' set statement_timeout='15s' as $$
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
create function api.svc_study_method_evidence_intent_resolve_v1(p_intent_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$declare i private.study_method_evidence_intents%rowtype;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');i:=private.study_method_evidence_intent_check(p_intent_id);
 if i.response is not null then return i.response;end if;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('kind','methodEvidenceCommandContext','intentId',i.id,'expiresAt',i.expires_at,
 'request',i.request,'studyId',i.study_id,'actorId',i.actor_id,'clientId',i.client_id,'evidenceId',i.evidence_id,'artifactId',i.artifact_id,'recordedAt',i.created_at,
 'contentHash',private.study_reporting_digest(null,i.request->'content'),'byteSize',octet_length(private.study_reporting_canonical(i.request->'content'))));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);end$$;
create function api.svc_study_method_evidence_intent_consume_v1(p_intent_id uuid,p_completion jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$declare i private.study_method_evidence_intents%rowtype;a uuid;result jsonb;ref jsonb;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');i:=private.study_method_evidence_intent_check(p_intent_id);
 select * into i from private.study_method_evidence_intents where id=p_intent_id for update;
 if i.response is not null then
  perform private.study_require(private.study_keys(p_completion,array['artifact']) and p_completion->'artifact'->'artifactRef'=i.response->'data'->'value'->'artifactRef'
   and exists(select 1 from private.study_artifacts where study_id=i.study_id and id=i.artifact_id and bucket=p_completion->'artifact'->>'storageBucket' and object_path=p_completion->'artifact'->>'storageObjectPath'),'IDEMPOTENCY_CONFLICT');
  return i.response;
 end if;
 ref:=p_completion->'artifact'->'artifactRef';
 perform private.study_require(private.study_keys(p_completion,array['artifact']) and private.study_keys(p_completion->'artifact',array['artifactRef','storageBucket','storageObjectPath'])
 and private.study_method_artifact_valid(ref,'methodEvidence','lca.study-method-evidence.v1',65536) and ref->>'id'=i.artifact_id::text
 and ref->>'contentHash'=private.study_reporting_digest(null,i.request->'content')
 and(ref->>'byteSize')::numeric=octet_length(private.study_reporting_canonical(i.request->'content')),'REFERENCE_MISMATCH');
 a:=private.study_store_artifact(i.study_id,ref,p_completion->'artifact'->>'storageBucket',p_completion->'artifact'->>'storageObjectPath','methodEvidence');
 insert into private.study_method_evidence(id,study_id,requirement_id,declared_kind,artifact_id,recorded_by,recorded_client_id,recorded_at)
 values(i.evidence_id,i.study_id,i.request->'content'->>'requirementId',i.request->'content'->>'declaredKind',a,i.actor_id,i.client_id,i.created_at);
 result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','methodEvidence','value',private.study_method_evidence_record(i.evidence_id)));
 update private.study_method_evidence_intents set response=result where id=i.id;
 update private.study_command_receipts set response=result where actor_id=i.actor_id and operation='method.evidence.create' and scope=i.study_id::text and idempotency_key=i.request->>'idempotencyKey';return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or numeric_value_out_of_range or not_null_violation or check_violation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');end$$;
create function api.svc_study_method_evidence_intent_reconcile_v1(p_intent_id uuid,p_artifact_id uuid,p_content_hash text) returns jsonb
language plpgsql security definer set search_path='' as $$declare i private.study_method_evidence_intents%rowtype;state text;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');select * into i from private.study_method_evidence_intents where id=p_intent_id;
 perform private.study_require(found and i.artifact_id=p_artifact_id and p_content_hash=private.study_reporting_digest(null,i.request->'content'),'REFERENCE_MISMATCH');
 perform 1 from private.studies where id=i.study_id for update;select * into i from private.study_method_evidence_intents where id=p_intent_id for update;
 if i.response is not null then state:='committed';
 elsif exists(select 1 from private.study_artifacts where id=p_artifact_id) then state:='referenced';
 elsif i.expires_at<=clock_timestamp() then state:='expired_unreferenced';else state:='pending';end if;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('schemaVersion','lca.study-method-evidence-reconcile.v1','intentId',i.id,'state',state,'response',i.response,'deletionPermitted',false));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);end$$;


create or replace function "private"."study_method_task"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare sid uuid:=(p_request->>'studyId')::uuid; actor uuid:=auth.uid(); client text:=nullif(auth.jwt()->>'client_id','');
 op text:=p_request->>'operation'; a private.study_method_assessments%rowtype; j private.worker_jobs%rowtype; result jsonb;
 old_role text; old_context text; previous private.study_command_receipts%rowtype; req jsonb:=(p_request-'schemaVersion'-'requestId'-'idempotencyKey')||jsonb_build_object('_verifiedClientId',client);
begin
 perform private.study_method_envelope(p_request,op='task.cancel');
 perform private.study_require(private.study_keys(p_request->'resource',array['type','id']) and p_request->'resource'->>'type'='methodAssessment','INVALID_REQUEST');
 perform private.study_authorize(sid,actor,client,case when op='task.cancel' then 'write' else 'read' end);
 select * into a from private.study_method_assessments where study_id=sid and id=(p_request->'resource'->>'id')::uuid;
 perform private.study_require(found,'FORBIDDEN');
 -- Minimal status/cancellation stays available after source withdrawal and
 -- admission shutdown. No source, result, payload or raw diagnostic is projected.
 perform private.study_require(exists(select 1 from private.worker_jobs bound_job where bound_job.id=a.job_id
 and bound_job.job_kind='study.method_assessment' and bound_job.worker_runtime='calculator' and bound_job.worker_queue='solver'
 and bound_job.subject_type='study' and bound_job.subject_id=a.id and bound_job.requested_by=a.requested_by
 and bound_job.payload_schema_version='study.method_assessment.request.v1'
 and bound_job.payload_json=jsonb_build_object('schemaVersion','study.method_assessment.request.v1','studyId',sid,'assessmentId',a.id)),'REFERENCE_MISMATCH');
 if op='task.cancel' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','idempotencyKey','studyId','resource','reason']) and private.study_text(p_request->'reason',512),'INVALID_REQUEST');
  select * into previous from private.study_command_receipts where actor_id=actor and operation='method.'||op and scope=sid::text and idempotency_key=p_request->>'idempotencyKey';
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
 if op='task.cancel' then insert into private.study_command_receipts values(actor,'method.'||op,sid::text,p_request->>'idempotencyKey',req,result,clock_timestamp()); end if;
 return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
end $$;


create function api.svc_study_method_assessment_fail_v1(p_resource_type text,p_resource_id uuid,p_job_id uuid,p_lease_token uuid,p_error_code text,p_idempotency_key text) returns jsonb
language plpgsql security definer set search_path='' as $$declare a private.study_method_assessments%rowtype;request jsonb;receipt private.study_service_receipts%rowtype;result jsonb;old_context text;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 perform private.study_require(p_resource_type='methodAssessment' and private.study_text(to_jsonb(p_idempotency_key),128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$')
 and p_error_code=any(array['source_invalid','boundary_undeclared','normalization_underflow','normalization_overflow','numeric_invalid','resource_limit','model_not_solvable','native_execution_failed','job_timeout','job_lease_lost','runtime_unavailable','runtime_failed']),'INVALID_REQUEST');
 select * into a from private.study_method_assessments where id=p_resource_id;perform private.study_require(found and a.job_id=p_job_id,'REFERENCE_MISMATCH');
 perform 1 from private.studies where id=a.study_id for update;
 request:=jsonb_build_object('id',p_resource_id,'jobId',p_job_id,'leaseToken',p_lease_token,'errorCode',p_error_code);
 select * into receipt from private.study_service_receipts where operation='methodAssessment'and study_id=a.study_id and idempotency_key=p_idempotency_key;
 if found then perform private.study_require(receipt.request=request and receipt.job_id=p_job_id and receipt.lease_token=p_lease_token,'IDEMPOTENCY_CONFLICT');return receipt.response;end if;
 perform private.study_method_lock_job(a.study_id,p_job_id,p_lease_token,a.id);old_context:=current_setting('app.study.task_context',true);perform set_config('app.study.task_context','complete',true);
 result:=private.worker_record_job_result(p_job_id,p_lease_token,'failed',jsonb_build_object('schemaVersion','lca.study-job-receipt.v1','studyId',a.study_id,'resourceType','methodAssessment','resourceId',a.id),
 'lca.study-job-receipt.v1',null,null,p_error_code,'Study task failed',null,null,null,false);
 perform set_config('app.study.task_context',coalesce(old_context,''),true);perform private.study_require((result->>'ok')::boolean,'FORBIDDEN');
 result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','methodAssessment','value',private.study_method_record(a.id)));
 insert into private.study_service_receipts values('methodAssessment',a.study_id,p_idempotency_key,p_job_id,p_lease_token,request,result);return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);end$$;
create function api.svc_study_method_assessment_reconcile_v1(p_resource_type text,p_resource_id uuid,p_job_id uuid,p_lease_token uuid,p_idempotency_key text,p_artifact_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$declare a private.study_method_assessments%rowtype;j private.worker_jobs%rowtype;receipt private.study_service_receipts%rowtype;state text;resource jsonb;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 perform private.study_require(p_resource_type='methodAssessment' and private.study_text(to_jsonb(p_idempotency_key),128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');
 select * into a from private.study_method_assessments where id=p_resource_id;perform private.study_require(found and a.job_id=p_job_id,'REFERENCE_MISMATCH');
 perform 1 from private.studies where id=a.study_id for update;select * into j from private.worker_jobs where id=p_job_id for update;
 perform private.study_require(j.job_kind='study.method_assessment'and j.worker_runtime='calculator'and j.worker_queue='solver'and j.subject_type='study'and j.subject_id=a.id
 and j.requested_by=a.requested_by and j.payload_schema_version='study.method_assessment.request.v1'
 and j.payload_json=jsonb_build_object('schemaVersion','study.method_assessment.request.v1','studyId',a.study_id,'assessmentId',a.id),'REFERENCE_MISMATCH');
 perform private.study_require(p_lease_token is not null and(j.lease_token=p_lease_token or exists(select 1 from private.worker_job_events where job_id=p_job_id and lease_token=p_lease_token)),'FORBIDDEN');
 select * into receipt from private.study_service_receipts where operation='methodAssessment'and study_id=a.study_id and idempotency_key=p_idempotency_key;
 if found then
  perform private.study_require(receipt.job_id=p_job_id and receipt.lease_token=p_lease_token and receipt.request->>'id'=a.id::text,'IDEMPOTENCY_CONFLICT');state:='committed';resource:=receipt.response->'data';
 elsif p_artifact_id is not null and exists(select 1 from private.study_artifacts where id=p_artifact_id) then state:='referenced';
 elsif j.status in('completed','failed','cancelled','blocked')and j.lease_token is null then state:='unreferenced';else state:='pending';end if;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('state',state,'resource',resource,'jobStatus',j.status));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);end$$;


alter table private.study_report_revisions drop constraint study_report_revisions_template_id_check;
alter table private.study_report_revisions add constraint study_report_revisions_template_id_check check(template_id in('lca.study-report.v1','lca.study-report.v2','lca.study-method-report.v1'));
alter table private.study_report_revisions add column method_assessment_ids jsonb not null default '[]'::jsonb;
alter table private.study_report_revisions add constraint study_method_report_selection_check check(
 case when template_id='lca.study-method-report.v1' then private.study_report_ids(run_ids,1,1) and analysis_ids='[]'::jsonb and private.study_report_ids(method_assessment_ids,1,1)
 else method_assessment_ids='[]'::jsonb end);
alter table private.study_report_intents drop constraint study_report_intents_family_check;
alter table private.study_report_intents add constraint study_report_intents_family_check check(family in('legacy','advanced','method'));
create table private.study_report_method_assessments(
 study_id uuid not null,report_id uuid primary key,assessment_id uuid not null,
 foreign key(study_id,report_id) references private.study_report_revisions(study_id,id),foreign key(study_id,assessment_id) references private.study_method_assessments(study_id,id)
);
create index study_report_method_study_idx on private.study_report_method_assessments(study_id,report_id);
create index study_report_method_assessment_idx on private.study_report_method_assessments(study_id,assessment_id);
create trigger study_report_method_immutable before update or delete on private.study_report_method_assessments for each row execute function private.study_report_immutable();
create function private.study_method_report_record(p_id uuid) returns jsonb language sql security definer set search_path='' as $$
 select(private.study_report_record(r.id)-'analysisIds')||jsonb_build_object('methodAssessmentIds',r.method_assessment_ids)
 from private.study_report_revisions r where r.id=p_id and r.template_id='lca.study-method-report.v1'$$;
create function private.study_method_report_rights(p_study uuid,p_runs jsonb,p_assessments jsonb,p_actor uuid,p_client text) returns jsonb
language plpgsql security definer set search_path='' as $$declare a private.study_method_assessments%rowtype;begin
 perform private.study_authorize(p_study,p_actor,p_client,'read');perform private.study_require(private.study_report_ids(p_runs,1,1) and private.study_report_ids(p_assessments,1,1),'INVALID_REQUEST');
 select * into a from private.study_method_assessments where study_id=p_study and id=(p_assessments->>0)::uuid;
 perform private.study_require(found and a.baseline_run_id::text=p_runs->>0 and a.facts_artifact_id is not null and exists(select 1 from private.worker_jobs where id=a.job_id and status='completed'),'REFERENCE_MISMATCH');
 perform private.study_require(a.source_snapshot_id=private.study_advanced_rights(p_study,a.baseline_run_id,p_actor,p_client),'REFERENCE_MISMATCH');
 perform private.study_method_evidence_refs(p_study,a.config,p_actor,p_client);
 return jsonb_build_array((select ref from private.study_artifacts where study_id=p_study and id=a.facts_artifact_id));
end$$;
create function private.study_method_report_artifact_authorize(p_study uuid,p_ref jsonb,p_actor uuid,p_client text) returns void
language plpgsql security definer set search_path='' as $$declare r private.study_report_revisions%rowtype;begin
 select * into r from private.study_report_revisions where study_id=p_study and template_id='lca.study-method-report.v1' and content_artifact_id=(p_ref->>'id')::uuid;
 perform private.study_require(found,'DISCLOSURE_DENIED');perform private.study_method_report_rights(p_study,r.run_ids,r.method_assessment_ids,p_actor,p_client);
end$$;
create function private.study_method_report_binding(p_study uuid,p_runs jsonb,p_assessments jsonb) returns text
language plpgsql security definer set search_path='' as $$declare a private.study_method_assessments%rowtype;r jsonb;p jsonb;source_ref jsonb;baseline jsonb;assessment jsonb;refs jsonb;begin
 perform private.study_require(private.study_report_ids(p_runs,1,1)and private.study_report_ids(p_assessments,1,1),'INVALID_REQUEST');
 select * into a from private.study_method_assessments where study_id=p_study and id=(p_assessments->>0)::uuid;
 perform private.study_require(found and a.baseline_run_id::text=p_runs->>0 and a.facts_artifact_id is not null,'REFERENCE_MISMATCH');
 r:=private.study_record('run',a.baseline_run_id);p:=private.study_record('modelPreparation',(r->>'modelPreparationId')::uuid);
 select ar.ref into source_ref from private.study_source_snapshots s join private.study_artifacts ar on ar.study_id=s.study_id and ar.id=s.artifact_id where s.study_id=p_study and s.id=a.source_snapshot_id;
 baseline:=jsonb_build_object('runId',r->'runId','studyId',r->'studyId','studyRevisionId',r->'studyRevisionId','scenarioRevisionId',r->'scenarioRevisionId',
 'effectiveModelRef',r->'effectiveModelRef','inputHash',r->'inputHash','profileId',r->'profileId','engineId',r->'engineId','calculationContractRef',r->'calculationContractRef',
 'resultRef',r->'resultRef','preparedArtifactRef',p->'inputArtifactRef','sourceSnapshotRef',source_ref);
 assessment:=jsonb_build_object('assessmentId',a.id,'profileId',a.profile_id,'configHash',a.config_hash,'moduleRef',a.config->'moduleRef');
 refs:=jsonb_build_array((select ref from private.study_artifacts where study_id=p_study and id=a.facts_artifact_id));
 return private.study_reporting_digest('lca.study-method-report-facts-binding.v1',jsonb_build_object('studyId',p_study,'runIds',p_runs,'methodAssessmentIds',p_assessments,'factsRefs',refs,'baseline',baseline,'assessment',assessment));
end$$;


create or replace function "private"."study_method_report_content_valid"("p_value" "jsonb") RETURNS boolean
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO ''
    AS $_$
declare c jsonb;r jsonb;section jsonb;typ text;idkey text;claimids jsonb;seen text[];v text;
begin
 if not private.study_keys(p_value,array['schemaVersion','title','claims','sections','tables','charts','additionalLimitations'])
 or p_value->>'schemaVersion' is distinct from 'lca.study-method-report-draft.v1' or not private.study_report_plain(p_value->'title',256)
 or jsonb_typeof(p_value->'claims') is distinct from 'array' then return false;end if;
 if jsonb_array_length(p_value->'claims') not between 1 and 256 then return false;end if;
 claimids:='[]';
 for c in select * from jsonb_array_elements(p_value->'claims') loop
  if not private.study_keys(c,array['claimId','bundleRef','factId','canonicalValue','unit','display'])
  or not private.study_text(c->'claimId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$') or not private.study_text(c->'factId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$')
  or not private.study_report_plain(c->'unit',128) or c->'display'<>'{"style":"exact"}'::jsonb
  or not private.study_keys(c->'bundleRef',array['type','id','contentHash','digestScope','byteSize','mediaType','schemaVersion'])
  or c->'bundleRef'->>'type' is distinct from 'methodAssessmentFacts' or c->'bundleRef'->>'schemaVersion' is distinct from 'lca.study-method-assessment-facts.v1'
  or c->'bundleRef'->>'mediaType' is distinct from 'application/json' then return false;end if;
  if c->'canonicalValue'<>'null'::jsonb then
   v:=c->>'canonicalValue';
   if not private.study_text(c->'canonicalValue',64,'^-?(0|[1-9][0-9]*)(\.[0-9]*[1-9])?(e-?[1-9][0-9]{0,2})?$')
   or (v ~ '^-?0(e.*)?$' and v<>'0') or (v like '%e%' and abs(split_part(v,'e',2)::integer)>324) then return false;end if;
  end if;
  claimids:=claimids||jsonb_build_array(c->'claimId');
 end loop;
 if not private.study_report_ids(claimids,1,256) then return false;end if;
 foreach typ in array array['sections','tables','charts'] loop
  if jsonb_typeof(p_value->typ) is distinct from 'array' then return false;end if;
  if jsonb_array_length(p_value->typ)>32 then return false;end if;
  idkey:=case typ when 'sections' then 'sectionId' when 'tables' then 'tableId' else 'chartId' end;seen:='{}'::text[];
  for r in select * from jsonb_array_elements(p_value->typ) loop
   if not private.study_keys(r,case when typ='sections' then array[idkey,'title','paragraphs','claimIds'] else array[idkey,'title','claimIds'] end)
   or not private.study_text(r->idkey,128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$') or (r->>idkey)=any(seen)
   or not private.study_report_plain(r->'title',256) or not private.study_report_ids(r->'claimIds',case when typ='sections' then 0 else 1 end,case when typ='charts' then 64 else 256 end)
   or not (r->'claimIds')<@claimids then return false;end if;seen:=seen||(r->>idkey);
   if typ='sections' then
    if jsonb_typeof(r->'paragraphs') is distinct from 'array' then return false;end if;
    if jsonb_array_length(r->'paragraphs')>32 then return false;end if;
    for section in select * from jsonb_array_elements(r->'paragraphs') loop if not private.study_report_plain(section,2048) then return false;end if;end loop;
   end if;
  end loop;
 end loop;
 if jsonb_typeof(p_value->'additionalLimitations') is distinct from 'array' then return false;end if;
 if jsonb_array_length(p_value->'additionalLimitations')>32 then return false;end if;
 for r in select * from jsonb_array_elements(p_value->'additionalLimitations') loop if not private.study_report_plain(r,2048) then return false;end if;end loop;
 return true;
exception when invalid_text_representation then return false;
end$_$;

create function private.study_method_report_validation_check(p_validation jsonb,p_report uuid,p_hash text,p_count integer,p_binding text,p_assessment uuid,p_config_hash text) returns void
language plpgsql set search_path='' as $$begin
 perform private.study_require(private.study_keys(p_validation,array['schemaVersion','profileId','reportRevisionId','contentHash','claimCount','factsBindingHash','methodAssessmentId','configHash','requirementCount','categoryCount','factCount'])
 and p_validation->>'schemaVersion'='lca.study-method-report-validation.v1'and p_validation->>'profileId'='lca.study-method-report-claims.v1'
 and p_validation->>'reportRevisionId'=p_report::text and p_validation->>'contentHash'=p_hash and private.study_method_uint(p_validation->'claimCount',1,256)and(p_validation->>'claimCount')::integer=p_count
 and p_validation->>'factsBindingHash'=p_binding and p_validation->>'methodAssessmentId'=p_assessment::text and p_validation->>'configHash'=p_config_hash
 and private.study_method_uint(p_validation->'requirementCount',20,20)and private.study_method_uint(p_validation->'categoryCount',25,25)and private.study_method_uint(p_validation->'factCount',58,58),'REFERENCE_MISMATCH');
end$$;

create or replace function "private"."study_method_report_command"("p_request" "jsonb") RETURNS "jsonb"
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

create or replace function "private"."study_method_report_intent_check"("p_id" "uuid") RETURNS "private"."study_report_intents"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare i private.study_report_intents%rowtype;r private.study_report_revisions%rowtype;cfg private.study_method_config%rowtype;refs jsonb;begin
 select * into i from private.study_report_intents where id=p_id;
 perform private.study_require(found and i.family='method','CAPABILITY_UNAVAILABLE');
 perform private.study_authorize(i.study_id,i.actor_id,i.client_id,case when i.operation='export.request' then 'read' else 'write' end);
 select * into i from private.study_report_intents where id=p_id;
 perform private.study_require((select grant_epoch from private.studies where id=i.study_id)=i.grant_epoch,'FORBIDDEN');
 if i.operation='report.create' then
  refs:=private.study_method_report_rights(i.study_id,i.request->'runIds',i.request->'methodAssessmentIds',i.actor_id,i.client_id);
 else
  select * into r from private.study_report_revisions where study_id=i.study_id and id=i.report_id;
  perform private.study_require(found,'REFERENCE_MISMATCH');
  refs:=private.study_method_report_rights(i.study_id,r.run_ids,r.method_assessment_ids,i.actor_id,i.client_id);
  perform private.study_require(refs=r.facts_refs,'REFERENCE_MISMATCH');
 end if;
 if i.response is not null then return i;end if;
 perform private.study_analysis_require_current(i.study_id,jsonb_build_object('runIds',case when i.operation='report.create' then i.request->'runIds' else r.run_ids end));
 perform private.study_require(i.expires_at>clock_timestamp(),'CAPABILITY_UNAVAILABLE');
 select * into cfg from private.study_method_config where singleton for share;
 perform private.study_require(cfg.revision=i.config_revision and cfg.report_enabled,'CAPABILITY_UNAVAILABLE');
 perform private.study_require((select status='active' from private.studies where id=i.study_id),'FROZEN_REVISION');
 if i.operation<>'report.create' then
  perform private.study_require(private.study_method_report_record(r.id)=i.report_snapshot,'REVISION_CONFLICT');
 end if;return i;
end$$;

create or replace function "api"."svc_study_report_method_intent_consume_v1"("p_intent_id" "uuid", "p_completion" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare i private.study_report_intents%rowtype;r private.study_report_revisions%rowtype;refs jsonb;contentref jsonb;artifact uuid;result jsonb;validation jsonb;claimcount integer;runids jsonb;assessmentids jsonb;binding text;assessmentid uuid;config_hash text;
begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 i:=private.study_method_report_intent_check(p_intent_id);
 select * into i from private.study_report_intents where id=i.id for update;
 if i.response is not null then return i.response;end if;
 if i.operation='report.create' then
  refs:=private.study_method_report_rights(i.study_id,i.request->'runIds',i.request->'methodAssessmentIds',i.actor_id,i.client_id);claimcount:=jsonb_array_length(i.request->'content'->'claims');
 else
  select * into r from private.study_report_revisions where id=i.report_id for update;
  refs:=private.study_method_report_rights(i.study_id,r.run_ids,r.method_assessment_ids,i.actor_id,i.client_id);
  claimcount:=case when i.operation='report.save' then jsonb_array_length(i.request->'content'->'claims') else (r.validation_evidence->>'claimCount')::integer end;
 end if;
 runids:=case when i.operation='report.create'then i.request->'runIds'else r.run_ids end;
 assessmentids:=case when i.operation='report.create'then i.request->'methodAssessmentIds'else r.method_assessment_ids end;
 assessmentid:=(assessmentids->>0)::uuid;select ma.config_hash into config_hash from private.study_method_assessments ma where ma.id=assessmentid;
 binding:=private.study_method_report_binding(i.study_id,runids,assessmentids);
 validation:=p_completion->'validation';
 if i.operation in ('report.create','report.save') then
  perform private.study_require(private.study_keys(p_completion,array['kind','contentArtifact','factsRefs','validation']) and p_completion->>'kind'='validatedContent'
   and p_completion->'factsRefs'=refs,'REFERENCE_MISMATCH');
  contentref:=p_completion->'contentArtifact'->'artifactRef';
  perform private.study_method_report_validation_check(validation,i.report_id,contentref->>'contentHash',claimcount,binding,assessmentid,config_hash);
  artifact:=private.study_report_store_produced(i.study_id,p_completion->'contentArtifact',i.content_artifact_id,'reportContent','lca.study-method-report-content.v1','content');
  if i.operation='report.create' then
   insert into private.study_report_revisions(id,study_id,parent_report_id,author_id,content_hash,content_artifact_id,template_id,run_ids,analysis_ids,method_assessment_ids,facts_refs,validity_snapshot,validation_evidence)
   values(i.report_id,i.study_id,(i.request->>'parentReportRevisionId')::uuid,i.actor_id,contentref->>'contentHash',artifact,i.request->>'templateId',i.request->'runIds','[]'::jsonb,i.request->'methodAssessmentIds',refs,
   private.study_report_validity_snapshot(i.study_id,i.request->'runIds',i.created_at),validation);
   insert into private.study_report_runs select i.study_id,i.report_id,n,v::uuid from jsonb_array_elements_text(i.request->'runIds') with ordinality e(v,n);
   insert into private.study_report_method_assessments select i.study_id,i.report_id,(i.request->'methodAssessmentIds'->>0)::uuid;
  else update private.study_report_revisions set revision=revision+1,content_hash=contentref->>'contentHash',content_artifact_id=artifact,validation_evidence=validation where id=i.report_id;end if;
  result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','reportRevision','value',private.study_method_report_record(i.report_id)));
 elsif i.operation='report.freeze' then
  select ref into contentref from private.study_artifacts where id=r.content_artifact_id;
  perform private.study_require(private.study_keys(p_completion,array['kind','contentRef','validation']) and p_completion->>'kind'='validatedFreeze' and p_completion->'contentRef'=contentref,'REFERENCE_MISMATCH');
  perform private.study_method_report_validation_check(validation,r.id,r.content_hash,claimcount,binding,assessmentid,config_hash);
  update private.study_report_revisions set status='frozen',revision=revision+1,validation_evidence=validation where id=r.id;
  result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','reportRevision','value',private.study_method_report_record(r.id)));
 end if;
 update private.study_report_intents set response=result where id=i.id;
 update private.study_command_receipts set response=result where actor_id=i.actor_id and operation='method.'||i.operation and scope=i.study_id::text and idempotency_key=i.request->>'idempotencyKey';return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range or check_violation or not_null_violation or invalid_datetime_format then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');
end$_$;

create or replace function "api"."svc_study_report_method_intent_reconcile_v1"("p_intent_id" "uuid", "p_artifact_id" "uuid", "p_content_hash" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare i private.study_report_intents%rowtype;a private.study_artifacts%rowtype;expected_ref jsonb;state text:='unknown';begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 perform private.study_require(p_intent_id is not null and p_artifact_id is not null and private.study_text(to_jsonb(p_content_hash),64,'^[0-9a-f]{64}$'),'INVALID_REQUEST');
 select * into i from private.study_report_intents where id=p_intent_id;
 if found and i.family='method' then
  perform 1 from private.studies where id=i.study_id for update;
  select * into i from private.study_report_intents where id=p_intent_id for update;
  if p_artifact_id=any(array[i.content_artifact_id,i.projection_artifact_id,i.resources_artifact_id,i.bundle_artifact_id]) then
   select * into a from private.study_artifacts where id=p_artifact_id;
   if found then
    expected_ref:=case when p_artifact_id=i.content_artifact_id then i.response->'data'->'value'->'contentRef'
     when p_artifact_id=i.projection_artifact_id then i.response->'data'->'value'->'projectionRef'
     when p_artifact_id=i.resources_artifact_id then i.response->'data'->'value'->'resourcesRef'
     else i.response->'data'->'value'->'bundleRef' end;
    if i.response->>'ok'='true' and a.study_id=i.study_id and a.ref=expected_ref and a.ref->>'contentHash'=p_content_hash then state:='committed';
    else state:='referenced';end if;
   elsif i.response is null and i.expires_at<=clock_timestamp() then state:='expired_unreferenced';
   elsif i.response is null then state:='pending';end if;
  end if;
 end if;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('schemaVersion','lca.study-method-report-reconcile.v1','intentId',p_intent_id,'artifactId',p_artifact_id,'state',state,'deletionPermitted',false));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end$_$;

create or replace function "api"."svc_study_report_method_intent_resolve_v1"("p_intent_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare i private.study_report_intents%rowtype;r private.study_report_revisions%rowtype;runids jsonb;assessmentids jsonb;runs jsonb;methodAssessments jsonb;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');i:=private.study_method_report_intent_check(p_intent_id);
 if i.response is not null then return i.response;end if;
 if i.operation='report.create' then runids:=i.request->'runIds';assessmentids:=i.request->'methodAssessmentIds';
 else select * into r from private.study_report_revisions where id=i.report_id;runids:=r.run_ids;assessmentids:=r.method_assessment_ids;end if;
 select jsonb_agg(jsonb_build_object('run',private.study_record('run',rn.id),'revision',private.study_record('studyRevision',rn.study_revision_id),
 'scenario',private.study_record('scenarioRevision',rn.scenario_id),'preparation',private.study_record('modelPreparation',rn.preparation_id),
 'preparedArtifact',private.study_private_artifact(i.study_id,p.input_artifact_id),'resultArtifact',private.study_private_artifact(i.study_id,rn.result_artifact_id)) order by e.n)
 into runs from jsonb_array_elements_text(runids) with ordinality e(v,n) join private.study_runs rn on rn.id=e.v::uuid and rn.study_id=i.study_id
 join private.study_model_preparations p on p.id=rn.preparation_id;
 select jsonb_agg(jsonb_build_object('assessment',private.study_method_record(a.id),'factsArtifact',private.study_private_artifact(i.study_id,a.facts_artifact_id),'sourceSnapshotRef',(select ar.ref from private.study_source_snapshots ss join private.study_artifacts ar on ar.id=ss.artifact_id where ss.id=a.source_snapshot_id)) order by e.n)
 into methodAssessments from jsonb_array_elements_text(assessmentids) with ordinality e(v,n) join private.study_method_assessments a on a.id=e.v::uuid and a.study_id=i.study_id;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('kind','reportMethodCommandContext','intentId',i.id,'expiresAt',i.expires_at,'operation',i.operation,
 'request',i.request,'studyId',i.study_id,'actorId',i.actor_id,'clientId',i.client_id,'grantEpoch',i.grant_epoch,'generatedAt',i.created_at,
 'reportRevisionId',i.report_id,'contentArtifactId',i.content_artifact_id,'exportId',i.export_id,'projectionArtifactId',i.projection_artifact_id,
 'resourcesArtifactId',i.resources_artifact_id,'bundleArtifactId',i.bundle_artifact_id,'report',i.report_snapshot,
 'contentArtifact',case when r.id is not null then private.study_private_artifact(i.study_id,r.content_artifact_id) end,'runs',runs,'methodAssessments',methodAssessments,
 'exportProfile',case when i.operation='export.request' then (select export_profile from private.study_reporting_config where singleton) end,
 'disclosureContextHash',case when i.operation='export.request' then private.study_report_disclosure_context(i) end,
 'factsBindingHash',private.study_method_report_binding(i.study_id,runids,assessmentids)));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end$$;


create table private.study_method_review_config (
 singleton boolean primary key default true check(singleton),revision bigint not null default 1 check(revision>0),
 enabled boolean not null default false,export_enabled boolean not null default false,export_profile jsonb,qualification_evidence_ref text,
 check(not export_enabled or (enabled and export_profile is not null)),
 check(not(enabled or export_enabled) or(qualification_evidence_ref is not null and coalesce(private.study_method_text(to_jsonb(qualification_evidence_ref),512),false)))
);
insert into private.study_method_review_config(singleton) values(true);
create function api.svc_study_review_method_configure_v1(p_expected_revision bigint,p_configuration jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$declare cfg private.study_method_review_config%rowtype;p jsonb:=p_configuration->'exportProfile';begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 perform private.study_require(private.study_keys(p_configuration,array['qualificationVersion','enabled','exportEnabled','exportProfile','evidenceRef'])
 and p_configuration->>'qualificationVersion'='lca.study-method-review-qualification.v1' and jsonb_typeof(p_configuration->'enabled')='boolean'
 and jsonb_typeof(p_configuration->'exportEnabled')='boolean' and private.study_text(p_configuration->'evidenceRef',512),'INVALID_REQUEST');
 if p<>'null'::jsonb then
  perform private.study_require(private.study_keys(p,array['issuerId','keyId','rendererVersion','viewModelVersion','rendererArtifactHash','policyId'])
   and private.study_text(p->'issuerId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$') and private.study_text(p->'keyId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$')
   and p->>'rendererVersion'='3.0.0' and p->>'viewModelVersion'='lca.study-report-view.v3'
   and private.study_text(p->'rendererArtifactHash',64,'^[0-9a-f]{64}$') and p->>'policyId'='lca.study-report-disclosure.v1','INVALID_REQUEST');
 end if;
 select * into cfg from private.study_method_review_config where singleton for update;perform private.study_require(cfg.revision=p_expected_revision,'REVISION_CONFLICT');
 update private.study_method_review_config set revision=revision+1,enabled=(p_configuration->>'enabled')::boolean,export_enabled=(p_configuration->>'exportEnabled')::boolean,
  export_profile=nullif(p,'null'::jsonb),qualification_evidence_ref=p_configuration->>'evidenceRef' where singleton returning * into cfg;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('revision',cfg.revision,'enabled',cfg.enabled,'qualificationVersion','lca.study-method-review-qualification.v1','evidenceRef',cfg.qualification_evidence_ref));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or check_violation or not_null_violation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');end$$;

create or replace function "private"."study_method_review_envelope"("p_request" "jsonb", "p_write" boolean) RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $_$declare field text;value jsonb;entry jsonb;pattern text:='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';begin
 perform private.study_require(auth.uid() is not null and not coalesce(util.is_service_request(),false),'AUTH_REQUIRED');
 perform private.study_require(p_request->>'schemaVersion'='lca.study-api.v6' and octet_length(p_request::text)<=262144
  and private.study_text(p_request->'requestId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');
 if p_write then perform private.study_require(private.study_text(p_request->'idempotencyKey',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');end if;
 -- Issued domain references are opaque exact identities. PostgreSQL accepts
 -- UUID aliases, but resolving an alias would change the response binding
 -- after effects. Reject it before every domain cast, receipt or intent.
 foreach field in array array['target','resource'] loop
  if p_request ? field then
   perform private.study_require(jsonb_typeof(p_request->field)='object'
    and private.study_text(p_request->field->'id',36,pattern),'INVALID_REQUEST');
  end if;
 end loop;
 foreach field in array array['reportRevisionId','shareId','exportId','delegationId','finalizationId','predecessorReviewId','recipientId'] loop
  if not p_request ? field then continue;end if;value:=p_request->field;
  if value='null'::jsonb and ((field='predecessorReviewId' and p_request->>'operation' in ('review.record','review.delegation.issue'))
   or (field='delegationId' and p_request->>'operation'='review.record')) then continue;end if;
  perform private.study_require(private.study_text(value,36,pattern),'INVALID_REQUEST');
 end loop;
 if p_request ? 'acceptedReviewIds' then
  perform private.study_require(jsonb_typeof(p_request->'acceptedReviewIds')='array','INVALID_REQUEST');
  perform private.study_require(jsonb_array_length(p_request->'acceptedReviewIds')<=64,'INVALID_REQUEST');
  for entry in select * from jsonb_array_elements(p_request->'acceptedReviewIds') loop
   perform private.study_require(private.study_text(entry,36,pattern),'INVALID_REQUEST');
  end loop;
 end if;
end$_$;

create or replace function "private"."study_method_review_new_intent"("p_request" "jsonb", "p_report" "uuid", "p_share" "uuid" DEFAULT NULL::"uuid", "p_export" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare r private.study_report_revisions%rowtype;e private.study_review_exports%rowtype;i private.study_review_intents%rowtype;st jsonb;cfg private.study_method_review_config%rowtype;actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');op text:=p_request->>'operation';begin
 select * into r from private.study_report_revisions where id=p_report;perform private.study_require(found and r.template_id='lca.study-method-report.v1' and p_request->>'schemaVersion'='lca.study-api.v6','REFERENCE_MISMATCH');
 if p_share is not null then perform private.study_review_share_check(p_share,actor,client,true);
 elsif op='export.download' then
  e:=private.study_review_export_check(p_export,actor,client);perform private.study_require(e.report_id=p_report,'REFERENCE_MISMATCH');
 else perform private.study_review_authorize(r.study_id,actor,client,case when op='export.request' then 'manage' else 'read' end);perform private.study_review_disclosure(r.id);end if;
 st:=private.study_review_state(r.id);
 if op='export.request' then
  perform private.study_require(st->>'acceptance'='current' and st->'finalization'->>'finalizationId'=p_request->>'finalizationId'
   and st->>'reviewStateHash'=p_request->>'expectedReviewStateHash','REVISION_CONFLICT');
  perform private.study_analysis_require_current(r.study_id,jsonb_build_object('runIds',r.run_ids));
  perform private.study_require((select export_enabled and export_profile is not null from private.study_method_review_config where singleton),'CAPABILITY_UNAVAILABLE');
 end if;
 select * into cfg from private.study_method_review_config where singleton for share;perform private.study_require(cfg.enabled,'CAPABILITY_UNAVAILABLE');
 perform pg_advisory_xact_lock(hashtextextended('study-review-intent:'||actor::text,906));
 perform private.study_require((select count(*) from private.study_review_intents where actor_id=actor and response is null and expires_at>clock_timestamp())<64,'CAPABILITY_UNAVAILABLE');
 insert into private.study_review_intents(study_id,report_id,actor_id,client_id,operation,request,share_id,finalization_id,grant_epoch,config_revision,reporting_config_revision,review_state_hash,
 export_id,projection_artifact_id,resources_artifact_id,bundle_artifact_id,disclosure_context_hash)
 values(r.study_id,r.id,actor,client,op,p_request,p_share,case when op='export.download' then e.finalization_id else (st->'finalization'->>'finalizationId')::uuid end,
 (select grant_epoch from private.studies where id=r.study_id),cfg.revision,(select revision from private.study_method_review_config where singleton),st->>'reviewStateHash',
 case when op='export.request' then gen_random_uuid() when op='export.download' then e.id end,case when op='export.request' then gen_random_uuid() end,
 case when op='export.request' then gen_random_uuid() end,case when op='export.request' then gen_random_uuid() end,
 private.study_reporting_digest('lca.study-review-disclosure.v1',jsonb_build_object('actorId',actor,'clientId',client,'reportRevisionId',r.id,'reportContentHash',r.content_hash,'reviewStateHash',st->>'reviewStateHash','shareId',p_share,'nonce',gen_random_uuid()))) returning * into i;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('kind','studyMethodReviewIntent','intentId',i.id,'operation',i.operation,'expiresAt',i.expires_at));
end$$;

create or replace function "private"."study_method_review_intent_check"("p_id" "uuid") RETURNS "private"."study_review_intents"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare i private.study_review_intents%rowtype;st jsonb;cfg private.study_method_review_config%rowtype;begin
 select * into i from private.study_review_intents where id=p_id;perform private.study_require(found and i.request->>'schemaVersion'='lca.study-api.v6' and exists(select 1 from private.study_report_revisions where id=i.report_id and template_id='lca.study-method-report.v1'),'CAPABILITY_UNAVAILABLE');
 perform 1 from private.studies where id=i.study_id for update;
 select * into i from private.study_review_intents where id=p_id;
 if i.share_id is not null then perform private.study_review_share_check(i.share_id,i.actor_id,i.client_id,true);
 elsif i.operation='export.download' then perform private.study_review_export_check(i.export_id,i.actor_id,i.client_id);
 else perform private.study_review_authorize(i.study_id,i.actor_id,i.client_id,case when i.operation='export.request' then 'manage' else 'read' end);perform private.study_review_disclosure(i.report_id);end if;
 if i.response is not null then return i;end if;
 select * into cfg from private.study_method_review_config where singleton for share;
 perform private.study_require(cfg.enabled and cfg.revision=i.config_revision and i.expires_at>clock_timestamp(),'CAPABILITY_UNAVAILABLE');
 perform private.study_require(i.grant_epoch=(select grant_epoch from private.studies where id=i.study_id),'FORBIDDEN');
 if i.operation='export.request' then
  st:=private.study_review_state(i.report_id);
  perform private.study_require(st->>'acceptance'='current' and st->'finalization'->>'finalizationId'=i.finalization_id::text and st->>'reviewStateHash'=i.review_state_hash,'REVISION_CONFLICT');
  perform private.study_analysis_require_current(i.study_id,jsonb_build_object('runIds',(select run_ids from private.study_report_revisions where id=i.report_id)));
  perform private.study_require((select export_enabled and export_profile is not null and revision=i.reporting_config_revision from private.study_method_review_config where singleton),'CAPABILITY_UNAVAILABLE');
 end if;return i;
end$$;

create or replace function "private"."study_method_review_actions"("p_type" "text", "p_id" "uuid", "p_actor" "uuid", "p_client" "text") RETURNS "jsonb"
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

create or replace function "api"."cmd_study_method_review_v1"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '15s'
    AS $_$
declare op text:=p_request->>'operation';actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');sid uuid;rid uuid;newid uuid;head uuid;allowed text[];
 req jsonb:=(p_request-'schemaVersion'-'requestId'-'idempotencyKey')||jsonb_build_object('_verifiedClientId',client);prev private.study_command_receipts%rowtype;r private.study_report_revisions%rowtype;d private.study_review_delegations%rowtype;
 s private.study_report_shares%rowtype;e private.study_review_exports%rowtype;study private.studies%rowtype;st jsonb;result jsonb;value jsonb;ts timestamptz;
begin
 perform private.study_method_review_envelope(p_request,true);perform private.study_review_family(p_request,'lca.study-method-report.v1');
 perform private.study_require(op<>'member.set','CAPABILITY_UNAVAILABLE');
 case op
 when 'review.delegation.revoke' then allowed:=array['delegationId'];select study_id,report_id into sid,rid from private.study_review_delegations where id=(p_request->>'delegationId')::uuid;
 when 'share.revoke' then allowed:=array['shareId','reason'];select study_id,report_id into sid,rid from private.study_report_shares where id=(p_request->>'shareId')::uuid;
 when 'report.finalize' then allowed:=array['target','expectedContentHash','expectedReviewStateHash','profileId','acceptedReviewIds'];rid:=(p_request->'target'->>'id')::uuid;
 when 'comment.append' then allowed:=array['reportRevisionId','expectedContentHash','text'];rid:=(p_request->>'reportRevisionId')::uuid;
 when 'review.record' then allowed:=array['reportRevisionId','expectedContentHash','reviewClass','decision','comment','predecessorReviewId','delegationId'];rid:=(p_request->>'reportRevisionId')::uuid;
 when 'review.delegation.issue' then allowed:=array['reportRevisionId','expectedContentHash','clientId','reviewClass','decision','predecessorReviewId','expiresAt'];rid:=(p_request->>'reportRevisionId')::uuid;
 when 'export.request' then allowed:=array['reportRevisionId','expectedContentHash','finalizationId','expectedReviewStateHash','rendererVersion','viewModelVersion'];rid:=(p_request->>'reportRevisionId')::uuid;
 when 'share.create' then allowed:=array['reportRevisionId','expectedContentHash','exportId','recipientId','disclosurePolicyId','expiresAt'];rid:=(p_request->>'reportRevisionId')::uuid;
 else perform private.study_require(false,'CAPABILITY_UNAVAILABLE');end case;
 perform private.study_require(private.study_keys(p_request,allowed||array['schemaVersion','requestId','idempotencyKey','operation']),'INVALID_REQUEST');
 if sid is null and rid is not null then select study_id into sid from private.study_report_revisions where id=rid;end if;
 perform private.study_review_authorize(sid,actor,client,case when op in ('report.finalize','export.request','share.create','share.revoke') then 'manage'
 when op in ('review.record','review.delegation.issue','review.delegation.revoke') then 'review' else 'comment' end);
 select * into study from private.studies where id=sid;
 -- Explicit share/delegation revoke does not require report-byte disclosure.
 -- All fresh mutations still require an active Study below.
 if rid is not null and op not in ('share.revoke','review.delegation.revoke') then
  select * into r from private.study_report_revisions where id=rid and study_id=sid;
  perform private.study_require(found and r.status='frozen' and r.content_hash=p_request->>'expectedContentHash','REFERENCE_MISMATCH');
  perform private.study_review_disclosure(r.id);
 end if;
 if op in ('review.delegation.issue','review.delegation.revoke') then perform private.study_require(client is null,'FORBIDDEN');end if;
 if op='review.delegation.revoke' then select * into d from private.study_review_delegations where id=(p_request->>'delegationId')::uuid;perform private.study_require(d.actor_id=actor,'FORBIDDEN');end if;
 if op='share.revoke' then select * into s from private.study_report_shares where id=(p_request->>'shareId')::uuid;perform private.study_require(s.issuer_id=actor,'FORBIDDEN');end if;
 select * into prev from private.study_command_receipts where actor_id=actor and operation=op and scope='v6:'||sid::text and idempotency_key=p_request->>'idempotencyKey';
 if found then
  perform private.study_require(prev.request=req,'IDEMPOTENCY_CONFLICT');
  if op='review.record' and client is not null then
   select * into d from private.study_review_delegations where id=(p_request->>'delegationId')::uuid;
   perform private.study_require(d.actor_id=actor and d.client_id=client and d.revoked_at is null and d.consumed_review_id::text=prev.response->'data'->'value'->>'reviewId','FORBIDDEN');
  end if;
  if op='export.request' and prev.response->'data'->>'kind'='studyMethodReviewIntent' then
   declare oldintent private.study_review_intents%rowtype;begin oldintent:=private.study_method_review_intent_check((prev.response->'data'->>'intentId')::uuid);if oldintent.response is not null then return oldintent.response;end if;end;
  end if;return private.study_review_refresh(prev.response);
 end if;
 perform private.study_require(study.status='active','FROZEN_REVISION');
 perform 1 from private.study_method_review_config where singleton and enabled for share;perform private.study_require(found,'CAPABILITY_UNAVAILABLE');
 if op='comment.append' then
  perform private.study_require(private.study_text(p_request->'text',4096) and p_request->>'text' !~ '[<>]','INVALID_REQUEST');
  insert into private.study_report_comments(study_id,report_id,report_hash,actor_id,client_id,body) values(sid,r.id,r.content_hash,actor,client,p_request->>'text') returning id into newid;
  value:=jsonb_build_object('type','comment','value',private.study_comment_record(newid));
 elsif op in ('review.record','review.delegation.issue') then
  perform private.study_require(p_request->>'reviewClass'='internal' and p_request->>'decision' in ('approve','reject','withdraw'),'INVALID_REQUEST');
  perform private.study_require(p_request->>'decision'<>'approve' or actor<>r.author_id,'FORBIDDEN');
  select review_id into head from private.study_report_review_heads where report_id=r.id and actor_id=actor and review_class='internal';
  perform private.study_require(head is not distinct from (p_request->>'predecessorReviewId')::uuid,'REVISION_CONFLICT');
  perform private.study_require(p_request->>'decision'<>'withdraw' or head is not null,'REVISION_CONFLICT');
  if op='review.delegation.issue' then
   perform private.study_require((p_request->>'clientId') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' and private.study_client_allowed(p_request->>'clientId','STUDY-WRITE-01'),'FORBIDDEN');
   ts:=(p_request->>'expiresAt')::timestamptz;perform private.study_require(ts>clock_timestamp() and ts<=clock_timestamp()+interval '15 minutes','INVALID_REQUEST');
   insert into private.study_review_delegations(study_id,report_id,report_hash,actor_id,client_id,review_class,decision,predecessor_id,expires_at)
   values(sid,r.id,r.content_hash,actor,p_request->>'clientId','internal',p_request->>'decision',head,ts) returning id into newid;
   value:=jsonb_build_object('type','delegation','value',private.study_delegation_record(newid));
  else
   perform private.study_require(private.study_text(p_request->'comment',4096) and p_request->>'comment' !~ '[<>]','INVALID_REQUEST');
   perform private.study_require(head is not null or (select count(*) from private.study_report_review_heads where report_id=r.id)<64,'CAPABILITY_UNAVAILABLE');
   if client is null then perform private.study_require(p_request->'delegationId'='null'::jsonb,'FORBIDDEN');
   else
    select * into d from private.study_review_delegations where id=(p_request->>'delegationId')::uuid for update;
    perform private.study_require(found and d.actor_id=actor and d.client_id=client and d.report_id=r.id and d.report_hash=r.content_hash and d.review_class='internal'
     and d.decision=p_request->>'decision' and d.predecessor_id is not distinct from head and d.revoked_at is null and d.consumed_review_id is null and d.expires_at>clock_timestamp(),'FORBIDDEN');
   end if;
   insert into private.study_report_reviews(study_id,report_id,report_hash,actor_id,client_id,review_class,decision,body,predecessor_id,delegation_id)
    values(sid,r.id,r.content_hash,actor,client,'internal',p_request->>'decision',p_request->>'comment',head,d.id) returning id into newid;
   insert into private.study_report_review_heads values(r.id,actor,'internal',newid) on conflict(report_id,actor_id,review_class) do update set review_id=excluded.review_id;
   if d.id is not null then update private.study_review_delegations set consumed_review_id=newid where id=d.id;end if;
   value:=jsonb_build_object('type','review','value',private.study_review_record(newid),'state',private.study_review_state(r.id));
  end if;
 elsif op='review.delegation.revoke' then
  update private.study_review_delegations set revoked_at=coalesce(revoked_at,clock_timestamp()) where id=d.id;
  value:=jsonb_build_object('type','delegation','value',private.study_delegation_record(d.id));
 elsif op='report.finalize' then
  perform private.study_require(private.study_keys(p_request->'target',array['type','id','expectedRevision']) and p_request->'target'->>'type'='reportRevision'
   and jsonb_typeof(p_request->'target'->'expectedRevision')='number' and (p_request->'target'->>'expectedRevision')::numeric=r.revision,'REVISION_CONFLICT');
  st:=private.study_review_state(r.id);perform private.study_require(st->>'reviewStateHash'=p_request->>'expectedReviewStateHash','REVISION_CONFLICT');
  perform private.study_require(p_request->>'profileId' in ('lca.study-report-unreviewed.v1','lca.study-report-internal-review.v1')
   and private.study_report_ids(p_request->'acceptedReviewIds',0,64),'INVALID_REQUEST');
  perform private.study_require(case when p_request->>'profileId'='lca.study-report-unreviewed.v1' then p_request->'acceptedReviewIds'='[]'::jsonb
   else jsonb_array_length(p_request->'acceptedReviewIds')>0 and (p_request->'acceptedReviewIds')<@(st->'acceptedReviewIds') end,'FORBIDDEN');
  insert into private.study_report_finalizations(study_id,report_id,report_hash,actor_id,profile_id,expected_review_state_hash,accepted_review_ids)
   values(sid,r.id,r.content_hash,actor,p_request->>'profileId',p_request->>'expectedReviewStateHash',p_request->'acceptedReviewIds') returning id into newid;
  value:=jsonb_build_object('type','finalization','value',private.study_finalization_record(newid),'state',private.study_review_state(r.id));
 elsif op='export.request' then
  perform private.study_require(p_request->>'rendererVersion'='3.0.0' and p_request->>'viewModelVersion'='lca.study-report-view.v3','CAPABILITY_UNAVAILABLE');
  result:=private.study_method_review_new_intent(p_request,r.id);value:=result->'data';
 elsif op='share.create' then
  select * into e from private.study_review_exports where id=(p_request->>'exportId')::uuid;
  st:=private.study_review_state(r.id);
  perform private.study_require(found and e.report_id=r.id and e.actor_id=actor and e.grant_epoch=study.grant_epoch and st->>'acceptance'='current'
   and st->'finalization'->>'finalizationId'=e.finalization_id::text and private.study_client_allowed(e.client_id,'STUDY-WRITE-01'),'DISCLOSURE_DENIED');
  perform private.study_require(p_request->>'disclosurePolicyId'='lca.study-report-summary-share.v1','INVALID_REQUEST');
  ts:=(p_request->>'expiresAt')::timestamptz;perform private.study_require(ts>clock_timestamp() and ts<=clock_timestamp()+interval '30 days','INVALID_REQUEST');
  insert into private.study_report_shares(study_id,report_id,report_hash,export_id,finalization_id,issuer_id,issuer_client_id,recipient_id,grant_epoch,disclosure_context_hash,expires_at)
   values(sid,r.id,r.content_hash,e.id,e.finalization_id,actor,client,(p_request->>'recipientId')::uuid,study.grant_epoch,
   private.study_reporting_digest('lca.study-summary-share.v1',jsonb_build_object('exportId',e.id,'recipientId',p_request->>'recipientId','grantEpoch',study.grant_epoch,'nonce',gen_random_uuid())),ts) returning id into newid;
  value:=jsonb_build_object('type','share','value',private.study_review_share_record(newid));
 elsif op='share.revoke' then
  perform private.study_require(private.study_text(p_request->'reason',4096) and p_request->>'reason' !~ '[<>]','INVALID_REQUEST');
  update private.study_report_shares set revoked_at=coalesce(revoked_at,clock_timestamp()),revocation_reason=coalesce(revocation_reason,p_request->>'reason') where id=s.id;
  value:=jsonb_build_object('type','share','value',private.study_review_share_record(s.id));
 end if;
 result:=jsonb_build_object('ok',true,'data',value);
 insert into private.study_command_receipts values(actor,op,'v6:'||sid::text,p_request->>'idempotencyKey',req,result,clock_timestamp());return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range or check_violation or not_null_violation or invalid_datetime_format then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');end$_$;

create or replace function "api"."qry_study_method_review_v1"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '15s'
    AS $$
declare op text:=p_request->>'operation';actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');allowed text[];rid uuid;r private.study_report_revisions%rowtype;
 s private.study_report_shares%rowtype;e private.study_review_exports%rowtype;value jsonb;ops jsonb;kind text;lim integer;afterid uuid;nextid uuid;ids uuid[];resource_id uuid;
 selection jsonb;epoch text;cur private.study_cursors%rowtype;items jsonb:='[]'::jsonb;more boolean;
begin
 perform private.study_method_review_envelope(p_request,false);perform private.study_review_family(p_request,'lca.study-method-report.v1');perform private.study_require(private.study_client_allowed(client,'STUDY-READ-01'),'FORBIDDEN');
 if op='capability.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation']),'INVALID_REQUEST');
  if not(select enabled from private.study_method_review_config where singleton) then
   value:=jsonb_build_object('type','capabilities','contractVersion','6.0.0','runtimeEnabled',false,'operations',jsonb_build_array('capability.read'),'finalizationProfiles','[]'::jsonb,'reviewClasses','[]'::jsonb,'disclosurePolicies','[]'::jsonb);
  else
   ops:='["capability.read","resource.actions","comment.list","review.list","review.delegation.list","report.current","report.view","export.read","export.download","share.read","share.view","share.download","share.list"]';
   if private.study_client_allowed(client,'STUDY-WRITE-01') then
    ops:=ops||'["comment.append","review.record","report.finalize","export.request","share.create","share.revoke"]'::jsonb;
    if client is null then ops:=ops||'["review.delegation.issue","review.delegation.revoke"]'::jsonb;end if;
   end if;
   value:=jsonb_build_object('type','capabilities','contractVersion','6.0.0','runtimeEnabled',true,'operations',ops,
   'finalizationProfiles',jsonb_build_array('lca.study-report-unreviewed.v1','lca.study-report-internal-review.v1'),'reviewClasses',jsonb_build_array('internal'),'disclosurePolicies',jsonb_build_array('lca.study-report-summary-share.v1'));
  end if;return jsonb_build_object('ok',true,'data',value);
 end if;
 perform private.study_require((select enabled from private.study_method_review_config where singleton),'CAPABILITY_UNAVAILABLE');
 case op
 when 'resource.actions' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','resource']) and private.study_keys(p_request->'resource',array['type','id'])
   and p_request->'resource'->>'type' in ('reportRevision','share','export'),'INVALID_REQUEST');
  case p_request->'resource'->>'type'
   when 'reportRevision' then
    select * into r from private.study_report_revisions where id=(p_request->'resource'->>'id')::uuid;
    perform private.study_review_authorize(r.study_id,actor,client,'read');
   when 'share' then s:=private.study_review_share_check((p_request->'resource'->>'id')::uuid,actor,client,false);
   when 'export' then e:=private.study_review_export_check((p_request->'resource'->>'id')::uuid,actor,client);
  end case;
  ops:=private.study_method_review_actions(p_request->'resource'->>'type',(p_request->'resource'->>'id')::uuid,actor,client);
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','actions','resource',p_request->'resource','actions',ops,'allowedMemberRoles','[]'::jsonb,
   'corePermissions',jsonb_build_object('read',false,'write',false)));
 when 'share.read','share.view','share.download' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','shareId']),'INVALID_REQUEST');
  s:=private.study_review_share_check((p_request->>'shareId')::uuid,actor,client,op<>'share.read');
  if op='share.read' then value:=jsonb_build_object('type','share','value',private.study_review_share_record(s.id));else return private.study_method_review_new_intent(p_request,s.report_id,s.id);end if;
  return jsonb_build_object('ok',true,'data',value);
 when 'export.read','export.download' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','exportId']),'INVALID_REQUEST');
  e:=private.study_review_export_check((p_request->>'exportId')::uuid,actor,client);
  if op='export.download' then return private.study_method_review_new_intent(p_request,e.report_id,null,e.id);end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','export','value',e.record));
 when 'report.current','report.view' then allowed:=array['reportRevisionId','expectedContentHash'];
 when 'comment.list','review.list','review.delegation.list','share.list' then allowed:=array['reportRevisionId','expectedContentHash','cursor','limit'];
 else perform private.study_require(false,'CAPABILITY_UNAVAILABLE');end case;
 perform private.study_require(private.study_keys(p_request,allowed||array['schemaVersion','requestId','operation']),'INVALID_REQUEST');
 rid:=(p_request->>'reportRevisionId')::uuid;select * into r from private.study_report_revisions where study_report_revisions.id=rid;
 perform private.study_review_authorize(r.study_id,actor,client,case when op='share.list' then 'manage' when op='review.delegation.list' then 'review' else 'read' end);
 perform private.study_require(r.status='frozen' and r.content_hash=p_request->>'expectedContentHash','REFERENCE_MISMATCH');perform private.study_review_disclosure(r.id);
 if op='report.current' then return jsonb_build_object('ok',true,'data',jsonb_build_object('type','reportState','value',private.study_review_state(r.id)));end if;
 if op='report.view' then return private.study_method_review_new_intent(p_request,r.id);end if;
 perform private.study_require(jsonb_typeof(p_request->'limit')='number' and (p_request->>'limit')::numeric between 1 and 100 and (p_request->>'limit')::numeric=trunc((p_request->>'limit')::numeric),'INVALID_REQUEST');lim:=(p_request->>'limit')::integer;
 selection:=p_request-'requestId'-'cursor';epoch:=private.study_access_epoch(actor,r.study_id);
 if p_request->'cursor'<>'null'::jsonb then
  select * into cur from private.study_cursors where study_cursors.id=(p_request->>'cursor')::uuid;
  perform private.study_require(found and cur.actor_id=actor and cur.client_id is not distinct from client and cur.selection=selection and cur.access_epoch=epoch and cur.expires_at>clock_timestamp(),'INVALID_REQUEST');afterid:=cur.after_id;
 end if;
 kind:=case op when 'comment.list' then 'comment' when 'review.list' then 'review' when 'review.delegation.list' then 'delegation' else 'share' end;
 select array_agg(x.id order by x.id) into ids from(
  select c.id from private.study_report_comments c where kind='comment' and c.report_id=r.id and(afterid is null or c.id>afterid)
  union all select c.id from private.study_report_reviews c where kind='review' and c.report_id=r.id and(afterid is null or c.id>afterid)
  union all select c.id from private.study_review_delegations c where kind='delegation' and c.report_id=r.id and c.actor_id=actor and(afterid is null or c.id>afterid)
  union all select c.id from private.study_report_shares c where kind='share' and c.report_id=r.id and c.issuer_id=actor and(afterid is null or c.id>afterid)
  order by id limit lim+1)x;
 more:=coalesce(cardinality(ids)>lim,false);
 foreach resource_id in array coalesce(ids[1:lim],'{}') loop
  items:=items||jsonb_build_array(case kind when 'comment' then private.study_comment_record(resource_id) when 'review' then private.study_review_record(resource_id) when 'delegation' then private.study_delegation_record(resource_id) else private.study_review_share_record(resource_id) end);
 end loop;
 if more then insert into private.study_cursors(actor_id,client_id,selection,access_epoch,after_id) values(actor,client,selection,epoch,ids[lim]) returning study_cursors.id into nextid;end if;
 value:=jsonb_build_object('type','history','studyId',r.study_id,'reportRevisionId',r.id,'reportContentHash',r.content_hash,'kind',kind,'items',items,'nextCursor',nextid);
 return jsonb_build_object('ok',true,'data',value);
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');end$$;

create or replace function "api"."svc_study_review_method_intent_resolve_v1"("p_intent_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare i private.study_review_intents%rowtype;r private.study_report_revisions%rowtype;s private.study_report_shares%rowtype;e private.study_review_exports%rowtype;
 st jsonb;producer jsonb;runs jsonb;methodAssessments jsonb;issuer uuid;artifact jsonb;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');i:=private.study_method_review_intent_check(p_intent_id);
 if i.response is not null then return i.response;end if;
 select * into r from private.study_report_revisions where id=i.report_id;st:=jsonb_set(private.study_review_state(r.id),'{checkedAt}',to_jsonb(i.created_at));
 if i.operation='export.download' then
  select * into e from private.study_review_exports where id=i.export_id;
  artifact:=private.study_private_artifact(i.study_id,e.bundle_artifact_id)||jsonb_build_object('kind','artifactCapability');
 elsif i.share_id is null then
  select owner_id into issuer from private.studies where id=i.study_id;
  select jsonb_agg(jsonb_build_object('run',private.study_record('run',rn.id),'revision',private.study_record('studyRevision',rn.study_revision_id),
   'scenario',private.study_record('scenarioRevision',rn.scenario_id),'preparation',private.study_record('modelPreparation',rn.preparation_id),
   'preparedArtifact',private.study_private_artifact(i.study_id,p.input_artifact_id),'resultArtifact',private.study_private_artifact(i.study_id,rn.result_artifact_id)) order by x.n)
   into runs from jsonb_array_elements_text(r.run_ids) with ordinality x(v,n) join private.study_runs rn on rn.id=x.v::uuid and rn.study_id=i.study_id join private.study_model_preparations p on p.id=rn.preparation_id;
  select jsonb_agg(jsonb_build_object('assessment',private.study_method_record(a.id),'factsArtifact',private.study_private_artifact(i.study_id,a.facts_artifact_id),'sourceSnapshotRef',(select ar.ref from private.study_source_snapshots ss join private.study_artifacts ar on ar.id=ss.artifact_id where ss.id=a.source_snapshot_id)) order by x.n)
   into methodAssessments from jsonb_array_elements_text(r.method_assessment_ids) with ordinality x(v,n) join private.study_method_assessments a on a.id=x.v::uuid and a.study_id=i.study_id;
  producer:=jsonb_build_object('kind','reportMethodCommandContext','intentId',i.id,'expiresAt',i.expires_at,'operation',i.operation,
   'request',i.request,
   'studyId',i.study_id,'actorId',issuer,'clientId',null,'grantEpoch',i.grant_epoch,'generatedAt',i.created_at,'reportRevisionId',r.id,'contentArtifactId',null,
   'exportId',i.export_id,'projectionArtifactId',i.projection_artifact_id,'resourcesArtifactId',i.resources_artifact_id,'bundleArtifactId',i.bundle_artifact_id,
   'report',private.study_method_report_record(r.id),'contentArtifact',private.study_private_artifact(i.study_id,r.content_artifact_id),'runs',runs,'methodAssessments',methodAssessments,
   'factsBindingHash',private.study_method_report_binding(i.study_id,r.run_ids,r.method_assessment_ids),'disclosureContextHash',i.disclosure_context_hash,
   'exportProfile',(select export_profile from private.study_method_review_config where singleton));
 else
  select * into s from private.study_report_shares where id=i.share_id;select * into e from private.study_review_exports where id=s.export_id;
  artifact:=private.study_private_artifact(i.study_id,case when i.operation='share.view' then e.projection_artifact_id else e.bundle_artifact_id end)||jsonb_build_object('kind','artifactCapability');
 end if;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('kind','studyMethodReviewContext','intentId',i.id,'expiresAt',i.expires_at,'operation',i.operation,'actorId',i.actor_id,'clientId',i.client_id,
 'request',i.request,'currentState',st,'producerContext',producer,'share',private.study_review_share_record(s.id),'export',e.record,'artifact',artifact));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end$$;

create or replace function "api"."svc_study_review_method_intent_consume_v1"("p_intent_id" "uuid", "p_completion" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$declare i private.study_review_intents%rowtype;r private.study_report_revisions%rowtype;f jsonb;manifest jsonb;receipt jsonb;profile jsonb;record jsonb;result jsonb;projection uuid;resources uuid;bundle uuid;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');i:=private.study_method_review_intent_check(p_intent_id);
 select * into i from private.study_review_intents where id=p_intent_id for update;
 if i.response is not null then return i.response;end if;
 perform private.study_require(i.operation='export.request','INVALID_REQUEST');select * into r from private.study_report_revisions where id=i.report_id;
 f:=private.study_finalization_record(i.finalization_id);
 select export_profile into profile from private.study_method_review_config where singleton;
 perform private.study_require(private.study_keys(p_completion,array['kind','projectionArtifact','resourcesArtifact','bundleArtifact','manifest','receipt']) and p_completion->>'kind'='validatedReviewExport','REFERENCE_MISMATCH');
 manifest:=p_completion->'manifest';receipt:=p_completion->'receipt';
 perform private.study_require(private.study_keys(manifest,array['schemaVersion','issuerId','exportId','studyId','reportRevisionId','reportContentHash','actorId','clientId','grantEpoch','policyId','disclosureContextHash','generatedAt','validitySnapshot','reviewIds','finalization','renderer','files'])
  and manifest->>'schemaVersion'='lca.study-export-manifest.v4' and manifest->>'issuerId'=profile->>'issuerId' and manifest->>'exportId'=i.export_id::text
  and manifest->>'studyId'=i.study_id::text and manifest->>'reportRevisionId'=r.id::text and manifest->>'reportContentHash'=r.content_hash
  and manifest->>'actorId'=i.actor_id::text and (manifest->>'clientId') is not distinct from i.client_id
  and jsonb_typeof(manifest->'grantEpoch')='number' and (manifest->>'grantEpoch')::numeric=i.grant_epoch
  and manifest->>'policyId'='lca.study-report-disclosure.v1' and manifest->>'disclosureContextHash'=i.disclosure_context_hash
  and (manifest->>'generatedAt')::timestamptz=i.created_at and manifest->'validitySnapshot'=private.study_method_report_record(r.id)->'validitySnapshot'
  and manifest->'finalization'=f and manifest->'reviewIds'=f->'acceptedReviewIds' and (f->>'finalizedAt')::timestamptz<=i.created_at
  and manifest->'renderer'=jsonb_build_object('version','3.0.0','viewModelVersion','lca.study-report-view.v3','artifactHash',profile->>'rendererArtifactHash'),'REFERENCE_MISMATCH');
 perform private.study_require(jsonb_typeof(manifest->'files')='array' and jsonb_array_length(manifest->'files')=2
  and private.study_keys(manifest->'files'->0,array['path','mediaType','sha256','byteSize']) and private.study_keys(manifest->'files'->1,array['path','mediaType','sha256','byteSize'])
  and manifest->'files'->0->>'path'='report.html' and manifest->'files'->0->>'mediaType'='text/html' and manifest->'files'->0->>'sha256' ~ '^[0-9a-f]{64}$'
  and manifest->'files'->1->>'path'='projection.json' and manifest->'files'->1->>'mediaType'='application/json'
  and jsonb_typeof(manifest->'files'->0->'byteSize')='number' and jsonb_typeof(manifest->'files'->1->'byteSize')='number'
  and (manifest->'files'->0->>'byteSize')::numeric=trunc((manifest->'files'->0->>'byteSize')::numeric)
  and (manifest->'files'->1->>'byteSize')::numeric=trunc((manifest->'files'->1->>'byteSize')::numeric)
  and (manifest->'files'->0->>'byteSize')::numeric between 1 and 4194304 and (manifest->'files'->1->>'byteSize')::numeric between 1 and 4194304
  and (manifest->'files'->0->>'byteSize')::numeric+(manifest->'files'->1->>'byteSize')::numeric<=4194304
  and manifest->'files'->1->>'sha256'=p_completion->'projectionArtifact'->'artifactRef'->>'contentHash'
  and (manifest->'files'->1->>'byteSize')::numeric=(p_completion->'projectionArtifact'->'artifactRef'->>'byteSize')::numeric,'REFERENCE_MISMATCH');
 perform private.study_require(p_completion->'resourcesArtifact'->'artifactRef'->>'contentHash'=private.study_reporting_digest(null,manifest)
  and (p_completion->'resourcesArtifact'->'artifactRef'->>'byteSize')::numeric=octet_length(private.study_reporting_canonical(manifest))
  and private.study_keys(receipt,array['schemaVersion','manifestHash','keyId','algorithm','signature']) and receipt->>'schemaVersion'='lca.study-export-receipt.v2'
  and receipt->>'manifestHash'=private.study_reporting_digest('lca.study-export-signature.v1',manifest) and receipt->>'keyId'=profile->>'keyId'
  and receipt->>'algorithm'='Ed25519' and private.study_text(receipt->'signature',86,'^[A-Za-z0-9_-]{85}[AQgw]$'),'REFERENCE_MISMATCH');
 projection:=private.study_report_store_produced(i.study_id,p_completion->'projectionArtifact',i.projection_artifact_id,'reportProjection','lca.study-report-view.v3','projection');
 resources:=private.study_report_store_produced(i.study_id,p_completion->'resourcesArtifact',i.resources_artifact_id,'renderResources','lca.study-export-manifest.v4','resources');
 bundle:=private.study_report_store_produced(i.study_id,p_completion->'bundleArtifact',i.bundle_artifact_id,'reportExportBundle','lca.study-export-bundle.v4','bundle');
 record:=jsonb_build_object('studyId',i.study_id,'reportRevisionId',r.id,'reportContentHash',r.content_hash,'exportId',i.export_id,'finalization',f,'generatedAt',i.created_at,
  'projectionRef',p_completion->'projectionArtifact'->'artifactRef','resourcesRef',p_completion->'resourcesArtifact'->'artifactRef','bundleRef',p_completion->'bundleArtifact'->'artifactRef','receipt',receipt);
 insert into private.study_review_exports(id,study_id,report_id,actor_id,client_id,grant_epoch,finalization_id,record,manifest,projection_artifact_id,resources_artifact_id,bundle_artifact_id)
  values(i.export_id,i.study_id,r.id,i.actor_id,i.client_id,i.grant_epoch,i.finalization_id,record,manifest,projection,resources,bundle);
 result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','export','value',record));update private.study_review_intents set response=result where id=i.id;
 update private.study_command_receipts set response=result where actor_id=i.actor_id and operation=i.operation and scope='v6:'||i.study_id::text and idempotency_key=i.request->>'idempotencyKey';return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range or check_violation or not_null_violation or invalid_datetime_format then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');end$_$;

create or replace function "api"."svc_study_review_method_intent_reconcile_v1"("p_intent_id" "uuid", "p_artifact_id" "uuid", "p_content_hash" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare i private.study_review_intents%rowtype;a private.study_artifacts%rowtype;expected_ref jsonb;state text:='unknown';begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 perform private.study_require(p_intent_id is not null and p_artifact_id is not null and private.study_text(to_jsonb(p_content_hash),64,'^[0-9a-f]{64}$'),'INVALID_REQUEST');
 select * into i from private.study_review_intents where id=p_intent_id;
 if found and i.request->>'schemaVersion'='lca.study-api.v6' and exists(select 1 from private.study_report_revisions where id=i.report_id and template_id='lca.study-method-report.v1') then
  perform 1 from private.studies where id=i.study_id for update;
  select * into i from private.study_review_intents where id=p_intent_id for update;
  if p_artifact_id=any(array[i.projection_artifact_id,i.resources_artifact_id,i.bundle_artifact_id]) then
   select * into a from private.study_artifacts where id=p_artifact_id;
   if found then
    expected_ref:=case when p_artifact_id=i.projection_artifact_id then i.response->'data'->'value'->'projectionRef'
     when p_artifact_id=i.resources_artifact_id then i.response->'data'->'value'->'resourcesRef'
     else i.response->'data'->'value'->'bundleRef' end;
    if i.response->>'ok'='true' and a.study_id=i.study_id and a.ref=expected_ref and a.ref->>'contentHash'=p_content_hash then state:='committed';
    else state:='referenced';end if;
   elsif i.response is null and i.expires_at<=clock_timestamp() then state:='expired_unreferenced';
   elsif i.response is null then state:='pending';end if;
  end if;
 end if;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('schemaVersion','lca.study-method-review-reconcile.v1','intentId',p_intent_id,'artifactId',p_artifact_id,'state',state,'deletionPermitted',false));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end$_$;

create or replace function private.study_review_disclosure(p_report uuid) returns void
language plpgsql security definer set search_path='' as $$declare r private.study_report_revisions%rowtype;issuer uuid;rid text;scope jsonb;begin
 select * into r from private.study_report_revisions where id=p_report;perform private.study_require(found and r.status='frozen','REFERENCE_MISMATCH');
 select owner_id into issuer from private.studies where id=r.study_id;
 if r.template_id='lca.study-method-report.v1' then
  perform private.study_require(private.study_method_report_rights(r.study_id,r.run_ids,r.method_assessment_ids,issuer,null)=r.facts_refs,'REFERENCE_MISMATCH');
 else
 perform private.study_require(private.study_report_rights(r.study_id,r.run_ids,r.analysis_ids,issuer,null)=r.facts_refs,'REFERENCE_MISMATCH');
 end if;
 for rid in select jsonb_array_elements_text(r.run_ids) loop
  select ss.source_authorization->'sourceScope' into scope from private.study_runs rn
   join private.study_source_snapshots ss on ss.id=private.study_preparation_snapshot(r.study_id,rn.preparation_id) where rn.id=rid::uuid and rn.study_id=r.study_id;
  perform private.study_require(jsonb_typeof(scope)='array' and not exists(select 1 from jsonb_array_elements(scope)d
   where coalesce((d->>'stateCode')::integer not in (0,100),true) or ((d->>'stateCode')::integer=0 and (d->>'ownerActorId') is distinct from issuer::text)),'DISCLOSURE_DENIED');
 end loop;
end$$;


create or replace function "api"."svc_study_task_fail_v1"("p_resource_type" "text", "p_resource_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_error_code" "text", "p_idempotency_key" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare sid uuid; job uuid; kind text; subject text; result jsonb; old_context text; receipt private.study_service_receipts%rowtype; request jsonb;
begin
  perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
  if p_resource_type='methodAssessment' then
    perform private.study_require(exists(select 1 from private.study_method_assessments where id=p_resource_id and job_id=p_job_id),'REFERENCE_MISMATCH');
    return api.svc_study_method_assessment_fail_v1(p_resource_type,p_resource_id,p_job_id,p_lease_token,p_error_code,p_idempotency_key);end if;
  if p_resource_type='analysis' and exists(select 1 from private.study_advanced_analyses where id=p_resource_id and job_id=p_job_id) then return api.svc_study_analysis_advanced_fail_v1(p_resource_type,p_resource_id,p_job_id,p_lease_token,p_error_code,p_idempotency_key);end if;
  perform private.study_require(p_error_code=any(array['source_invalid','boundary_undeclared','normalization_underflow','normalization_overflow','numeric_invalid','resource_limit','model_not_solvable','native_execution_failed','job_timeout','job_lease_lost','runtime_unavailable','runtime_failed']) and length(p_idempotency_key) between 1 and 128,'INVALID_REQUEST');
  case p_resource_type
    when 'modelSourceAcquisition' then select study_id,job_id into sid,job from private.study_source_acquisitions where id=p_resource_id; kind:='study.source_acquire'; subject:='acquisitionId';
    when 'modelPreparation' then select study_id,job_id into sid,job from private.study_model_preparations where id=p_resource_id; kind:='study.model_prepare'; subject:='preparationId';
    when 'run' then select study_id,job_id into sid,job from private.study_runs where id=p_resource_id; kind:='study.run'; subject:='runId';
 when 'analysis' then select study_id,job_id into sid,job from private.study_analyses where id=p_resource_id; kind:='study.analysis'; subject:='analysisId';
    else perform private.study_require(false,'INVALID_REQUEST');
  end case;
  perform private.study_require(sid is not null and job=p_job_id,'REFERENCE_MISMATCH'); perform 1 from private.studies where id=sid for update;
  request:=jsonb_build_object('id',p_resource_id,'jobId',p_job_id,'leaseToken',p_lease_token,'errorCode',p_error_code);
  select * into receipt from private.study_service_receipts where operation=p_resource_type and study_id=sid and idempotency_key=p_idempotency_key;
  if found then perform private.study_require(receipt.request=request,'IDEMPOTENCY_CONFLICT'); return receipt.response; end if;
  if p_resource_type='analysis' then perform private.study_analysis_lock_job(sid,p_job_id,p_lease_token,p_resource_id);
 else perform private.study_lock_job(sid,p_job_id,p_lease_token,kind,subject,p_resource_id);end if;
  old_context:=current_setting('app.study.task_context',true); perform set_config('app.study.task_context','complete',true);
  result:=private.worker_record_job_result(p_job_id,p_lease_token,'failed',jsonb_build_object('schemaVersion','lca.study-job-receipt.v1','studyId',sid,'resourceType',p_resource_type,'resourceId',p_resource_id),
    'lca.study-job-receipt.v1',null,null,p_error_code,'Study task failed',null,null,null,false);
  perform set_config('app.study.task_context',coalesce(old_context,''),true); perform private.study_require((result->>'ok')::boolean,'FORBIDDEN');
  result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type',p_resource_type,'value',case when p_resource_type='analysis' then private.study_analysis_record(p_resource_id) else private.study_record(p_resource_type,p_resource_id) end));
  insert into private.study_service_receipts values(p_resource_type,sid,p_idempotency_key,p_job_id,p_lease_token,request,result); return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end $$;

create or replace function "api"."svc_study_task_reconcile_v1"("p_resource_type" "text", "p_resource_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_idempotency_key" "text", "p_artifact_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare sid uuid; bound_job uuid; j private.worker_jobs%rowtype; receipt private.study_service_receipts%rowtype; state text; resource jsonb;
begin
  perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
  if p_resource_type='methodAssessment' then
    perform private.study_require(exists(select 1 from private.study_method_assessments where id=p_resource_id and job_id=p_job_id),'REFERENCE_MISMATCH');
    return api.svc_study_method_assessment_reconcile_v1(p_resource_type,p_resource_id,p_job_id,p_lease_token,p_idempotency_key,p_artifact_id);end if;
  if p_resource_type='analysis' and exists(select 1 from private.study_advanced_analyses where id=p_resource_id and job_id=p_job_id) then return api.svc_study_analysis_advanced_reconcile_v1(p_resource_type,p_resource_id,p_job_id,p_lease_token,p_idempotency_key,p_artifact_id);end if;
  case p_resource_type
    when 'modelSourceAcquisition' then select study_id,job_id into sid,bound_job from private.study_source_acquisitions where id=p_resource_id;
    when 'modelPreparation' then select study_id,job_id into sid,bound_job from private.study_model_preparations where id=p_resource_id;
    when 'run' then select study_id,job_id into sid,bound_job from private.study_runs where id=p_resource_id;
 when 'analysis' then select study_id,job_id into sid,bound_job from private.study_analyses where id=p_resource_id;
    else perform private.study_require(false,'INVALID_REQUEST');
  end case;
  perform private.study_require(sid is not null and bound_job=p_job_id,'REFERENCE_MISMATCH');
  perform 1 from private.studies where id=sid for update;
  select * into j from private.worker_jobs where id=p_job_id for update;
 if p_resource_type='analysis' then
  perform private.study_require(j.job_kind='study.analysis' and j.worker_runtime='calculator' and j.worker_queue='solver' and j.subject_type='study' and j.subject_id=p_resource_id
   and j.payload_schema_version='study.analysis.request.v1' and j.payload_json=jsonb_build_object('schemaVersion','study.analysis.request.v1','studyId',sid,'analysisId',p_resource_id)
   and exists(select 1 from private.study_analyses a where a.id=p_resource_id and a.study_id=sid and a.job_id=p_job_id and a.requested_by=j.requested_by),'REFERENCE_MISMATCH');
 end if;
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



create function private.study_method_list(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare sid uuid:=(p_request->>'studyId')::uuid;actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');kind text:=p_request->>'kind';lim integer;
 selection jsonb;cur private.study_cursors%rowtype;afterid uuid;ids uuid[];resourceid uuid;items jsonb:='[]'::jsonb;v jsonb;nextid uuid;more boolean;epoch text;a private.study_method_assessments%rowtype;r private.study_report_revisions%rowtype;
begin
 perform private.study_method_envelope(p_request,false);
 perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','studyId','kind','limit','cursor']) and kind in ('methodAssessment','reportRevision')
 and jsonb_typeof(p_request->'limit')='number' and (p_request->>'limit')::numeric between 1 and 100 and trunc((p_request->>'limit')::numeric)=(p_request->>'limit')::numeric,'INVALID_REQUEST');lim:=(p_request->>'limit')::integer;
 perform private.study_authorize(sid,actor,client,'read');epoch:=private.study_access_epoch(actor,sid);selection:=p_request-'requestId'-'cursor';
 if p_request->'cursor'<>'null'::jsonb then
  select * into cur from private.study_cursors where id=(p_request->>'cursor')::uuid;
  perform private.study_require(found and cur.actor_id=actor and cur.client_id is not distinct from client and cur.selection=selection and cur.access_epoch=epoch and cur.expires_at>clock_timestamp(),'INVALID_REQUEST');afterid:=cur.after_id;
 end if;
 if kind='methodAssessment' then
  select array_agg(t.id order by t.id) into ids from(select id from private.study_method_assessments where study_id=sid and(afterid is null or id>afterid) order by id limit lim+1)t;
 else
  select array_agg(t.id order by t.id) into ids from(select id from private.study_report_revisions where study_id=sid and template_id='lca.study-method-report.v1' and(afterid is null or id>afterid) order by id limit lim+1)t;
 end if;more:=coalesce(cardinality(ids)>lim,false);
 foreach resourceid in array coalesce(ids[1:lim],'{}') loop
  if kind='methodAssessment' then
   select * into a from private.study_method_assessments where id=resourceid;perform private.study_advanced_rights(sid,a.baseline_run_id,actor,client);perform private.study_method_evidence_refs(sid,a.config,actor,client);v:=private.study_method_record(resourceid);
  else
   select * into r from private.study_report_revisions where id=resourceid;perform private.study_method_report_rights(sid,r.run_ids,r.method_assessment_ids,actor,client);v:=private.study_method_report_record(resourceid);
  end if;items:=items||jsonb_build_array(jsonb_build_object('type',kind,'value',v));
 end loop;
 if more then insert into private.study_cursors(actor_id,client_id,selection,access_epoch,after_id) values(actor,client,selection,epoch,ids[lim]) returning id into nextid;end if;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('type','resourcePage','studyId',sid,'kind',kind,'items',items,'nextCursor',nextid));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');end$$;
alter table private.study_artifact_read_intents drop constraint study_artifact_read_intents_family_check;
alter table private.study_artifact_read_intents add constraint study_artifact_read_intents_family_check check(family in('legacy','advanced','method'));
create function private.study_method_artifact_authorize(p_study uuid,p_ref jsonb,p_actor uuid,p_client text) returns jsonb
language plpgsql security definer set search_path='' as $$declare a private.study_artifacts%rowtype;m private.study_method_assessments%rowtype;begin
 perform private.study_authorize(p_study,p_actor,p_client,'read');perform private.study_require((select disclosure_enabled from private.study_runtime_config where singleton),'CAPABILITY_UNAVAILABLE');
 select * into a from private.study_artifacts where study_id=p_study and id=(p_ref->>'id')::uuid;perform private.study_require(found and a.ref=p_ref,'REFERENCE_MISMATCH');
 if p_ref->>'type'='methodAssessmentFacts' and p_ref->>'schemaVersion'='lca.study-method-assessment-facts.v1' then
  select * into m from private.study_method_assessments where study_id=p_study and facts_artifact_id=a.id;
  perform private.study_require(found and exists(select 1 from private.worker_jobs where id=m.job_id and status='completed'),'DISCLOSURE_DENIED');
  perform private.study_advanced_rights(p_study,m.baseline_run_id,p_actor,p_client);perform private.study_method_evidence_refs(p_study,m.config,p_actor,p_client);
 elsif p_ref->>'type'='methodEvidence' and p_ref->>'schemaVersion'='lca.study-method-evidence.v1' then
  perform private.study_require(exists(select 1 from private.study_method_evidence where study_id=p_study and artifact_id=a.id),'DISCLOSURE_DENIED');
 elsif p_ref->>'type' in('modelInput','runResult') then
  perform private.study_require(exists(select 1 from private.study_method_assessments ma join private.study_runs r on r.id=ma.baseline_run_id and r.study_id=ma.study_id
   join private.study_model_preparations p on p.id=r.preparation_id and p.study_id=r.study_id where ma.study_id=p_study and (a.id=r.result_artifact_id or a.id=p.input_artifact_id)),'DISCLOSURE_DENIED');
  return private.study_reporting_artifact_authorize(p_study,p_ref,p_actor,p_client);
 elsif p_ref->>'type'='reportContent' and p_ref->>'schemaVersion'='lca.study-method-report-content.v1' then
  perform private.study_method_report_artifact_authorize(p_study,p_ref,p_actor,p_client);
 else perform private.study_require(false,'DISCLOSURE_DENIED');end if;
 return jsonb_build_object('kind','artifactCapability','studyId',p_study,'artifactRef',a.ref,'storageBucket',a.bucket,'storageObjectPath',a.object_path);
end$$;
create function private.study_method_artifact_intent(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$declare sid uuid:=(p_request->>'studyId')::uuid;actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');i uuid;expiry timestamptz;begin
 perform private.study_method_envelope(p_request,false);perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','studyId','artifactRef']) and p_request->>'operation'='artifact.read','INVALID_REQUEST');
 perform private.study_method_artifact_authorize(sid,p_request->'artifactRef',actor,client);
 perform pg_advisory_xact_lock(hashtextextended('study-artifact-intent:'||actor::text,895));
 with expired as(select id from private.study_artifact_read_intents where expires_at<=clock_timestamp() order by expires_at,id limit 256 for update skip locked)
 delete from private.study_artifact_read_intents target using expired e where target.id=e.id;
 perform private.study_require((select count(*) from private.study_artifact_read_intents where actor_id=actor and expires_at>clock_timestamp())<64,'CAPABILITY_UNAVAILABLE');
 insert into private.study_artifact_read_intents(study_id,artifact_id,artifact_ref,actor_id,client_id,family)
 values(sid,(p_request->'artifactRef'->>'id')::uuid,p_request->'artifactRef',actor,client,'method') returning id,expires_at into i,expiry;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('kind','artifactReadIntent','intentId',i,'expiresAt',expiry,'studyId',sid,'artifactRef',p_request->'artifactRef'));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');end$$;
create or replace function api.svc_study_artifact_read_resolve_v1(p_intent_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$declare i private.study_artifact_read_intents%rowtype;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');select * into i from private.study_artifact_read_intents where id=p_intent_id;
 perform private.study_require(found and i.expires_at>clock_timestamp(),'CAPABILITY_UNAVAILABLE');
 return jsonb_build_object('ok',true,'data',case i.family when 'method' then private.study_method_artifact_authorize(i.study_id,i.artifact_ref,i.actor_id,i.client_id)
 when 'advanced' then private.study_advanced_artifact_authorize(i.study_id,i.artifact_ref,i.actor_id,i.client_id) else private.study_reporting_artifact_authorize(i.study_id,i.artifact_ref,i.actor_id,i.client_id) end);
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);end$$;
create function private.study_method_actions(p_resource jsonb,p_actor uuid,p_client text) returns jsonb
language plpgsql security definer set search_path='' as $$declare a private.study_method_assessments%rowtype;ops jsonb;role text;full_rights boolean:=false;begin
 perform private.study_require(private.study_keys(p_resource,array['type','id']) and p_resource->>'type'='methodAssessment' and private.study_method_uuid(p_resource->'id'),'INVALID_REQUEST');
 select * into a from private.study_method_assessments where id=(p_resource->>'id')::uuid;perform private.study_require(found,'FORBIDDEN');role:=private.study_authorize(a.study_id,p_actor,p_client,'read');
 ops:='["task.read"]'::jsonb;
 if role in('owner','editor') and private.study_client_allowed(p_client,'STUDY-WRITE-01') then ops:=ops||'["task.cancel"]'::jsonb;end if;
 begin
  perform private.study_advanced_rights(a.study_id,a.baseline_run_id,p_actor,p_client);perform private.study_method_evidence_refs(a.study_id,a.config,p_actor,p_client);full_rights:=true;
 exception when raise_exception then null;end;
 if full_rights then
  ops:=ops||'["method.assessment.read"]'::jsonb;
  if a.facts_artifact_id is not null and(select disclosure_enabled from private.study_runtime_config where singleton) then ops:=ops||'["artifact.read"]'::jsonb;end if;
 end if;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('type','actions','resource',p_resource,'actions',ops,
 'corePermissions',jsonb_build_object('read',true,'write',role in('owner','editor') and private.study_client_allowed(p_client,'STUDY-WRITE-01') and(select status='active'from private.studies where id=a.study_id)),'allowedMemberRoles','[]'::jsonb));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);end$$;
create function api.cmd_study_method_v1(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$begin
 perform private.study_method_envelope(p_request,true);perform private.study_require(private.study_client_allowed(nullif(auth.jwt()->>'client_id',''),'STUDY-WRITE-01'),'FORBIDDEN');
 case p_request->>'operation'
 when 'method.assessment.request' then return private.study_method_request(p_request);
 when 'method.evidence.create' then return private.study_method_evidence_create(p_request);
 when 'task.cancel' then return private.study_method_task(p_request);
 when 'report.create','report.save','report.freeze' then return private.study_method_report_command(p_request);
 else return jsonb_build_object('ok',false,'code','CAPABILITY_UNAVAILABLE');end case;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);end$$;
create function api.qry_study_method_v1(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$declare actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');a private.study_method_assessments%rowtype;e private.study_method_evidence%rowtype;r private.study_report_revisions%rowtype;
 cfg private.study_method_config%rowtype;ops jsonb;profiles jsonb:='[]'::jsonb;begin
 perform private.study_method_envelope(p_request,false);perform private.study_require(private.study_client_allowed(client,'STUDY-READ-01'),'FORBIDDEN');
 case p_request->>'operation'
 when 'capability.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation']),'INVALID_REQUEST');select * into cfg from private.study_method_config where singleton;
  ops:='["capability.read","method.assessment.read","method.evidence.read","task.read","report.read","study.resources.list","resource.actions"]'::jsonb;
  if private.study_client_allowed(client,'STUDY-WRITE-01') then
   ops:=ops||'["task.cancel"]'::jsonb;
   if cfg.execution_enabled then ops:=ops||'["method.evidence.create"]'::jsonb;end if;
  end if;
  if private.study_client_allowed(client,'DB-CORE-READ-01') then
   if(select disclosure_enabled from private.study_runtime_config where singleton) then ops:=ops||'["artifact.read"]'::jsonb;end if;
   if private.study_client_allowed(client,'STUDY-WRITE-01') then
    if cfg.execution_enabled then ops:=ops||'["method.assessment.request"]'::jsonb;end if;
    if cfg.report_enabled then ops:=ops||'["report.create","report.save","report.freeze"]'::jsonb;end if;
   end if;
  end if;
  if cfg.execution_enabled then profiles:='["lca.study-method-pef-2021-ef31-cement-intermediate.v1"]'::jsonb;end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','capabilities','contractVersion','6.0.0','runtimeEnabled',cfg.execution_enabled or cfg.report_enabled,'operations',ops,'methodProfiles',profiles,
   'reportTemplates',case when cfg.report_enabled then '["lca.study-method-report.v1"]'::jsonb else '[]'::jsonb end,
   'limits',jsonb_build_object('maxEvidenceRefs',coalesce(cfg.max_evidence_refs,0),'maxSelectedFactorRecords',coalesce(cfg.max_selected_factor_records,0),'maxFactsBytes',4194304,'maxProjectionBytes',2000000)));
 when 'method.assessment.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','assessmentId']),'INVALID_REQUEST');select * into a from private.study_method_assessments where id=(p_request->>'assessmentId')::uuid;
  perform private.study_require(found,'FORBIDDEN');perform private.study_advanced_rights(a.study_id,a.baseline_run_id,actor,client);perform private.study_method_evidence_refs(a.study_id,a.config,actor,client);
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','methodAssessment','value',private.study_method_record(a.id)));
 when 'method.evidence.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','evidenceId']),'INVALID_REQUEST');select * into e from private.study_method_evidence where id=(p_request->>'evidenceId')::uuid;
  perform private.study_require(found,'FORBIDDEN');perform private.study_authorize(e.study_id,actor,client,'read');return jsonb_build_object('ok',true,'data',jsonb_build_object('type','methodEvidence','value',private.study_method_evidence_record(e.id)));
 when 'report.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','reportRevisionId']),'INVALID_REQUEST');select * into r from private.study_report_revisions where id=(p_request->>'reportRevisionId')::uuid;
  perform private.study_require(found and r.template_id='lca.study-method-report.v1','FORBIDDEN');perform private.study_method_report_rights(r.study_id,r.run_ids,r.method_assessment_ids,actor,client);
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','reportRevision','value',private.study_method_report_record(r.id)));
 when 'resource.actions' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','resource']),'INVALID_REQUEST');
  if p_request->'resource'->>'type'='methodAssessment' then return private.study_method_actions(p_request->'resource',actor,client);end if;
  return api.qry_study_method_review_v1(p_request);
 when 'task.read' then return private.study_method_task(p_request);
 when 'study.resources.list' then return private.study_method_list(p_request);
 when 'artifact.read' then return private.study_method_artifact_intent(p_request);
 else return jsonb_build_object('ok',false,'code','CAPABILITY_UNAVAILABLE');end case;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');end$$;

do $$declare f record;t text;ident text;begin
 foreach t in array array['study_method_config','study_method_evidence','study_method_evidence_intents','study_method_assessments','study_report_method_assessments','study_method_review_config'] loop
  execute format('alter table private.%I enable row level security',t);execute format('alter table private.%I force row level security',t);execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);
 end loop;
 for f in select p.oid::regprocedure id,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname=any(array['study_method_actions','study_method_artifact_authorize','study_method_artifact_intent','study_method_artifact_valid','study_method_config_hash','study_method_config_valid','study_method_envelope','study_method_evidence_body_valid','study_method_evidence_create','study_method_evidence_intent_check','study_method_evidence_plain','study_method_evidence_record','study_method_evidence_refs','study_method_immutable','study_method_list','study_method_lock_job','study_method_module','study_method_record','study_method_report_artifact_authorize','study_method_report_binding','study_method_report_command','study_method_report_content_valid','study_method_report_intent_check','study_method_report_record','study_method_report_rights','study_method_report_validation_check','study_method_request','study_method_review_actions','study_method_review_envelope','study_method_review_intent_check','study_method_review_new_intent','study_method_task','study_method_text','study_method_uint','study_method_uuid']) loop
  execute format('revoke all on function %s from public,anon,authenticated,service_role',f.id);
 end loop;
 for f in select p.oid::regprocedure id,p.proname,pg_catalog.oidvectortypes(p.proargtypes) args from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='api' and p.proname in('cmd_study_method_v1','qry_study_method_v1','svc_study_method_configure_v1','svc_study_method_assessment_read_input_v1','svc_study_method_assessment_complete_v1','svc_study_method_assessment_fail_v1','svc_study_method_assessment_reconcile_v1','svc_study_method_evidence_intent_resolve_v1','svc_study_method_evidence_intent_consume_v1','svc_study_method_evidence_intent_reconcile_v1','svc_study_report_method_intent_resolve_v1','svc_study_report_method_intent_consume_v1','svc_study_report_method_intent_reconcile_v1','svc_study_review_method_configure_v1','cmd_study_method_review_v1','qry_study_method_review_v1','svc_study_review_method_intent_resolve_v1','svc_study_review_method_intent_consume_v1','svc_study_review_method_intent_reconcile_v1') loop
  execute format('revoke all on function %s from public,anon,authenticated,service_role',f.id);execute format('grant execute on function %s to %I',f.id,case when f.proname like 'svc_%' then 'service_role' else 'authenticated' end);
  ident:=format('api.%I(%s)',f.proname,f.args);insert into private.api_capability_grants values(ident,case when f.proname like 'svc_%' then 'STUDY-SERVICE-01' when f.proname like 'cmd_%' then 'STUDY-WRITE-01' else 'STUDY-READ-01' end,false,f.proname not like 'svc_%',f.proname like 'svc_%');
 end loop;
end$$;
notify pgrst,'reload schema';
commit;
