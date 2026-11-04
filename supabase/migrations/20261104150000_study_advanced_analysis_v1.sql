-- Database #909: negotiated V5 advanced analysis and report family.
-- New admission is independently default-off. No environment/client grants.
begin;
create or replace function private.study_advanced_number(p_value jsonb) returns text
language plpgsql immutable set search_path='' set extra_float_digits=3 as $$
declare v double precision;t text;negative boolean;digits text;point integer;zero_count integer;exponent integer;result text;
 raw bytea;fraction bigint;binary_exponent integer;i integer;power_value numeric:=1;factor numeric;remaining integer;exact_value numeric;rounded numeric;quantum numeric;scale integer;candidate numeric;best numeric;best_distance numeric;distance numeric;
begin
 if not private.study_text(p_value,64,'^-?(0|[1-9][0-9]*)(\.[0-9]*[1-9])?(e-?[1-9][0-9]{0,2})?$') then return null;end if;
 v:=(p_value#>>'{}')::double precision;
 if v in ('Infinity'::double precision,'-Infinity'::double precision,'NaN'::double precision) then return null;end if;
 if v=0 then return case when p_value#>>'{}'='0' then '0' end;end if;
 negative:=v<0;raw:=float8send(abs(v));binary_exponent:=((get_byte(raw,0)&127)*16+(get_byte(raw,1)>>4));fraction:=(get_byte(raw,1)&15)::bigint;
 for byte_index in 2..7 loop fraction:=fraction*256+get_byte(raw,byte_index);end loop;
 if binary_exponent=0 then binary_exponent:=-1074;else fraction:=fraction+4503599627370496;binary_exponent:=binary_exponent-1075;end if;
 -- Construct the exact finite binary value as decimal integer/scale. PostgreSQL's
 -- own float8 text chooses different shortest spellings at some boundaries.
 remaining:=abs(binary_exponent);factor:=case when binary_exponent<0 then 5 else 2 end;
 while remaining>0 loop
  if remaining%2=1 then power_value:=power_value*factor;end if;
  remaining:=remaining/2;if remaining>0 then factor:=factor*factor;end if;
 end loop;
 t:=(fraction::numeric*power_value)::text;
 if binary_exponent<0 then
  i:=-binary_exponent;
  if length(t)<=i then t:='0.'||repeat('0',i-length(t))||t;else t:=left(t,length(t)-i)||'.'||right(t,i);end if;
 end if;exact_value:=t::numeric;
 point:=position('.' in t);if point=0 then point:=length(t)+1;end if;
 digits:=replace(t,'.','');zero_count:=length(digits)-length(ltrim(digits,'0'));exponent:=point-zero_count-2;
 -- Binary powers have asymmetric neighboring intervals. At the shortest
 -- decimal precision inspect the nearest coefficient and both adjacent ones;
 -- select only roundtripping candidates by exact distance, then even ties.
 for precision in 1..17 loop
  scale:=precision-1-exponent;rounded:=round(exact_value,scale);quantum:=('1e'||(-scale)::text)::numeric;best:=null;best_distance:=null;
  foreach candidate in array array[rounded,rounded-quantum,rounded+quantum] loop
   if candidate<=0 then continue;end if;
   begin
    if candidate::double precision=abs(v) then
     distance:=abs(candidate-exact_value);
     if best is null or distance<best_distance or (distance=best_distance and mod(candidate*(('1e'||scale::text)::numeric),2)=0 and mod(best*(('1e'||scale::text)::numeric),2)<>0) then
      best:=candidate;best_distance:=distance;
     end if;
    end if;
   exception when numeric_value_out_of_range then null;end;
  end loop;
  if best is not null then rounded:=best;exit;end if;
 end loop;
 if best is null then return null;end if;
 t:=rounded::text;point:=position('.' in t);if point=0 then point:=length(t)+1;end if;
 digits:=replace(t,'.','');zero_count:=length(digits)-length(ltrim(digits,'0'));digits:=rtrim(ltrim(digits,'0'),'0');exponent:=point-zero_count-2;
 if exponent between -5 and 15 then result:=case when position('.' in t)>0 then rtrim(rtrim(t,'0'),'.') else t end;
 else result:=left(digits,1)||case when length(digits)>1 then '.'||substr(digits,2) else '' end||'e'||exponent::text;end if;
 if negative then result:='-'||result;end if;return case when result=p_value#>>'{}' then result end;
exception when invalid_text_representation or numeric_value_out_of_range then return null;
end$$;
create function private.study_advanced_config_valid(p_config jsonb) returns boolean
language plpgsql immutable set search_path='' as $$
declare x jsonb;row jsonb;v jsonb;seen text[]:='{}'::text[];n integer;low double precision;high double precision;base double precision;kind text:=p_config->>'kind';
begin
 if octet_length(p_config::text)>262144 or p_config->>'schemaVersion' is distinct from 'lca.study-analysis-config.v2'
 or not private.study_text(p_config->'baselineRunId',36,'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
 or jsonb_typeof(p_config->'parameters') is distinct from 'array' then return false;end if;
 if kind='sensitivityOat' then
  if not private.study_keys(p_config,array['kind','schemaVersion','baselineRunId','parameters']) then return false;end if;
 elsif kind='uncertainty' then
  if not private.study_keys(p_config,array['kind','schemaVersion','baselineRunId','parameters','design','sampleCount','seedHex','generator'])
  or p_config->>'generator' is distinct from 'study.uncertainty.hmac-drbg-sha256.v1'
  or not private.study_text(p_config->'seedHex',64,'^[0-9a-f]{64}$') or jsonb_typeof(p_config->'sampleCount') is distinct from 'number'
  or (p_config->>'sampleCount')::numeric not between 2 and 4294967295 or trunc((p_config->>'sampleCount')::numeric)<>(p_config->>'sampleCount')::numeric then return false;end if;
 else return false;end if;
 if jsonb_array_length(p_config->'parameters')<1 then return false;end if;
 for x in select * from jsonb_array_elements(p_config->'parameters') loop
  if not private.study_keys(x,array['path','unit','baselineAmount','low','high'])
  or not private.study_text(x->'path',256,'^/instances/[^/]+/exchanges/[^/]+/amount$') or octet_length(x->>'path')>256
  or not private.study_text(x->'unit',256) or octet_length(x->>'unit')>256 or (x->>'path')=any(seen)
  or private.study_advanced_number(x->'low') is null or private.study_advanced_number(x->'high') is null or private.study_advanced_number(x->'baselineAmount') is null then return false;end if;
  low:=(x->>'low')::double precision;high:=(x->>'high')::double precision;base:=(x->>'baselineAmount')::double precision;
  if not (low<high and low<=base and base<=high) or (high-low)='Infinity'::double precision then return false;end if;seen:=seen||(x->>'path');
 end loop;
 if kind='uncertainty' then
  if p_config->'design'->>'kind'='independentUniform' then
   if not private.study_keys(p_config->'design',array['kind','independenceDeclared']) or p_config->'design'->'independenceDeclared' is distinct from 'true'::jsonb then return false;end if;
  elsif p_config->'design'->>'kind'='jointEmpirical' then
   if not private.study_keys(p_config->'design',array['kind','rows']) or jsonb_typeof(p_config->'design'->'rows') is distinct from 'array' then return false;end if;
   if jsonb_array_length(p_config->'design'->'rows')<1 then return false;end if;
   for row in select * from jsonb_array_elements(p_config->'design'->'rows') loop
    if jsonb_typeof(row)<>'array' then return false;end if;
    if jsonb_array_length(row)<>cardinality(seen) then return false;end if;
    n:=0;for v in select * from jsonb_array_elements(row) loop
     if private.study_advanced_number(v) is null then return false;end if;
     x:=p_config->'parameters'->n;
     if (v#>>'{}')::double precision<(x->>'low')::double precision or (v#>>'{}')::double precision>(x->>'high')::double precision then return false;end if;n:=n+1;
    end loop;
   end loop;
  else return false;end if;
 end if;return true;
exception when invalid_text_representation or numeric_value_out_of_range or invalid_parameter_value then return false;
end$$;
create function private.study_advanced_config_hash(p_config jsonb) returns text
language sql stable set search_path='' as $$select private.study_reporting_digest('study.analysis-config.v2',p_config)$$;
create table private.study_advanced_config (
 singleton boolean primary key default true check(singleton),revision bigint not null default 1 check(revision>0),
 sensitivity_enabled boolean not null default false,uncertainty_enabled boolean not null default false,report_enabled boolean not null default false,
 max_parameters integer check(max_parameters>0),max_samples bigint check(max_samples between 2 and 4294967295),qualification_evidence_ref text,
 check(not(sensitivity_enabled or uncertainty_enabled or report_enabled) or (max_parameters is not null and max_samples is not null and private.study_text(to_jsonb(qualification_evidence_ref),2048)))
);
insert into private.study_advanced_config(singleton) values(true);
create table private.study_advanced_analyses (
 id uuid primary key,study_id uuid not null references private.studies(id),
 profile_id text not null,config jsonb not null check(private.study_advanced_config_valid(config)),config_hash text not null,
 baseline_run_id uuid not null,source_snapshot_id uuid not null,
 job_id uuid not null unique references private.worker_jobs(id),requested_by uuid not null references auth.users(id),requested_client_id text,
 facts_artifact_id uuid,unique(study_id,id),
 foreign key(study_id,baseline_run_id) references private.study_runs(study_id,id),
 foreign key(study_id,source_snapshot_id) references private.study_source_snapshots(study_id,id),
 foreign key(study_id,facts_artifact_id) references private.study_artifacts(study_id,id),
 check(config_hash=private.study_advanced_config_hash(config)),
 check(config->>'baselineRunId'=baseline_run_id::text),
 check((profile_id='lca.study-sensitivity-oat.v1' and config->>'kind'='sensitivityOat') or (profile_id='lca.study-uncertainty-bounded.v1' and config->>'kind'='uncertainty'))
);
create index study_advanced_analysis_study_idx on private.study_advanced_analyses(study_id,id);
create index study_advanced_analysis_actor_idx on private.study_advanced_analyses(requested_by);
create index study_advanced_analysis_baseline_idx on private.study_advanced_analyses(study_id,baseline_run_id);
create index study_advanced_analysis_snapshot_idx on private.study_advanced_analyses(study_id,source_snapshot_id);
create index study_advanced_analysis_facts_idx on private.study_advanced_analyses(study_id,facts_artifact_id);
create function private.study_advanced_immutable() returns trigger language plpgsql set search_path='' as $$begin
 if tg_op='DELETE' or (to_jsonb(old)-'facts_artifact_id') is distinct from (to_jsonb(new)-'facts_artifact_id') or old.facts_artifact_id is not null then raise exception 'FROZEN_REVISION';end if;return new;
end$$;
create trigger study_advanced_immutable before update or delete on private.study_advanced_analyses for each row execute function private.study_advanced_immutable();
insert into private.worker_job_kinds(job_kind,worker_runtime,worker_queue,default_visibility,payload_schema_version,result_schema_version,user_visible,description)
 values('study.analysis_advanced','calculator','solver','user','study.analysis_advanced.request.v1','lca.study-job-receipt.v1',false,'V5 bounded advanced analysis; independent explicit admission');

create function private.study_advanced_record(p_id uuid) returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('analysisId',a.id,'studyId',a.study_id,'profileId',a.profile_id,'config',a.config,'configHash',a.config_hash,
 'execution',jsonb_build_object('jobId',a.job_id,'status',j.status),'factsRef',case when j.status='completed' then f.ref else null end)
 from private.study_advanced_analyses a join private.worker_jobs j on j.id=a.job_id left join private.study_artifacts f on f.id=a.facts_artifact_id where a.id=p_id
$$;
create function private.study_advanced_rights(p_study uuid,p_run uuid,p_actor uuid,p_client text) returns uuid
language plpgsql security definer set search_path='' as $$declare snapshot uuid;begin
 perform private.study_analysis_rights(p_study,jsonb_build_object('runIds',jsonb_build_array(p_run)),p_actor,p_client);
 select private.study_preparation_snapshot(p_study,preparation_id) into snapshot from private.study_runs where study_id=p_study and id=p_run;
 perform private.study_require(snapshot is not null,'REFERENCE_MISMATCH');return snapshot;
end$$;
create function private.study_advanced_baseline(p_study uuid,p_run uuid) returns jsonb
language sql security definer set search_path='' as $$select jsonb_build_object('run',private.study_record('run',r.id),'revision',private.study_record('studyRevision',r.study_revision_id),
 'scenario',private.study_record('scenarioRevision',r.scenario_id),'preparation',private.study_record('modelPreparation',r.preparation_id),
 'preparedArtifact',private.study_private_artifact(p_study,p.input_artifact_id),'resultArtifact',private.study_private_artifact(p_study,r.result_artifact_id))
 from private.study_runs r join private.study_model_preparations p on p.study_id=r.study_id and p.id=r.preparation_id where r.study_id=p_study and r.id=p_run$$;
create function private.study_advanced_lock_job(p_study uuid,p_job uuid,p_token uuid,p_analysis uuid) returns void
language plpgsql security definer set search_path='' as $$begin
 perform private.study_lock_job(p_study,p_job,p_token,'study.analysis_advanced','analysisId',p_analysis);
 perform private.study_require(exists(select 1 from private.worker_jobs j join private.study_advanced_analyses a on a.job_id=j.id
 where a.id=p_analysis and a.study_id=p_study and j.id=p_job and j.subject_type='study' and j.subject_id=p_analysis and j.worker_queue='solver'
 and j.payload_schema_version='study.analysis_advanced.request.v1' and j.requested_by=a.requested_by
 and j.payload_json=jsonb_build_object('schemaVersion','study.analysis_advanced.request.v1','studyId',p_study,'analysisId',p_analysis)),'REFERENCE_MISMATCH');
end$$;
create function private.study_advanced_request(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' set statement_timeout='15s' as $$
declare sid uuid:=(p_request->>'studyId')::uuid;actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');req jsonb:=p_request-'schemaVersion'-'requestId'-'idempotencyKey';
 previous private.study_command_receipts%rowtype;cfg private.study_advanced_config%rowtype;s private.studies%rowtype;aid uuid:=gen_random_uuid();job uuid;snapshot uuid;result jsonb;old_role text;old_context text;
begin
 perform private.study_advanced_envelope(p_request,true);
 perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','idempotencyKey','operation','studyId','profileId','config','configHash'])
 and p_request->>'operation'='analysis.request' and private.study_advanced_config_valid(p_request->'config'),'INVALID_REQUEST');
 perform private.study_require(p_request->>'profileId'=case p_request->'config'->>'kind' when 'sensitivityOat' then 'lca.study-sensitivity-oat.v1' else 'lca.study-uncertainty-bounded.v1' end
 and p_request->>'configHash'=private.study_advanced_config_hash(p_request->'config'),'REFERENCE_MISMATCH');
 perform private.study_authorize(sid,actor,client,'write');snapshot:=private.study_advanced_rights(sid,(p_request->'config'->>'baselineRunId')::uuid,actor,client);
 select * into previous from private.study_command_receipts where actor_id=actor and operation='analysis.advanced.request' and scope=sid::text and idempotency_key=p_request->>'idempotencyKey';
 if found then perform private.study_require(previous.request=req,'IDEMPOTENCY_CONFLICT');return previous.response;end if;
 perform private.study_analysis_require_current(sid,jsonb_build_object('runIds',jsonb_build_array(p_request->'config'->'baselineRunId')));
 select * into s from private.studies where id=sid;perform private.study_require(s.status='active','FROZEN_REVISION');select * into cfg from private.study_advanced_config where singleton for share;
 perform private.study_require(case p_request->'config'->>'kind' when 'sensitivityOat' then cfg.sensitivity_enabled else cfg.uncertainty_enabled end,'CAPABILITY_UNAVAILABLE');
 perform private.study_require(jsonb_array_length(p_request->'config'->'parameters')<=cfg.max_parameters
 and (p_request->'config'->>'kind'<>'uncertainty' or (p_request->'config'->>'sampleCount')::bigint<=cfg.max_samples),'CAPABILITY_UNAVAILABLE');
 old_role:=current_setting('request.jwt.claim.role',true);old_context:=current_setting('app.study.task_context',true);perform set_config('request.jwt.claim.role','service_role',true);perform set_config('app.study.task_context','enqueue',true);
 result:=private.worker_enqueue_job('study.analysis_advanced',jsonb_build_object('schemaVersion','study.analysis_advanced.request.v1','studyId',sid,'analysisId',aid),
 'study.analysis_advanced.request.v1','study',aid,null,actor,'user',s.team_id,actor::text||':'||sid::text||':study.analysis_advanced:'||(p_request->>'idempotencyKey'),
 private.study_content_hash('lca.study-job-request.v1',req),null,0,null,null,'user');
 perform set_config('request.jwt.claim.role',coalesce(old_role,''),true);perform set_config('app.study.task_context',coalesce(old_context,''),true);
 perform private.study_require((result->>'ok')::boolean,'CAPABILITY_UNAVAILABLE');job:=(result->'data'->>'id')::uuid;
 insert into private.study_advanced_analyses(id,study_id,profile_id,config,config_hash,baseline_run_id,source_snapshot_id,job_id,requested_by,requested_client_id)
 values(aid,sid,p_request->>'profileId',p_request->'config',p_request->>'configHash',(p_request->'config'->>'baselineRunId')::uuid,snapshot,job,actor,client);
 result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','analysis','value',private.study_advanced_record(aid)));
 insert into private.study_command_receipts values(actor,'analysis.advanced.request',sid::text,p_request->>'idempotencyKey',req,result,clock_timestamp());return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range or not_null_violation or check_violation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');end$$;
create function api.svc_study_analysis_advanced_read_input_v1(p_analysis_id uuid,p_job_id uuid,p_lease_token uuid) returns jsonb
language plpgsql security definer set search_path='' as $$declare a private.study_advanced_analyses%rowtype;snapshot uuid;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');select * into a from private.study_advanced_analyses where id=p_analysis_id;
 perform private.study_require(found and a.job_id=p_job_id,'REFERENCE_MISMATCH');perform private.study_authorize(a.study_id,a.requested_by,a.requested_client_id,'write');
 snapshot:=private.study_advanced_rights(a.study_id,a.baseline_run_id,a.requested_by,a.requested_client_id);perform private.study_require(snapshot=a.source_snapshot_id,'REFERENCE_MISMATCH');
 perform private.study_analysis_require_current(a.study_id,jsonb_build_object('runIds',jsonb_build_array(a.baseline_run_id)));
 perform private.study_advanced_lock_job(a.study_id,p_job_id,p_lease_token,a.id);
 return jsonb_build_object('ok',true,'data',jsonb_build_object('schemaVersion','lca.study-analysis-input.v2','analysis',private.study_advanced_record(a.id)-'factsRef',
 'baseline',private.study_advanced_baseline(a.study_id,a.baseline_run_id),'sourceSnapshot',private.study_record('modelSourceSnapshot',snapshot),
 'sourceArtifact',private.study_private_artifact(a.study_id,(select artifact_id from private.study_source_snapshots where id=snapshot))));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);end$$;
create function api.svc_study_analysis_advanced_complete_v1(p_analysis_id uuid,p_job_id uuid,p_lease_token uuid,p_completion jsonb,p_idempotency_key text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a private.study_advanced_analyses%rowtype;previous private.study_service_receipts%rowtype;request jsonb;result jsonb;artifact uuid;old_context text;snapshot uuid;
begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');perform private.study_require(private.study_text(to_jsonb(p_idempotency_key),128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');
 select * into a from private.study_advanced_analyses where id=p_analysis_id;perform private.study_require(found and a.job_id=p_job_id,'REFERENCE_MISMATCH');
 perform private.study_authorize(a.study_id,a.requested_by,a.requested_client_id,'write');snapshot:=private.study_advanced_rights(a.study_id,a.baseline_run_id,a.requested_by,a.requested_client_id);
 perform private.study_require(snapshot=a.source_snapshot_id,'REFERENCE_MISMATCH');request:=jsonb_build_object('id',p_analysis_id,'jobId',p_job_id,'leaseToken',p_lease_token,'completion',p_completion);
 select * into previous from private.study_service_receipts where operation='analysisAdvanced' and study_id=a.study_id and idempotency_key=p_idempotency_key;
 if found then perform private.study_require(previous.request=request and previous.job_id=p_job_id and previous.lease_token=p_lease_token,'IDEMPOTENCY_CONFLICT');return previous.response;end if;
 perform private.study_analysis_require_current(a.study_id,jsonb_build_object('runIds',jsonb_build_array(a.baseline_run_id)));perform private.study_advanced_lock_job(a.study_id,p_job_id,p_lease_token,a.id);
 select * into a from private.study_advanced_analyses where id=p_analysis_id for update;
 perform private.study_require(a.facts_artifact_id is null and private.study_keys(p_completion,array['profileId','configHash','factsRef','storageBucket','storageObjectPath'])
 and p_completion->>'profileId'=a.profile_id and p_completion->>'configHash'=a.config_hash and p_completion->'factsRef'->>'schemaVersion'='lca.study-analysis-facts.v2'
 and p_completion->'factsRef'->>'mediaType'='application/json','REFERENCE_MISMATCH');
 artifact:=private.study_store_artifact(a.study_id,p_completion->'factsRef',p_completion->>'storageBucket',p_completion->>'storageObjectPath','analysisFacts');
 update private.study_advanced_analyses set facts_artifact_id=artifact where id=a.id;old_context:=current_setting('app.study.task_context',true);perform set_config('app.study.task_context','complete',true);
 result:=private.worker_record_job_result(p_job_id,p_lease_token,'completed',jsonb_build_object('schemaVersion','lca.study-job-receipt.v1','studyId',a.study_id,'resourceType','analysis','resourceId',a.id),'lca.study-job-receipt.v1',p_completion->'factsRef');
 perform set_config('app.study.task_context',coalesce(old_context,''),true);perform private.study_require((result->>'ok')::boolean,'FORBIDDEN');
 result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','analysis','value',private.study_advanced_record(a.id)));
 insert into private.study_service_receipts values('analysisAdvanced',a.study_id,p_idempotency_key,p_job_id,p_lease_token,request,result);return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or numeric_value_out_of_range or not_null_violation or check_violation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');end$$;

create function api.svc_study_advanced_configure_v1(p_expected_revision bigint,p_configuration jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$declare cfg private.study_advanced_config%rowtype;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 perform private.study_require(private.study_keys(p_configuration,array['sensitivityEnabled','uncertaintyEnabled','reportEnabled','maxParameters','maxSamples','qualificationEvidenceRef'])
 and jsonb_typeof(p_configuration->'sensitivityEnabled')='boolean' and jsonb_typeof(p_configuration->'uncertaintyEnabled')='boolean' and jsonb_typeof(p_configuration->'reportEnabled')='boolean'
 and (p_configuration->'maxParameters'='null'::jsonb or (jsonb_typeof(p_configuration->'maxParameters')='number' and (p_configuration->>'maxParameters')::numeric between 1 and 2147483647 and trunc((p_configuration->>'maxParameters')::numeric)=(p_configuration->>'maxParameters')::numeric))
 and (p_configuration->'maxSamples'='null'::jsonb or (jsonb_typeof(p_configuration->'maxSamples')='number' and (p_configuration->>'maxSamples')::numeric between 2 and 4294967295 and trunc((p_configuration->>'maxSamples')::numeric)=(p_configuration->>'maxSamples')::numeric))
 and (p_configuration->'qualificationEvidenceRef'='null'::jsonb or private.study_text(p_configuration->'qualificationEvidenceRef',2048)),'INVALID_REQUEST');
 select * into cfg from private.study_advanced_config where singleton for update;perform private.study_require(cfg.revision=p_expected_revision,'REVISION_CONFLICT');
 update private.study_advanced_config set revision=revision+1,sensitivity_enabled=(p_configuration->>'sensitivityEnabled')::boolean,
 uncertainty_enabled=(p_configuration->>'uncertaintyEnabled')::boolean,report_enabled=(p_configuration->>'reportEnabled')::boolean,
 max_parameters=(p_configuration->>'maxParameters')::integer,max_samples=(p_configuration->>'maxSamples')::bigint,qualification_evidence_ref=p_configuration->>'qualificationEvidenceRef' where singleton;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('revision',cfg.revision+1));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');end$$;

create or replace function "private"."study_advanced_task"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare sid uuid:=(p_request->>'studyId')::uuid; actor uuid:=auth.uid(); client text:=nullif(auth.jwt()->>'client_id','');
 op text:=p_request->>'operation'; a private.study_advanced_analyses%rowtype; j private.worker_jobs%rowtype; result jsonb;
 old_role text; old_context text; previous private.study_command_receipts%rowtype; req jsonb:=p_request-'schemaVersion'-'requestId'-'idempotencyKey';
begin
 perform private.study_advanced_envelope(p_request,op='task.cancel');
 perform private.study_require(private.study_keys(p_request->'resource',array['type','id']) and p_request->'resource'->>'type'='analysis','INVALID_REQUEST');
 perform private.study_authorize(sid,actor,client,case when op='task.cancel' then 'write' else 'read' end);
 select * into a from private.study_advanced_analyses where study_id=sid and id=(p_request->'resource'->>'id')::uuid;
 perform private.study_require(found,'FORBIDDEN');
 -- Minimal status/cancellation stays available after source withdrawal and
 -- admission shutdown. No source, result, payload or raw diagnostic is projected.
 perform private.study_require(exists(select 1 from private.worker_jobs bound_job where bound_job.id=a.job_id
 and bound_job.job_kind='study.analysis_advanced' and bound_job.worker_runtime='calculator' and bound_job.worker_queue='solver'
 and bound_job.subject_type='study' and bound_job.subject_id=a.id and bound_job.requested_by=a.requested_by
 and bound_job.payload_schema_version='study.analysis_advanced.request.v1'
 and bound_job.payload_json=jsonb_build_object('schemaVersion','study.analysis_advanced.request.v1','studyId',sid,'analysisId',a.id)),'REFERENCE_MISMATCH');
 if op='task.cancel' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','idempotencyKey','studyId','resource','reason']) and private.study_text(p_request->'reason',512),'INVALID_REQUEST');
  select * into previous from private.study_command_receipts where actor_id=actor and operation='advanced.'||op and scope=sid::text and idempotency_key=p_request->>'idempotencyKey';
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
 if op='task.cancel' then insert into private.study_command_receipts values(actor,'advanced.'||op,sid::text,p_request->>'idempotencyKey',req,result,clock_timestamp()); end if;
 return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
end $$;


create or replace function "api"."svc_study_analysis_advanced_fail_v1"("p_resource_type" "text", "p_resource_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_error_code" "text", "p_idempotency_key" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare sid uuid; job uuid; kind text; subject text; result jsonb; old_context text; receipt private.study_service_receipts%rowtype; request jsonb;
begin
  perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
  perform private.study_require(p_error_code=any(array['source_invalid','boundary_undeclared','normalization_underflow','normalization_overflow','numeric_invalid','resource_limit','model_not_solvable','native_execution_failed','job_timeout','job_lease_lost','runtime_unavailable','runtime_failed']) and length(p_idempotency_key) between 1 and 128,'INVALID_REQUEST');
  perform private.study_require(p_resource_type='analysis','INVALID_REQUEST');
  case p_resource_type
    when 'modelSourceAcquisition' then select study_id,job_id into sid,job from private.study_source_acquisitions where id=p_resource_id; kind:='study.source_acquire'; subject:='acquisitionId';
    when 'modelPreparation' then select study_id,job_id into sid,job from private.study_model_preparations where id=p_resource_id; kind:='study.model_prepare'; subject:='preparationId';
    when 'run' then select study_id,job_id into sid,job from private.study_runs where id=p_resource_id; kind:='study.run'; subject:='runId';
 when 'analysis' then select study_id,job_id into sid,job from private.study_advanced_analyses where id=p_resource_id; kind:='study.analysis_advanced'; subject:='analysisId';
    else perform private.study_require(false,'INVALID_REQUEST');
  end case;
  perform private.study_require(sid is not null and job=p_job_id,'REFERENCE_MISMATCH'); perform 1 from private.studies where id=sid for update;
  request:=jsonb_build_object('id',p_resource_id,'jobId',p_job_id,'leaseToken',p_lease_token,'errorCode',p_error_code);
  select * into receipt from private.study_service_receipts where operation='analysisAdvanced' and study_id=sid and idempotency_key=p_idempotency_key;
  if found then perform private.study_require(receipt.request=request,'IDEMPOTENCY_CONFLICT'); return receipt.response; end if;
  if p_resource_type='analysis' then perform private.study_advanced_lock_job(sid,p_job_id,p_lease_token,p_resource_id);
 else perform private.study_lock_job(sid,p_job_id,p_lease_token,kind,subject,p_resource_id);end if;
  old_context:=current_setting('app.study.task_context',true); perform set_config('app.study.task_context','complete',true);
  result:=private.worker_record_job_result(p_job_id,p_lease_token,'failed',jsonb_build_object('schemaVersion','lca.study-job-receipt.v1','studyId',sid,'resourceType',p_resource_type,'resourceId',p_resource_id),
    'lca.study-job-receipt.v1',null,null,p_error_code,'Study task failed',null,null,null,false);
  perform set_config('app.study.task_context',coalesce(old_context,''),true); perform private.study_require((result->>'ok')::boolean,'FORBIDDEN');
  result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type',p_resource_type,'value',case when p_resource_type='analysis' then private.study_advanced_record(p_resource_id) else private.study_record(p_resource_type,p_resource_id) end));
  insert into private.study_service_receipts values('analysisAdvanced',sid,p_idempotency_key,p_job_id,p_lease_token,request,result); return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end $$;


create or replace function "api"."svc_study_analysis_advanced_reconcile_v1"("p_resource_type" "text", "p_resource_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_idempotency_key" "text", "p_artifact_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare sid uuid; bound_job uuid; j private.worker_jobs%rowtype; receipt private.study_service_receipts%rowtype; state text; resource jsonb;
begin
  perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
  perform private.study_require(p_resource_type='analysis','INVALID_REQUEST');
  case p_resource_type
    when 'modelSourceAcquisition' then select study_id,job_id into sid,bound_job from private.study_source_acquisitions where id=p_resource_id;
    when 'modelPreparation' then select study_id,job_id into sid,bound_job from private.study_model_preparations where id=p_resource_id;
    when 'run' then select study_id,job_id into sid,bound_job from private.study_runs where id=p_resource_id;
 when 'analysis' then select study_id,job_id into sid,bound_job from private.study_advanced_analyses where id=p_resource_id;
    else perform private.study_require(false,'INVALID_REQUEST');
  end case;
  perform private.study_require(sid is not null and bound_job=p_job_id,'REFERENCE_MISMATCH');
  perform 1 from private.studies where id=sid for update;
  select * into j from private.worker_jobs where id=p_job_id for update;
 if p_resource_type='analysis' then
  perform private.study_require(j.job_kind='study.analysis_advanced' and j.worker_runtime='calculator' and j.worker_queue='solver' and j.subject_type='study' and j.subject_id=p_resource_id
   and j.payload_schema_version='study.analysis_advanced.request.v1' and j.payload_json=jsonb_build_object('schemaVersion','study.analysis_advanced.request.v1','studyId',sid,'analysisId',p_resource_id)
   and exists(select 1 from private.study_advanced_analyses a where a.id=p_resource_id and a.study_id=sid and a.job_id=p_job_id and a.requested_by=j.requested_by),'REFERENCE_MISMATCH');
 end if;
  perform private.study_require(p_lease_token is not null and (j.lease_token=p_lease_token or exists(
    select 1 from private.worker_job_events where job_id=p_job_id and lease_token=p_lease_token)),'FORBIDDEN');
  select * into receipt from private.study_service_receipts where operation='analysisAdvanced' and study_id=sid and idempotency_key=p_idempotency_key;
  if found then
    perform private.study_require(receipt.job_id=p_job_id and receipt.lease_token=p_lease_token and receipt.request->>'id'=p_resource_id::text,'IDEMPOTENCY_CONFLICT');
    state:='committed'; resource:=receipt.response->'data';
  elsif p_artifact_id is not null and exists(select 1 from private.study_artifacts where id=p_artifact_id) then state:='referenced';
  elsif j.status in ('completed','failed','cancelled','blocked') and j.lease_token is null then state:='unreferenced';
  else state:='pending'; end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('state',state,'resource',resource,'jobStatus',j.status));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end $$;


create or replace function "api"."svc_study_task_fail_v1"("p_resource_type" "text", "p_resource_id" "uuid", "p_job_id" "uuid", "p_lease_token" "uuid", "p_error_code" "text", "p_idempotency_key" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare sid uuid; job uuid; kind text; subject text; result jsonb; old_context text; receipt private.study_service_receipts%rowtype; request jsonb;
begin
  perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
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



alter table private.study_artifact_read_intents add column family text not null default 'legacy' check(family in ('legacy','advanced'));
create function private.study_advanced_artifact_authorize(p_study uuid,p_ref jsonb,p_actor uuid,p_client text) returns jsonb
language plpgsql security definer set search_path='' as $$declare a private.study_artifacts%rowtype;analysis private.study_advanced_analyses%rowtype;r private.study_report_revisions%rowtype;begin
 perform private.study_authorize(p_study,p_actor,p_client,'read');perform private.study_require((select disclosure_enabled from private.study_runtime_config where singleton),'CAPABILITY_UNAVAILABLE');
 select * into a from private.study_artifacts where study_id=p_study and id=(p_ref->>'id')::uuid;perform private.study_require(found and a.ref=p_ref,'REFERENCE_MISMATCH');
 if p_ref->>'type'='analysisFacts' and p_ref->>'schemaVersion'='lca.study-analysis-facts.v2' then
  select * into analysis from private.study_advanced_analyses where study_id=p_study and facts_artifact_id=a.id;
  perform private.study_require(found and exists(select 1 from private.worker_jobs where id=analysis.job_id and status='completed'),'DISCLOSURE_DENIED');
  perform private.study_advanced_rights(p_study,analysis.baseline_run_id,p_actor,p_client);
 elsif p_ref->>'type'='reportContent' and p_ref->>'schemaVersion'='lca.study-report-content.v2' then
  select * into r from private.study_report_revisions where study_id=p_study and template_id='lca.study-report.v2' and content_artifact_id=a.id;
  perform private.study_require(found,'DISCLOSURE_DENIED');perform private.study_report_advanced_rights(p_study,r.run_ids,r.analysis_ids,p_actor,p_client);
 else perform private.study_require(false,'DISCLOSURE_DENIED');end if;
 return jsonb_build_object('kind','artifactCapability','studyId',p_study,'artifactRef',a.ref,'storageBucket',a.bucket,'storageObjectPath',a.object_path);
end$$;

create or replace function "private"."study_advanced_artifact_intent"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare sid uuid:=(p_request->>'studyId')::uuid; actor uuid:=auth.uid(); client text:=nullif(auth.jwt()->>'client_id',''); intent uuid; expiry timestamptz; begin
 perform private.study_advanced_envelope(p_request,false);
 perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','studyId','artifactRef']) and p_request->>'operation'='artifact.read','INVALID_REQUEST');
 perform private.study_advanced_artifact_authorize(sid,p_request->'artifactRef',actor,client);
 perform pg_advisory_xact_lock(hashtextextended('study-artifact-intent:'||actor::text,895));
 with expired as(select id from private.study_artifact_read_intents where expires_at<=clock_timestamp() order by expires_at,id limit 256 for update skip locked)
 delete from private.study_artifact_read_intents i using expired e where i.id=e.id;
 perform private.study_require((select count(*) from private.study_artifact_read_intents where actor_id=actor and expires_at>clock_timestamp())<64,'CAPABILITY_UNAVAILABLE');
 insert into private.study_artifact_read_intents(study_id,artifact_id,artifact_ref,actor_id,client_id,family)
 values(sid,(p_request->'artifactRef'->>'id')::uuid,p_request->'artifactRef',actor,client,'advanced') returning id,expires_at into intent,expiry;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('kind','artifactReadIntent','intentId',intent,'expiresAt',expiry,'studyId',sid,'artifactRef',p_request->'artifactRef'));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
end $$;


create or replace function "api"."svc_study_artifact_read_resolve_v1"("p_intent_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$ declare i private.study_artifact_read_intents%rowtype; begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 select * into i from private.study_artifact_read_intents where id=p_intent_id;
 perform private.study_require(found and i.expires_at>clock_timestamp(),'CAPABILITY_UNAVAILABLE');
 return jsonb_build_object('ok',true,'data',case when i.family='advanced' then private.study_advanced_artifact_authorize(i.study_id,i.artifact_ref,i.actor_id,i.client_id) else private.study_reporting_artifact_authorize(i.study_id,i.artifact_ref,i.actor_id,i.client_id) end);
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end $$;



create table private.study_advanced_parameter_intents (
 id uuid primary key default gen_random_uuid(),study_id uuid not null,baseline_run_id uuid not null,source_snapshot_id uuid not null,
 actor_id uuid not null references auth.users(id),client_id text,expires_at timestamptz not null default clock_timestamp()+interval '2 minutes',
 foreign key(study_id,baseline_run_id) references private.study_runs(study_id,id),foreign key(study_id,source_snapshot_id) references private.study_source_snapshots(study_id,id)
);
create index study_advanced_parameter_actor_idx on private.study_advanced_parameter_intents(actor_id,expires_at);
create index study_advanced_parameter_run_idx on private.study_advanced_parameter_intents(study_id,baseline_run_id);
create index study_advanced_parameter_snapshot_idx on private.study_advanced_parameter_intents(study_id,source_snapshot_id);
create function private.study_advanced_parameters(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$declare actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');sid uuid:=(p_request->>'studyId')::uuid;rid uuid:=(p_request->>'baselineRunId')::uuid;snapshot uuid;intent uuid;expiry timestamptz;begin
 perform private.study_advanced_envelope(p_request,false);
 perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','studyId','baselineRunId']) and p_request->>'operation'='analysis.parameters.read','INVALID_REQUEST');
 snapshot:=private.study_advanced_rights(sid,rid,actor,client);
 perform pg_advisory_xact_lock(hashtextextended('study-advanced-parameter-intent:'||actor::text,909));
 with expired as(select id from private.study_advanced_parameter_intents where expires_at<=clock_timestamp() order by expires_at,id limit 256 for update skip locked)
 delete from private.study_advanced_parameter_intents i using expired e where i.id=e.id;
 perform private.study_require((select count(*) from private.study_advanced_parameter_intents where actor_id=actor and expires_at>clock_timestamp())<64,'CAPABILITY_UNAVAILABLE');
 insert into private.study_advanced_parameter_intents(study_id,baseline_run_id,source_snapshot_id,actor_id,client_id) values(sid,rid,snapshot,actor,client) returning id,expires_at into intent,expiry;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('kind','advancedParameterIntent','intentId',intent,'expiresAt',expiry,'studyId',sid,'baselineRunId',rid));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');end$$;
create function api.svc_study_analysis_parameters_resolve_v1(p_intent_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$declare i private.study_advanced_parameter_intents%rowtype;snapshot uuid;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');select * into i from private.study_advanced_parameter_intents where id=p_intent_id;
 perform private.study_require(found and i.expires_at>clock_timestamp(),'CAPABILITY_UNAVAILABLE');snapshot:=private.study_advanced_rights(i.study_id,i.baseline_run_id,i.actor_id,i.client_id);
 perform private.study_require(snapshot=i.source_snapshot_id,'REFERENCE_MISMATCH');
 return jsonb_build_object('ok',true,'data',jsonb_build_object('kind','advancedParameterContext','intentId',i.id,'expiresAt',i.expires_at,'studyId',i.study_id,'baselineRunId',i.baseline_run_id,'actorId',i.actor_id,'clientId',i.client_id,
 'baseline',private.study_advanced_baseline(i.study_id,i.baseline_run_id),'sourceSnapshot',private.study_record('modelSourceSnapshot',snapshot),
 'sourceArtifact',private.study_private_artifact(i.study_id,(select artifact_id from private.study_source_snapshots where id=snapshot))));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);end$$;


alter table private.study_report_revisions drop constraint study_report_revisions_template_id_check;
alter table private.study_report_revisions add constraint study_report_revisions_template_id_check check(template_id in ('lca.study-report.v1','lca.study-report.v2'));
alter table private.study_report_intents add column family text not null default 'legacy' check(family in ('legacy','advanced'));
create table private.study_report_advanced_analyses (
 study_id uuid not null,report_id uuid not null,ordinal integer not null check(ordinal between 1 and 2),analysis_id uuid not null,
 primary key(report_id,ordinal),unique(report_id,analysis_id),foreign key(study_id,report_id) references private.study_report_revisions(study_id,id),
 foreign key(study_id,analysis_id) references private.study_advanced_analyses(study_id,id)
);
create index study_report_advanced_analysis_idx on private.study_report_advanced_analyses(study_id,analysis_id);
create index study_report_advanced_report_idx on private.study_report_advanced_analyses(study_id,report_id);
create trigger study_report_advanced_analyses_immutable before update or delete on private.study_report_advanced_analyses for each row execute function private.study_report_immutable();
create function private.study_report_advanced_rights(p_study uuid,p_runs jsonb,p_analyses jsonb,p_actor uuid,p_client text) returns jsonb
language plpgsql security definer set search_path='' as $$declare aid text;a private.study_advanced_analyses%rowtype;refs jsonb:='[]'::jsonb;begin
 perform private.study_authorize(p_study,p_actor,p_client,'read');perform private.study_require(private.study_report_ids(p_runs,1,1) and private.study_report_ids(p_analyses,1,2),'INVALID_REQUEST');
 perform private.study_advanced_rights(p_study,(p_runs->>0)::uuid,p_actor,p_client);
 for aid in select jsonb_array_elements_text(p_analyses) loop
  select * into a from private.study_advanced_analyses where study_id=p_study and id=aid::uuid;
  perform private.study_require(found and a.baseline_run_id::text=p_runs->>0 and a.facts_artifact_id is not null
   and exists(select 1 from private.worker_jobs where id=a.job_id and status='completed'),'REFERENCE_MISMATCH');
  perform private.study_require(a.source_snapshot_id=private.study_advanced_rights(p_study,a.baseline_run_id,p_actor,p_client),'REFERENCE_MISMATCH');
  refs:=refs||jsonb_build_array((select ref from private.study_artifacts where id=a.facts_artifact_id));
 end loop;return refs;
end$$;

create or replace function "private"."study_report_rights"("p_study" "uuid", "p_runs" "jsonb", "p_analyses" "jsonb", "p_actor" "uuid", "p_client" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare rid text;aid text;a private.study_analyses%rowtype;refs jsonb:='[]'::jsonb;begin
 if exists(select 1 from private.study_advanced_analyses where study_id=p_study and id=(p_analyses->>0)::uuid) then return private.study_report_advanced_rights(p_study,p_runs,p_analyses,p_actor,p_client);end if;
 perform private.study_authorize(p_study,p_actor,p_client,'read');
 perform private.study_require(private.study_report_ids(p_runs,1,2) and private.study_report_ids(p_analyses,1,2),'INVALID_REQUEST');
 for rid in select jsonb_array_elements_text(p_runs) loop
  perform private.study_analysis_rights(p_study,jsonb_build_object('runIds',jsonb_build_array(rid)),p_actor,p_client);
 end loop;
 for aid in select jsonb_array_elements_text(p_analyses) loop
  select * into a from private.study_analyses where study_id=p_study and id=aid::uuid;
  perform private.study_require(found and a.facts_artifact_id is not null and exists(select 1 from private.worker_jobs where id=a.job_id and status='completed')
   and a.config->'runIds'<@p_runs,'REFERENCE_MISMATCH');
  perform private.study_analysis_rights(p_study,a.config,p_actor,p_client);
  refs:=refs||jsonb_build_array((select ref from private.study_artifacts where id=a.facts_artifact_id));
 end loop;return refs;
end$$;


create or replace function "private"."study_report_advanced_content_valid"("p_value" "jsonb") RETURNS boolean
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO ''
    AS $_$
declare c jsonb;r jsonb;section jsonb;typ text;idkey text;claimids jsonb;seen text[];v text;
begin
 if not private.study_keys(p_value,array['schemaVersion','title','claims','sections','tables','charts','additionalLimitations'])
 or p_value->>'schemaVersion' is distinct from 'lca.study-report-draft.v2' or not private.study_report_plain(p_value->'title',256)
 or jsonb_typeof(p_value->'claims') is distinct from 'array' then return false;end if;
 if jsonb_array_length(p_value->'claims') not between 1 and 256 then return false;end if;
 claimids:='[]';
 for c in select * from jsonb_array_elements(p_value->'claims') loop
  if not private.study_keys(c,array['claimId','bundleRef','factId','canonicalValue','unit','display'])
  or not private.study_text(c->'claimId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$') or not private.study_text(c->'factId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$')
  or not private.study_report_plain(c->'unit',128) or c->'display'<>'{"style":"exact"}'::jsonb
  or not private.study_keys(c->'bundleRef',array['type','id','contentHash','digestScope','byteSize','mediaType','schemaVersion'])
  or c->'bundleRef'->>'type' is distinct from 'analysisFacts' or c->'bundleRef'->>'schemaVersion' is distinct from 'lca.study-analysis-facts.v2'
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


create or replace function "private"."study_report_advanced_validation_check"("p_validation" "jsonb", "p_report" "uuid", "p_hash" "text", "p_count" integer, "p_refs" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$begin
 perform private.study_require(private.study_keys(p_validation,array['schemaVersion','profileId','reportRevisionId','contentHash','claimCount','factsBindingHash'])
 and p_validation->>'schemaVersion'='lca.study-report-validation.v2' and p_validation->>'profileId'='lca.study-report-claims.v2'
 and p_validation->>'reportRevisionId'=p_report::text and p_validation->>'contentHash'=p_hash
 and jsonb_typeof(p_validation->'claimCount')='number' and (p_validation->>'claimCount')::numeric=p_count
 and p_validation->>'factsBindingHash'=private.study_reporting_digest('lca.study-report-facts-binding.v1',p_refs),'REFERENCE_MISMATCH');
end$$;


create or replace function "private"."study_report_advanced_command"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '15s'
    AS $$
declare op text:=p_request->>'operation';actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');sid uuid;rid uuid;
 r private.study_report_revisions%rowtype;i private.study_report_intents%rowtype;cfg private.study_advanced_config%rowtype;previous private.study_command_receipts%rowtype;
 req jsonb:=p_request-'schemaVersion'-'requestId'-'idempotencyKey';refs jsonb;result jsonb;allowed text[];parent uuid;
begin
 perform private.study_advanced_envelope(p_request,true);
 perform private.study_require(op in ('report.create','report.save','report.freeze'),'CAPABILITY_UNAVAILABLE');
 perform private.study_require(private.study_client_allowed(client,'STUDY-WRITE-01'),'FORBIDDEN');
 case op
 when 'report.create' then
  allowed:=array['schemaVersion','requestId','idempotencyKey','operation','studyId','parentReportRevisionId','runIds','analysisIds','content','templateId'];sid:=(p_request->>'studyId')::uuid;
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
  perform private.study_require(found and r.template_id='lca.study-report.v2','NOT_FOUND');
 end if;
 if op='report.create' then refs:=private.study_report_advanced_rights(sid,p_request->'runIds',p_request->'analysisIds',actor,client);
 else refs:=private.study_report_advanced_rights(sid,r.run_ids,r.analysis_ids,actor,client);end if;
 select * into previous from private.study_command_receipts where actor_id=actor and operation='advanced.'||op and scope=sid::text and idempotency_key=p_request->>'idempotencyKey';
 if found then
  perform private.study_require(previous.request=req,'IDEMPOTENCY_CONFLICT');
  if previous.response->'data'->>'kind'='reportAdvancedCommandIntent' then
   i:=private.study_report_advanced_intent_check((previous.response->'data'->>'intentId')::uuid);if i.response is not null then return i.response;end if;
  end if;
  if op='export.request' then perform private.study_report_export_authorize((previous.response->'data'->'value'->>'exportId')::uuid,actor,client);end if;return previous.response;
 end if;
 perform private.study_analysis_require_current(sid,jsonb_build_object('runIds',case when op='report.create' then p_request->'runIds' else r.run_ids end));
 perform private.study_require((select status='active' from private.studies where id=sid),'FROZEN_REVISION');
 select * into cfg from private.study_advanced_config where singleton for share;
 perform private.study_require(cfg.report_enabled,'CAPABILITY_UNAVAILABLE');
 if op in ('report.create','report.save') then
  perform private.study_require(private.study_report_advanced_content_valid(p_request->'content'),'INVALID_REQUEST');
  perform private.study_require(not exists(select 1 from jsonb_array_elements(p_request->'content'->'claims')c where not refs @> jsonb_build_array(c->'bundleRef')),'REFERENCE_MISMATCH');
 end if;
 if op='report.create' then
  perform private.study_require(p_request->>'templateId'='lca.study-report.v2','INVALID_REQUEST');parent:=(p_request->>'parentReportRevisionId')::uuid;
  if parent is not null then perform private.study_require(exists(select 1 from private.study_report_revisions where study_id=sid and id=parent and status='frozen' and template_id='lca.study-report.v2'),'REFERENCE_MISMATCH');end if;
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
 (select grant_epoch from private.studies where id=sid),cfg.revision,case when op<>'report.create' then private.study_report_record(rid) end,'advanced') returning * into i;
 result:=jsonb_build_object('ok',true,'data',jsonb_build_object('kind','reportAdvancedCommandIntent','intentId',i.id,'expiresAt',i.expires_at,'operation',op));
 insert into private.study_command_receipts values(actor,'advanced.'||op,sid::text,p_request->>'idempotencyKey',req,result,clock_timestamp());return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range or check_violation or not_null_violation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');
end$$;


create or replace function "private"."study_report_advanced_intent_check"("p_id" "uuid") RETURNS "private"."study_report_intents"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare i private.study_report_intents%rowtype;r private.study_report_revisions%rowtype;cfg private.study_advanced_config%rowtype;refs jsonb;begin
 select * into i from private.study_report_intents where id=p_id;
 perform private.study_require(found and i.family='advanced','CAPABILITY_UNAVAILABLE');
 perform private.study_authorize(i.study_id,i.actor_id,i.client_id,case when i.operation='export.request' then 'read' else 'write' end);
 select * into i from private.study_report_intents where id=p_id;
 perform private.study_require((select grant_epoch from private.studies where id=i.study_id)=i.grant_epoch,'FORBIDDEN');
 if i.operation='report.create' then
  refs:=private.study_report_advanced_rights(i.study_id,i.request->'runIds',i.request->'analysisIds',i.actor_id,i.client_id);
 else
  select * into r from private.study_report_revisions where study_id=i.study_id and id=i.report_id;
  perform private.study_require(found,'REFERENCE_MISMATCH');
  refs:=private.study_report_advanced_rights(i.study_id,r.run_ids,r.analysis_ids,i.actor_id,i.client_id);
  perform private.study_require(refs=r.facts_refs,'REFERENCE_MISMATCH');
 end if;
 if i.response is not null then return i;end if;
 perform private.study_analysis_require_current(i.study_id,jsonb_build_object('runIds',case when i.operation='report.create' then i.request->'runIds' else r.run_ids end));
 perform private.study_require(i.expires_at>clock_timestamp(),'CAPABILITY_UNAVAILABLE');
 select * into cfg from private.study_advanced_config where singleton for share;
 perform private.study_require(cfg.revision=i.config_revision and cfg.report_enabled,'CAPABILITY_UNAVAILABLE');
 perform private.study_require((select status='active' from private.studies where id=i.study_id),'FROZEN_REVISION');
 if i.operation<>'report.create' then
  perform private.study_require(private.study_report_record(r.id)=i.report_snapshot,'REVISION_CONFLICT');
 end if;return i;
end$$;





create or replace function "api"."svc_study_report_advanced_intent_consume_v1"("p_intent_id" "uuid", "p_completion" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare i private.study_report_intents%rowtype;r private.study_report_revisions%rowtype;refs jsonb;contentref jsonb;artifact uuid;result jsonb;validation jsonb;claimcount integer;
begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 i:=private.study_report_advanced_intent_check(p_intent_id);
 select * into i from private.study_report_intents where id=i.id for update;
 if i.response is not null then return i.response;end if;
 if i.operation='report.create' then
  refs:=private.study_report_advanced_rights(i.study_id,i.request->'runIds',i.request->'analysisIds',i.actor_id,i.client_id);claimcount:=jsonb_array_length(i.request->'content'->'claims');
 else
  select * into r from private.study_report_revisions where id=i.report_id for update;
  refs:=private.study_report_advanced_rights(i.study_id,r.run_ids,r.analysis_ids,i.actor_id,i.client_id);
  claimcount:=case when i.operation='report.save' then jsonb_array_length(i.request->'content'->'claims') else (r.validation_evidence->>'claimCount')::integer end;
 end if;
 validation:=p_completion->'validation';
 if i.operation in ('report.create','report.save') then
  perform private.study_require(private.study_keys(p_completion,array['kind','contentArtifact','factsRefs','validation']) and p_completion->>'kind'='validatedContent'
   and p_completion->'factsRefs'=refs,'REFERENCE_MISMATCH');
  contentref:=p_completion->'contentArtifact'->'artifactRef';
  perform private.study_report_advanced_validation_check(validation,i.report_id,contentref->>'contentHash',claimcount,refs);
  artifact:=private.study_report_store_produced(i.study_id,p_completion->'contentArtifact',i.content_artifact_id,'reportContent','lca.study-report-content.v2','content');
  if i.operation='report.create' then
   insert into private.study_report_revisions(id,study_id,parent_report_id,author_id,content_hash,content_artifact_id,template_id,run_ids,analysis_ids,facts_refs,validity_snapshot,validation_evidence)
   values(i.report_id,i.study_id,(i.request->>'parentReportRevisionId')::uuid,i.actor_id,contentref->>'contentHash',artifact,i.request->>'templateId',i.request->'runIds',i.request->'analysisIds',refs,
   private.study_report_validity_snapshot(i.study_id,i.request->'runIds',i.created_at),validation);
   insert into private.study_report_runs select i.study_id,i.report_id,n,v::uuid from jsonb_array_elements_text(i.request->'runIds') with ordinality e(v,n);
   insert into private.study_report_advanced_analyses select i.study_id,i.report_id,n,v::uuid from jsonb_array_elements_text(i.request->'analysisIds') with ordinality e(v,n);
  else update private.study_report_revisions set revision=revision+1,content_hash=contentref->>'contentHash',content_artifact_id=artifact,validation_evidence=validation where id=i.report_id;end if;
  result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','reportRevision','value',private.study_report_record(i.report_id)));
 elsif i.operation='report.freeze' then
  select ref into contentref from private.study_artifacts where id=r.content_artifact_id;
  perform private.study_require(private.study_keys(p_completion,array['kind','contentRef','validation']) and p_completion->>'kind'='validatedFreeze' and p_completion->'contentRef'=contentref,'REFERENCE_MISMATCH');
  perform private.study_report_advanced_validation_check(validation,r.id,r.content_hash,claimcount,refs);
  update private.study_report_revisions set status='frozen',revision=revision+1,validation_evidence=validation where id=r.id;
  result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','reportRevision','value',private.study_report_record(r.id)));
 end if;
 update private.study_report_intents set response=result where id=i.id;
 update private.study_command_receipts set response=result where actor_id=i.actor_id and operation='advanced.'||i.operation and scope=i.study_id::text and idempotency_key=i.request->>'idempotencyKey';return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range or check_violation or not_null_violation or invalid_datetime_format then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');
end$_$;


create or replace function "api"."svc_study_report_advanced_intent_reconcile_v1"("p_intent_id" "uuid", "p_artifact_id" "uuid", "p_content_hash" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare i private.study_report_intents%rowtype;a private.study_artifacts%rowtype;expected_ref jsonb;state text:='unknown';begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 perform private.study_require(p_intent_id is not null and p_artifact_id is not null and private.study_text(to_jsonb(p_content_hash),64,'^[0-9a-f]{64}$'),'INVALID_REQUEST');
 select * into i from private.study_report_intents where id=p_intent_id;
 if found and i.family='advanced' then
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
 return jsonb_build_object('ok',true,'data',jsonb_build_object('schemaVersion','lca.study-report-reconcile.v1','intentId',p_intent_id,'artifactId',p_artifact_id,'state',state,'deletionPermitted',false));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end$_$;


create or replace function "api"."svc_study_report_intent_resolve_v1"("p_intent_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare i private.study_report_intents%rowtype;r private.study_report_revisions%rowtype;runids jsonb;analysisids jsonb;runs jsonb;analyses jsonb;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');perform private.study_require(exists(select 1 from private.study_report_intents where id=p_intent_id and family='legacy'),'CAPABILITY_UNAVAILABLE');i:=private.study_report_intent_check(p_intent_id);
 if i.response is not null then return i.response;end if;
 if i.operation='report.create' then runids:=i.request->'runIds';analysisids:=i.request->'analysisIds';
 else select * into r from private.study_report_revisions where id=i.report_id;runids:=r.run_ids;analysisids:=r.analysis_ids;end if;
 select jsonb_agg(jsonb_build_object('run',private.study_record('run',rn.id),'revision',private.study_record('studyRevision',rn.study_revision_id),
 'scenario',private.study_record('scenarioRevision',rn.scenario_id),'preparation',private.study_record('modelPreparation',rn.preparation_id),
 'preparedArtifact',private.study_private_artifact(i.study_id,p.input_artifact_id),'resultArtifact',private.study_private_artifact(i.study_id,rn.result_artifact_id)) order by e.n)
 into runs from jsonb_array_elements_text(runids) with ordinality e(v,n) join private.study_runs rn on rn.id=e.v::uuid and rn.study_id=i.study_id
 join private.study_model_preparations p on p.id=rn.preparation_id;
 select jsonb_agg(jsonb_build_object('analysis',private.study_analysis_record(a.id),'factsArtifact',private.study_private_artifact(i.study_id,a.facts_artifact_id)) order by e.n)
 into analyses from jsonb_array_elements_text(analysisids) with ordinality e(v,n) join private.study_analyses a on a.id=e.v::uuid and a.study_id=i.study_id;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('kind','reportCommandContext','intentId',i.id,'expiresAt',i.expires_at,'operation',i.operation,
 'request',i.request,'studyId',i.study_id,'actorId',i.actor_id,'clientId',i.client_id,'grantEpoch',i.grant_epoch,'generatedAt',i.created_at,
 'reportRevisionId',i.report_id,'contentArtifactId',i.content_artifact_id,'exportId',i.export_id,'projectionArtifactId',i.projection_artifact_id,
 'resourcesArtifactId',i.resources_artifact_id,'bundleArtifactId',i.bundle_artifact_id,'report',i.report_snapshot,
 'contentArtifact',case when r.id is not null then private.study_private_artifact(i.study_id,r.content_artifact_id) end,'runs',runs,'analyses',analyses,
 'exportProfile',case when i.operation='export.request' then (select export_profile from private.study_reporting_config where singleton) end,
 'disclosureContextHash',case when i.operation='export.request' then private.study_report_disclosure_context(i) end,
 'factsBindingHash',private.study_reporting_digest('lca.study-report-facts-binding.v1',private.study_report_rights(i.study_id,runids,analysisids,i.actor_id,i.client_id))));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end$$;


create or replace function "api"."svc_study_report_intent_consume_v1"("p_intent_id" "uuid", "p_completion" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare i private.study_report_intents%rowtype;r private.study_report_revisions%rowtype;refs jsonb;contentref jsonb;artifact uuid;result jsonb;validation jsonb;claimcount integer;
 manifest jsonb;receipt jsonb;profile jsonb;projection uuid;resources uuid;bundle uuid;record jsonb;validity jsonb;
begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 perform private.study_require(exists(select 1 from private.study_report_intents where id=p_intent_id and family='legacy'),'CAPABILITY_UNAVAILABLE');i:=private.study_report_intent_check(p_intent_id);
 select * into i from private.study_report_intents where id=i.id for update;
 if i.response is not null then return i.response;end if;
 if i.operation='report.create' then
  refs:=private.study_report_rights(i.study_id,i.request->'runIds',i.request->'analysisIds',i.actor_id,i.client_id);claimcount:=jsonb_array_length(i.request->'content'->'claims');
 else
  select * into r from private.study_report_revisions where id=i.report_id for update;
  refs:=private.study_report_rights(i.study_id,r.run_ids,r.analysis_ids,i.actor_id,i.client_id);
  claimcount:=case when i.operation='report.save' then jsonb_array_length(i.request->'content'->'claims') else (r.validation_evidence->>'claimCount')::integer end;
 end if;
 validation:=p_completion->'validation';
 if i.operation in ('report.create','report.save') then
  perform private.study_require(private.study_keys(p_completion,array['kind','contentArtifact','factsRefs','validation']) and p_completion->>'kind'='validatedContent'
   and p_completion->'factsRefs'=refs,'REFERENCE_MISMATCH');
  contentref:=p_completion->'contentArtifact'->'artifactRef';
  perform private.study_report_validation_check(validation,i.report_id,contentref->>'contentHash',claimcount,refs);
  artifact:=private.study_report_store_produced(i.study_id,p_completion->'contentArtifact',i.content_artifact_id,'reportContent','lca.study-report-content.v1','content');
  if i.operation='report.create' then
   insert into private.study_report_revisions(id,study_id,parent_report_id,author_id,content_hash,content_artifact_id,template_id,run_ids,analysis_ids,facts_refs,validity_snapshot,validation_evidence)
   values(i.report_id,i.study_id,(i.request->>'parentReportRevisionId')::uuid,i.actor_id,contentref->>'contentHash',artifact,i.request->>'templateId',i.request->'runIds',i.request->'analysisIds',refs,
   private.study_report_validity_snapshot(i.study_id,i.request->'runIds',i.created_at),validation);
   insert into private.study_report_runs select i.study_id,i.report_id,n,v::uuid from jsonb_array_elements_text(i.request->'runIds') with ordinality e(v,n);
   insert into private.study_report_analyses select i.study_id,i.report_id,n,v::uuid from jsonb_array_elements_text(i.request->'analysisIds') with ordinality e(v,n);
  else update private.study_report_revisions set revision=revision+1,content_hash=contentref->>'contentHash',content_artifact_id=artifact,validation_evidence=validation where id=i.report_id;end if;
  result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','reportRevision','value',private.study_report_record(i.report_id)));
 elsif i.operation='report.freeze' then
  select ref into contentref from private.study_artifacts where id=r.content_artifact_id;
  perform private.study_require(private.study_keys(p_completion,array['kind','contentRef','validation']) and p_completion->>'kind'='validatedFreeze' and p_completion->'contentRef'=contentref,'REFERENCE_MISMATCH');
  perform private.study_report_validation_check(validation,r.id,r.content_hash,claimcount,refs);
  update private.study_report_revisions set status='frozen',revision=revision+1,validation_evidence=validation where id=r.id;
  result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','reportRevision','value',private.study_report_record(r.id)));
 else
  perform private.study_require(private.study_keys(p_completion,array['kind','projectionArtifact','resourcesArtifact','bundleArtifact','manifest','receipt']) and p_completion->>'kind'='validatedExport','REFERENCE_MISMATCH');
  manifest:=p_completion->'manifest';receipt:=p_completion->'receipt';select export_profile into profile from private.study_reporting_config where singleton;
  perform private.study_require(private.study_keys(manifest,array['schemaVersion','issuerId','exportId','studyId','reportRevisionId','reportContentHash','actorId','clientId','grantEpoch','policyId','disclosureContextHash','generatedAt','validitySnapshot','reviewIds','renderer','files'])
   and manifest->>'schemaVersion'='lca.study-export-manifest.v1' and manifest->>'issuerId'=profile->>'issuerId'
   and manifest->>'exportId'=i.export_id::text and manifest->>'studyId'=i.study_id::text and manifest->>'reportRevisionId'=i.report_id::text
   and manifest->>'reportContentHash'=r.content_hash and manifest->>'actorId'=i.actor_id::text and (manifest->>'clientId') is not distinct from i.client_id
   and jsonb_typeof(manifest->'grantEpoch')='number' and (manifest->>'grantEpoch')::numeric=i.grant_epoch
   and manifest->>'policyId'='lca.study-report-disclosure.v1' and manifest->>'disclosureContextHash'=private.study_report_disclosure_context(i)
   and (manifest->>'generatedAt')::timestamptz=i.created_at and manifest->'validitySnapshot'=i.report_snapshot->'validitySnapshot' and manifest->'reviewIds'='[]'::jsonb
   and manifest->'renderer'=jsonb_build_object('version','1.0.0','viewModelVersion','lca.study-report-view.v1','artifactHash',profile->>'rendererArtifactHash'),'REFERENCE_MISMATCH');
  perform private.study_require(jsonb_typeof(manifest->'files')='array' and jsonb_array_length(manifest->'files')=2
   and private.study_keys(manifest->'files'->0,array['path','mediaType','sha256','byteSize']) and private.study_keys(manifest->'files'->1,array['path','mediaType','sha256','byteSize'])
   and manifest->'files'->0->>'path'='report.html' and manifest->'files'->0->>'mediaType'='text/html'
   and manifest->'files'->1->>'path'='projection.json' and manifest->'files'->1->>'mediaType'='application/json'
   and manifest->'files'->0->>'sha256' ~ '^[0-9a-f]{64}$'
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
  projection:=private.study_report_store_produced(i.study_id,p_completion->'projectionArtifact',i.projection_artifact_id,'reportProjection','lca.study-report-view.v1','projection');
  resources:=private.study_report_store_produced(i.study_id,p_completion->'resourcesArtifact',i.resources_artifact_id,'renderResources','lca.study-export-manifest.v1','resources');
  bundle:=private.study_report_store_produced(i.study_id,p_completion->'bundleArtifact',i.bundle_artifact_id,'reportExportBundle','lca.study-export-bundle.v1','bundle');
  record:=jsonb_build_object('exportId',i.export_id,'studyId',i.study_id,'reportRevisionId',i.report_id,'reportContentHash',r.content_hash,'status','ready',
   'projectionRef',p_completion->'projectionArtifact'->'artifactRef','grantEpoch',i.grant_epoch,'factsRefs',refs,'rendererVersion','1.0.0','viewModelVersion','lca.study-report-view.v1',
   'resourcesRef',p_completion->'resourcesArtifact'->'artifactRef','actorId',i.actor_id,'policyId','lca.study-report-disclosure.v1','disclosureContextHash',manifest->>'disclosureContextHash',
   'disclosureDecision','allowed','generatedAt',i.created_at,'validitySnapshot',i.report_snapshot->'validitySnapshot','reviewIds','[]'::jsonb,'receipt',receipt,'bundleRef',p_completion->'bundleArtifact'->'artifactRef');
  insert into private.study_report_exports(id,study_id,report_id,actor_id,client_id,grant_epoch,record,manifest,projection_artifact_id,resources_artifact_id,bundle_artifact_id) values(i.export_id,i.study_id,i.report_id,i.actor_id,i.client_id,i.grant_epoch,record,manifest,projection,resources,bundle);
  result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','export','value',record));
 end if;
 update private.study_report_intents set response=result where id=i.id;
 update private.study_command_receipts set response=result where actor_id=i.actor_id and operation=i.operation and scope=i.study_id::text and idempotency_key=i.request->>'idempotencyKey';return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range or check_violation or not_null_violation or invalid_datetime_format then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');
end$_$;


create or replace function "api"."svc_study_report_intent_reconcile_v1"("p_intent_id" "uuid", "p_artifact_id" "uuid", "p_content_hash" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare i private.study_report_intents%rowtype;a private.study_artifacts%rowtype;expected_ref jsonb;state text:='unknown';begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 perform private.study_require(p_intent_id is not null and p_artifact_id is not null and private.study_text(to_jsonb(p_content_hash),64,'^[0-9a-f]{64}$'),'INVALID_REQUEST');
 select * into i from private.study_report_intents where id=p_intent_id;
 if found and i.family='legacy' then
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
 return jsonb_build_object('ok',true,'data',jsonb_build_object('schemaVersion','lca.study-report-reconcile.v1','intentId',p_intent_id,'artifactId',p_artifact_id,'state',state,'deletionPermitted',false));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end$_$;


create or replace function "private"."study_report_command"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '15s'
    AS $$
declare op text:=p_request->>'operation';actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');sid uuid;rid uuid;
 r private.study_report_revisions%rowtype;i private.study_report_intents%rowtype;cfg private.study_reporting_config%rowtype;previous private.study_command_receipts%rowtype;
 req jsonb:=p_request-'schemaVersion'-'requestId'-'idempotencyKey';refs jsonb;result jsonb;allowed text[];parent uuid;
begin
 perform private.study_reporting_envelope(p_request,true);
 perform private.study_require(private.study_client_allowed(client,'STUDY-WRITE-01'),'FORBIDDEN');
 case op
 when 'report.create' then
  allowed:=array['schemaVersion','requestId','idempotencyKey','operation','studyId','parentReportRevisionId','runIds','analysisIds','content','templateId'];sid:=(p_request->>'studyId')::uuid;
 when 'report.save','report.freeze' then
  allowed:=array['schemaVersion','requestId','idempotencyKey','operation','target']||case when op='report.save' then array['content'] else array['expectedContentHash'] end;
  perform private.study_require(private.study_keys(p_request->'target',array['type','id','expectedRevision']) and p_request->'target'->>'type'='reportRevision'
   and jsonb_typeof(p_request->'target'->'expectedRevision')='number' and (p_request->'target'->>'expectedRevision')::numeric between 1 and 9007199254740991
   and trunc((p_request->'target'->>'expectedRevision')::numeric)=(p_request->'target'->>'expectedRevision')::numeric,'INVALID_REQUEST');
  rid:=(p_request->'target'->>'id')::uuid;select study_id into sid from private.study_report_revisions where id=rid;
 when 'export.request' then
  allowed:=array['schemaVersion','requestId','idempotencyKey','operation','reportRevisionId','expectedContentHash','rendererVersion','viewModelVersion'];
  rid:=(p_request->>'reportRevisionId')::uuid;select study_id into sid from private.study_report_revisions where id=rid;
 else perform private.study_require(false,'CAPABILITY_UNAVAILABLE');end case;
 perform private.study_require(private.study_keys(p_request,allowed),'INVALID_REQUEST');
 perform private.study_authorize(sid,actor,client,case when op='export.request' then 'read' else 'write' end);
 -- The first lookup routes only by immutable Study ownership. A command may
 -- have waited for a producer holding the Study lock; reload and lock the
 -- mutable report before rights, replay recovery, CAS/hash checks or snapshot.
 if op<>'report.create' then
  select * into r from private.study_report_revisions where study_id=sid and id=rid for update;
  perform private.study_require(found and r.template_id='lca.study-report.v1','NOT_FOUND');
 end if;
 if op='report.create' then refs:=private.study_report_rights(sid,p_request->'runIds',p_request->'analysisIds',actor,client);
 else refs:=private.study_report_rights(sid,r.run_ids,r.analysis_ids,actor,client);end if;
 select * into previous from private.study_command_receipts where actor_id=actor and operation=op and scope=sid::text and idempotency_key=p_request->>'idempotencyKey';
 if found then
  perform private.study_require(previous.request=req,'IDEMPOTENCY_CONFLICT');
  if previous.response->'data'->>'kind'='reportCommandIntent' then
   i:=private.study_report_intent_check((previous.response->'data'->>'intentId')::uuid);if i.response is not null then return i.response;end if;
  end if;
  if op='export.request' then perform private.study_report_export_authorize((previous.response->'data'->'value'->>'exportId')::uuid,actor,client);end if;return previous.response;
 end if;
 perform private.study_analysis_require_current(sid,jsonb_build_object('runIds',case when op='report.create' then p_request->'runIds' else r.run_ids end));
 perform private.study_require((select status='active' from private.studies where id=sid),'FROZEN_REVISION');
 select * into cfg from private.study_reporting_config where singleton for share;
 perform private.study_require(case when op='export.request' then cfg.export_enabled else cfg.report_enabled end,'CAPABILITY_UNAVAILABLE');
 if op in ('report.create','report.save') then
  perform private.study_require(private.study_report_content_valid(p_request->'content'),'INVALID_REQUEST');
  perform private.study_require(not exists(select 1 from jsonb_array_elements(p_request->'content'->'claims')c where not refs @> jsonb_build_array(c->'bundleRef')),'REFERENCE_MISMATCH');
 end if;
 if op='report.create' then
  perform private.study_require(p_request->>'templateId'='lca.study-report.v1','INVALID_REQUEST');parent:=(p_request->>'parentReportRevisionId')::uuid;
  if parent is not null then perform private.study_require(exists(select 1 from private.study_report_revisions where study_id=sid and id=parent and status='frozen' and template_id='lca.study-report.v1'),'REFERENCE_MISMATCH');end if;
  rid:=gen_random_uuid();
 else
  if op='export.request' then
   perform private.study_require(r.status='frozen' and r.content_hash=p_request->>'expectedContentHash','REFERENCE_MISMATCH');
   perform private.study_require(p_request->>'rendererVersion'='1.0.0' and p_request->>'viewModelVersion'='lca.study-report-view.v1' and cfg.export_profile is not null,'CAPABILITY_UNAVAILABLE');
  else
   perform private.study_require(r.revision=(p_request->'target'->>'expectedRevision')::bigint,'REVISION_CONFLICT');
   perform private.study_require(r.status='draft','FROZEN_REVISION');
   if op='report.freeze' then perform private.study_require(r.content_hash=p_request->>'expectedContentHash','REFERENCE_MISMATCH');end if;
  end if;
 end if;
 -- Bounded, actor-serialized intent retention. No placeholder public row exists.
 perform pg_advisory_xact_lock(hashtextextended('study-report-intent:'||actor::text,904));
 perform private.study_require((select count(*) from private.study_report_intents where actor_id=actor and expires_at>clock_timestamp() and response is null)<64,'CAPABILITY_UNAVAILABLE');
 insert into private.study_report_intents(study_id,actor_id,client_id,operation,request,report_id,content_artifact_id,export_id,projection_artifact_id,resources_artifact_id,bundle_artifact_id,grant_epoch,config_revision,report_snapshot)
 values(sid,actor,client,op,p_request,rid,case when op in ('report.create','report.save') then gen_random_uuid() end,
 case when op='export.request' then gen_random_uuid() end,case when op='export.request' then gen_random_uuid() end,
 case when op='export.request' then gen_random_uuid() end,case when op='export.request' then gen_random_uuid() end,
 (select grant_epoch from private.studies where id=sid),cfg.revision,case when op<>'report.create' then private.study_report_record(rid) end) returning * into i;
 result:=jsonb_build_object('ok',true,'data',jsonb_build_object('kind','reportCommandIntent','intentId',i.id,'expiresAt',i.expires_at,'operation',op));
 insert into private.study_command_receipts values(actor,op,sid::text,p_request->>'idempotencyKey',req,result,clock_timestamp());return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range or check_violation or not_null_violation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');
end$$;


create or replace function "private"."study_reporting_list"("p_request" "jsonb") RETURNS "jsonb"
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
 elsif kind='reportRevision' then select array_agg(t.id order by t.id) into ids from(select study_report_revisions.id from private.study_report_revisions where study_id=sid and template_id='lca.study-report.v1' and (after_id is null or study_report_revisions.id>after_id) order by study_report_revisions.id limit lim+1)t;
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


create or replace function "api"."qry_study_reporting_v1"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare op text:=p_request->>'operation';actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');r private.study_report_revisions%rowtype;e private.study_report_exports%rowtype;result jsonb;ops jsonb;cfg private.study_reporting_config%rowtype;begin
 perform private.study_reporting_envelope(p_request,false);
 if op='artifact.read' then perform private.study_require(p_request->'artifactRef'->>'type' in ('analysisFacts','reportContent','reportProjection','renderResources','reportExportBundle'),'INVALID_REQUEST');end if;
 if op='study.resources.list' then return private.study_reporting_list(p_request);end if;
 if op='report.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','reportRevisionId']),'INVALID_REQUEST');
  select * into r from private.study_report_revisions where id=(p_request->>'reportRevisionId')::uuid;perform private.study_require(found and r.template_id='lca.study-report.v1','FORBIDDEN');
  perform private.study_report_rights(r.study_id,r.run_ids,r.analysis_ids,actor,client);
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','reportRevision','value',private.study_report_record(r.id)));
 elsif op='export.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','exportId']),'INVALID_REQUEST');e:=private.study_report_export_authorize((p_request->>'exportId')::uuid,actor,client);
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','export','value',e.record));
 end if;
 result:=private.study_qry_analysis_v1(p_request);
 if op='capability.read' and result->>'ok'='true' then
  ops:=result->'data'->'operations'||jsonb_build_array('study.resources.list','report.read','export.read');select * into cfg from private.study_reporting_config where singleton;
  if private.study_client_allowed(client,'STUDY-WRITE-01') and private.study_client_allowed(client,'DB-CORE-READ-01') then
   if cfg.report_enabled then ops:=ops||jsonb_build_array('report.create','report.save','report.freeze');end if;
   if cfg.export_enabled then ops:=ops||jsonb_build_array('export.request');end if;
  end if;
  result:=jsonb_set(jsonb_set(result,'{data,operations}',ops),'{data,runtimeEnabled}',to_jsonb(jsonb_array_length(ops)>1));
 end if;return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
end$$;


create or replace function "private"."study_reporting_artifact_authorize"("p_study" "uuid", "p_ref" "jsonb", "p_actor" "uuid", "p_client" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare r private.study_report_revisions%rowtype;e private.study_report_exports%rowtype;a private.study_artifacts%rowtype;begin
 if p_ref->>'type' not in ('reportContent','reportProjection','renderResources','reportExportBundle') then return private.study_analysis_artifact_authorize(p_study,p_ref,p_actor,p_client);end if;
 perform private.study_authorize(p_study,p_actor,p_client,'read');
 perform private.study_require((select disclosure_enabled from private.study_runtime_config where singleton),'CAPABILITY_UNAVAILABLE');
 select * into a from private.study_artifacts where study_id=p_study and id=(p_ref->>'id')::uuid;perform private.study_require(found and a.ref=p_ref,'REFERENCE_MISMATCH');
 if p_ref->>'type'='reportContent' then
  select * into r from private.study_report_revisions where study_id=p_study and content_artifact_id=a.id;
  perform private.study_require(found and r.template_id='lca.study-report.v1','DISCLOSURE_DENIED');perform private.study_report_rights(p_study,r.run_ids,r.analysis_ids,p_actor,p_client);
 else
  select * into e from private.study_report_exports where study_id=p_study and (projection_artifact_id=a.id or resources_artifact_id=a.id or bundle_artifact_id=a.id);
  perform private.study_require(found,'DISCLOSURE_DENIED');perform private.study_report_export_authorize(e.id,p_actor,p_client);
 end if;
 return jsonb_build_object('kind','artifactCapability','studyId',p_study,'artifactRef',a.ref,'storageBucket',a.bucket,'storageObjectPath',a.object_path);
end$$;






create function private.study_advanced_list(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
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
create function api.cmd_study_advanced_v1(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$begin
 perform private.study_advanced_envelope(p_request,true);perform private.study_require(private.study_client_allowed(nullif(auth.jwt()->>'client_id',''),'STUDY-WRITE-01'),'FORBIDDEN');
 case p_request->>'operation' when 'analysis.request' then return private.study_advanced_request(p_request);
 when 'task.cancel' then return private.study_advanced_task(p_request);
 when 'report.create','report.save','report.freeze' then return private.study_report_advanced_command(p_request);
 else return jsonb_build_object('ok',false,'code','CAPABILITY_UNAVAILABLE');end case;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);end$$;
create function api.qry_study_advanced_v1(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$declare actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');a private.study_advanced_analyses%rowtype;r private.study_report_revisions%rowtype;
 cfg private.study_advanced_config%rowtype;ops jsonb;profiles jsonb:='[]'::jsonb;begin
 perform private.study_advanced_envelope(p_request,false);perform private.study_require(private.study_client_allowed(client,'STUDY-READ-01'),'FORBIDDEN');
 case p_request->>'operation'
 when 'capability.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation']),'INVALID_REQUEST');select * into cfg from private.study_advanced_config where singleton;
  ops:='["capability.read","analysis.read","task.read","report.read","study.resources.list"]';
  if private.study_client_allowed(client,'STUDY-WRITE-01') then ops:=ops||'["task.cancel"]'::jsonb;end if;
  if private.study_client_allowed(client,'DB-CORE-READ-01') then
   ops:=ops||'["analysis.parameters.read"]'::jsonb;
   if (select disclosure_enabled from private.study_runtime_config where singleton) then ops:=ops||'["artifact.read"]'::jsonb;end if;
   if private.study_client_allowed(client,'STUDY-WRITE-01') then
    if cfg.sensitivity_enabled or cfg.uncertainty_enabled then ops:=ops||'["analysis.request"]'::jsonb;end if;
    if cfg.report_enabled then ops:=ops||'["report.create","report.save","report.freeze"]'::jsonb;end if;
   end if;
  end if;
  if cfg.sensitivity_enabled then profiles:=profiles||'["lca.study-sensitivity-oat.v1"]'::jsonb;end if;
  if cfg.uncertainty_enabled then profiles:=profiles||'["lca.study-uncertainty-bounded.v1"]'::jsonb;end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','capabilities','contractVersion','5.0.0','runtimeEnabled',cfg.sensitivity_enabled or cfg.uncertainty_enabled or cfg.report_enabled,
   'operations',ops,'analysisProfiles',profiles,'reportTemplates',case when cfg.report_enabled then '["lca.study-report.v2"]'::jsonb else '[]'::jsonb end));
 when 'analysis.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','analysisId']),'INVALID_REQUEST');select * into a from private.study_advanced_analyses where id=(p_request->>'analysisId')::uuid;
  perform private.study_require(found,'FORBIDDEN');perform private.study_advanced_rights(a.study_id,a.baseline_run_id,actor,client);
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','analysis','value',private.study_advanced_record(a.id)));
 when 'report.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','reportRevisionId']),'INVALID_REQUEST');select * into r from private.study_report_revisions where id=(p_request->>'reportRevisionId')::uuid;
  perform private.study_require(found and r.template_id='lca.study-report.v2','FORBIDDEN');perform private.study_report_advanced_rights(r.study_id,r.run_ids,r.analysis_ids,actor,client);
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','reportRevision','value',private.study_report_record(r.id)));
 when 'analysis.parameters.read' then return private.study_advanced_parameters(p_request);
 when 'task.read' then return private.study_advanced_task(p_request);
 when 'study.resources.list' then return private.study_advanced_list(p_request);
 when 'artifact.read' then return private.study_advanced_artifact_intent(p_request);
 else return jsonb_build_object('ok',false,'code','CAPABILITY_UNAVAILABLE');end case;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');end$$;

create or replace function "private"."study_advanced_envelope"("p_request" "jsonb", "p_write" boolean) RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $_$declare field text;value jsonb;entry jsonb;pattern text:='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';begin
 perform private.study_require(auth.uid() is not null and not coalesce(util.is_service_request(),false),'AUTH_REQUIRED');
 perform private.study_require(p_request->>'schemaVersion'='lca.study-api.v5' and octet_length(p_request::text)<=262144
  and private.study_text(p_request->'requestId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');
 if p_write then perform private.study_require(private.study_text(p_request->'idempotencyKey',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');end if;
 -- Issued domain references are opaque exact identities. PostgreSQL accepts
 -- UUID aliases, but resolving an alias would change the response binding
 -- after effects. Reject it before every domain cast, receipt or intent.
 foreach field in array array['target','resource','artifactRef'] loop
  if p_request ? field then
   perform private.study_require(jsonb_typeof(p_request->field)='object'
    and private.study_text(p_request->field->'id',36,pattern),'INVALID_REQUEST');
  end if;
 end loop;
 foreach field in array array['studyId','analysisId','baselineRunId','reportRevisionId','parentReportRevisionId','cursor'] loop
  if not p_request ? field then continue;end if;value:=p_request->field;
  if value='null'::jsonb and field in ('parentReportRevisionId','cursor') then continue;end if;
  perform private.study_require(private.study_text(value,36,pattern),'INVALID_REQUEST');
 end loop;
 if p_request ? 'runIds' or p_request ? 'analysisIds' then
 foreach field in array array['runIds','analysisIds'] loop
 if not p_request ? field then continue;end if;
  perform private.study_require(jsonb_typeof(p_request->field)='array','INVALID_REQUEST');
  perform private.study_require(jsonb_array_length(p_request->field)<=64,'INVALID_REQUEST');
  for entry in select * from jsonb_array_elements(p_request->field) loop
   perform private.study_require(private.study_text(entry,36,pattern),'INVALID_REQUEST');
  end loop;
 end loop;
 end if;
end$_$;





-- V5 review/export cannot reuse a renderer/version literal that misdescribes its facts.
create table private.study_advanced_review_config (
 singleton boolean primary key default true check(singleton),revision bigint not null default 1 check(revision>0),
 enabled boolean not null default false,export_enabled boolean not null default false,export_profile jsonb,qualification_evidence_ref text,
 check(not export_enabled or (enabled and export_profile is not null))
);
insert into private.study_advanced_review_config(singleton) values(true);
create function api.svc_study_review_advanced_configure_v1(p_expected_revision bigint,p_configuration jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$declare cfg private.study_advanced_review_config%rowtype;p jsonb:=p_configuration->'exportProfile';begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 perform private.study_require(private.study_keys(p_configuration,array['qualificationVersion','enabled','exportEnabled','exportProfile','evidenceRef'])
 and p_configuration->>'qualificationVersion'='lca.study-advanced-review-qualification.v1' and jsonb_typeof(p_configuration->'enabled')='boolean'
 and jsonb_typeof(p_configuration->'exportEnabled')='boolean' and private.study_text(p_configuration->'evidenceRef',512),'INVALID_REQUEST');
 if p<>'null'::jsonb then
  perform private.study_require(private.study_keys(p,array['issuerId','keyId','rendererVersion','viewModelVersion','rendererArtifactHash','policyId'])
   and private.study_text(p->'issuerId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$') and private.study_text(p->'keyId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$')
   and p->>'rendererVersion'='2.0.0' and p->>'viewModelVersion'='lca.study-report-view.v2'
   and private.study_text(p->'rendererArtifactHash',64,'^[0-9a-f]{64}$') and p->>'policyId'='lca.study-report-disclosure.v1','INVALID_REQUEST');
 end if;
 select * into cfg from private.study_advanced_review_config where singleton for update;perform private.study_require(cfg.revision=p_expected_revision,'REVISION_CONFLICT');
 update private.study_advanced_review_config set revision=revision+1,enabled=(p_configuration->>'enabled')::boolean,export_enabled=(p_configuration->>'exportEnabled')::boolean,
  export_profile=nullif(p,'null'::jsonb),qualification_evidence_ref=p_configuration->>'evidenceRef' where singleton returning * into cfg;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('revision',cfg.revision,'enabled',cfg.enabled,'qualificationVersion','lca.study-advanced-review-qualification.v1','evidenceRef',cfg.qualification_evidence_ref));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or check_violation or not_null_violation then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');end$$;
-- Resolve every indirect report reference before effects or old-wire responses.
create function private.study_review_family(p_request jsonb,p_template text) returns void
language plpgsql security definer set search_path='' as $$declare f text;rid uuid;v text;begin
 foreach f in array array['reportRevisionId','shareId','exportId','delegationId','finalizationId'] loop
  if not p_request ? f then continue;end if;v:=p_request->>f;
  if v is null then continue;end if;
  case f when 'reportRevisionId' then rid:=v::uuid;
   when 'shareId' then select report_id into rid from private.study_report_shares where id=v::uuid;
   when 'exportId' then select report_id into rid from private.study_review_exports where id=v::uuid;
   when 'delegationId' then select report_id into rid from private.study_review_delegations where id=v::uuid;
   when 'finalizationId' then select report_id into rid from private.study_report_finalizations where id=v::uuid;end case;
  perform private.study_require(exists(select 1 from private.study_report_revisions where id=rid and template_id=p_template),'FORBIDDEN');
 end loop;
 foreach f in array array['target','resource'] loop
  if not p_request ? f then continue;end if;v:=p_request->f->>'id';rid:=null;
  case p_request->f->>'type' when 'reportRevision' then rid:=v::uuid;
   when 'share' then select report_id into rid from private.study_report_shares where id=v::uuid;
   when 'export' then select report_id into rid from private.study_review_exports where id=v::uuid;
   when 'study' then continue;
   else perform private.study_require(false,'INVALID_REQUEST');end case;
  perform private.study_require(exists(select 1 from private.study_report_revisions where id=rid and template_id=p_template),'FORBIDDEN');
 end loop;
end$$;

create or replace function "private"."study_advanced_review_envelope"("p_request" "jsonb", "p_write" boolean) RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $_$declare field text;value jsonb;entry jsonb;pattern text:='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';begin
 perform private.study_require(auth.uid() is not null and not coalesce(util.is_service_request(),false),'AUTH_REQUIRED');
 perform private.study_require(p_request->>'schemaVersion'='lca.study-api.v5' and octet_length(p_request::text)<=262144
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
 foreach field in array array['reportRevisionId','shareId','exportId','delegationId','finalizationId','predecessorReviewId','memberId','recipientId'] loop
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


create or replace function "private"."study_advanced_review_new_intent"("p_request" "jsonb", "p_report" "uuid", "p_share" "uuid" DEFAULT NULL::"uuid", "p_export" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare r private.study_report_revisions%rowtype;e private.study_review_exports%rowtype;i private.study_review_intents%rowtype;st jsonb;cfg private.study_advanced_review_config%rowtype;actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');op text:=p_request->>'operation';begin
 select * into r from private.study_report_revisions where id=p_report;perform private.study_require(found and r.template_id='lca.study-report.v2' and p_request->>'schemaVersion'='lca.study-api.v5','REFERENCE_MISMATCH');
 if p_share is not null then perform private.study_review_share_check(p_share,actor,client,true);
 elsif op='export.download' then
  e:=private.study_review_export_check(p_export,actor,client);perform private.study_require(e.report_id=p_report,'REFERENCE_MISMATCH');
 else perform private.study_review_authorize(r.study_id,actor,client,case when op='export.request' then 'manage' else 'read' end);perform private.study_review_disclosure(r.id);end if;
 st:=private.study_review_state(r.id);
 if op='export.request' then
  perform private.study_require(st->>'acceptance'='current' and st->'finalization'->>'finalizationId'=p_request->>'finalizationId'
   and st->>'reviewStateHash'=p_request->>'expectedReviewStateHash','REVISION_CONFLICT');
  perform private.study_analysis_require_current(r.study_id,jsonb_build_object('runIds',r.run_ids));
  perform private.study_require((select export_enabled and export_profile is not null from private.study_advanced_review_config where singleton),'CAPABILITY_UNAVAILABLE');
 end if;
 select * into cfg from private.study_advanced_review_config where singleton for share;perform private.study_require(cfg.enabled,'CAPABILITY_UNAVAILABLE');
 perform pg_advisory_xact_lock(hashtextextended('study-review-intent:'||actor::text,906));
 perform private.study_require((select count(*) from private.study_review_intents where actor_id=actor and response is null and expires_at>clock_timestamp())<64,'CAPABILITY_UNAVAILABLE');
 insert into private.study_review_intents(study_id,report_id,actor_id,client_id,operation,request,share_id,finalization_id,grant_epoch,config_revision,reporting_config_revision,review_state_hash,
 export_id,projection_artifact_id,resources_artifact_id,bundle_artifact_id,disclosure_context_hash)
 values(r.study_id,r.id,actor,client,op,p_request,p_share,case when op='export.download' then e.finalization_id else (st->'finalization'->>'finalizationId')::uuid end,
 (select grant_epoch from private.studies where id=r.study_id),cfg.revision,(select revision from private.study_advanced_review_config where singleton),st->>'reviewStateHash',
 case when op='export.request' then gen_random_uuid() when op='export.download' then e.id end,case when op='export.request' then gen_random_uuid() end,
 case when op='export.request' then gen_random_uuid() end,case when op='export.request' then gen_random_uuid() end,
 private.study_reporting_digest('lca.study-review-disclosure.v1',jsonb_build_object('actorId',actor,'clientId',client,'reportRevisionId',r.id,'reportContentHash',r.content_hash,'reviewStateHash',st->>'reviewStateHash','shareId',p_share,'nonce',gen_random_uuid()))) returning * into i;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('kind','studyAdvancedReviewIntent','intentId',i.id,'operation',i.operation,'expiresAt',i.expires_at));
end$$;


create or replace function "private"."study_advanced_review_intent_check"("p_id" "uuid") RETURNS "private"."study_review_intents"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare i private.study_review_intents%rowtype;st jsonb;cfg private.study_advanced_review_config%rowtype;begin
 select * into i from private.study_review_intents where id=p_id;perform private.study_require(found and i.request->>'schemaVersion'='lca.study-api.v5' and exists(select 1 from private.study_report_revisions where id=i.report_id and template_id='lca.study-report.v2'),'CAPABILITY_UNAVAILABLE');
 perform 1 from private.studies where id=i.study_id for update;
 select * into i from private.study_review_intents where id=p_id;
 if i.share_id is not null then perform private.study_review_share_check(i.share_id,i.actor_id,i.client_id,true);
 elsif i.operation='export.download' then perform private.study_review_export_check(i.export_id,i.actor_id,i.client_id);
 else perform private.study_review_authorize(i.study_id,i.actor_id,i.client_id,case when i.operation='export.request' then 'manage' else 'read' end);perform private.study_review_disclosure(i.report_id);end if;
 if i.response is not null then return i;end if;
 select * into cfg from private.study_advanced_review_config where singleton for share;
 perform private.study_require(cfg.enabled and cfg.revision=i.config_revision and i.expires_at>clock_timestamp(),'CAPABILITY_UNAVAILABLE');
 perform private.study_require(i.grant_epoch=(select grant_epoch from private.studies where id=i.study_id),'FORBIDDEN');
 if i.operation='export.request' then
  st:=private.study_review_state(i.report_id);
  perform private.study_require(st->>'acceptance'='current' and st->'finalization'->>'finalizationId'=i.finalization_id::text and st->>'reviewStateHash'=i.review_state_hash,'REVISION_CONFLICT');
  perform private.study_analysis_require_current(i.study_id,jsonb_build_object('runIds',(select run_ids from private.study_report_revisions where id=i.report_id)));
  perform private.study_require((select export_enabled and export_profile is not null and revision=i.reporting_config_revision from private.study_advanced_review_config where singleton),'CAPABILITY_UNAVAILABLE');
 end if;return i;
end$$;


create or replace function "private"."study_advanced_review_actions"("p_type" "text", "p_id" "uuid", "p_actor" "uuid", "p_client" "text") RETURNS "jsonb"
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
 elsif p_type='study' then
  role:=private.study_review_authorize(p_id,p_actor,p_client,'read');
  if role='owner' and private.study_client_allowed(p_client,'STUDY-WRITE-01')
   and (select status='active' from private.studies where id=p_id) then ops:=jsonb_build_array('member.set');end if;return ops;
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
    if (select export_enabled and export_profile is not null from private.study_advanced_review_config where singleton) and not exists(select 1 from private.study_runs where id in(select jsonb_array_elements_text(r.run_ids)::uuid) and validity<>'current') then ops:=ops||jsonb_build_array('export.request');end if;
    if exists(select 1 from private.study_review_exports e where e.report_id=r.id and e.finalization_id=(st->'finalization'->>'finalizationId')::uuid and e.actor_id=p_actor
     and e.grant_epoch=(select grant_epoch from private.studies where id=r.study_id) and private.study_client_allowed(e.client_id,'STUDY-WRITE-01')) then ops:=ops||jsonb_build_array('share.create');end if;
   end if;
  end if;
 end if;return ops;
exception when raise_exception then return '[]'::jsonb;end$$;


create or replace function "api"."cmd_study_advanced_review_v1"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '15s'
    AS $_$
declare op text:=p_request->>'operation';actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');sid uuid;rid uuid;member uuid;newid uuid;head uuid;allowed text[];
 req jsonb:=(p_request-'schemaVersion'-'requestId'-'idempotencyKey')||jsonb_build_object('_verifiedClientId',client);prev private.study_command_receipts%rowtype;r private.study_report_revisions%rowtype;d private.study_review_delegations%rowtype;
 s private.study_report_shares%rowtype;e private.study_review_exports%rowtype;study private.studies%rowtype;st jsonb;result jsonb;value jsonb;ts timestamptz;
begin
 perform private.study_advanced_review_envelope(p_request,true);perform private.study_review_family(p_request,'lca.study-report.v2');
 perform private.study_require(op<>'member.set','CAPABILITY_UNAVAILABLE');
 case op
 when 'member.set' then allowed:=array['target','memberId','role'];sid:=(p_request->'target'->>'id')::uuid;
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
 perform private.study_review_authorize(sid,actor,client,case when op in ('member.set','report.finalize','export.request','share.create','share.revoke') then 'manage'
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
 select * into prev from private.study_command_receipts where actor_id=actor and operation=op and scope='v5:'||sid::text and idempotency_key=p_request->>'idempotencyKey';
 if found then
  perform private.study_require(prev.request=req,'IDEMPOTENCY_CONFLICT');
  if op='review.record' and client is not null then
   select * into d from private.study_review_delegations where id=(p_request->>'delegationId')::uuid;
   perform private.study_require(d.actor_id=actor and d.client_id=client and d.revoked_at is null and d.consumed_review_id::text=prev.response->'data'->'value'->>'reviewId','FORBIDDEN');
  end if;
  if op='export.request' and prev.response->'data'->>'kind'='studyAdvancedReviewIntent' then
   declare oldintent private.study_review_intents%rowtype;begin oldintent:=private.study_advanced_review_intent_check((prev.response->'data'->>'intentId')::uuid);if oldintent.response is not null then return oldintent.response;end if;end;
  end if;return private.study_review_refresh(prev.response);
 end if;
 perform private.study_require(study.status='active','FROZEN_REVISION');
 perform 1 from private.study_advanced_review_config where singleton and enabled for share;perform private.study_require(found,'CAPABILITY_UNAVAILABLE');
 if op='member.set' then
  perform private.study_require(private.study_keys(p_request->'target',array['type','id','expectedRevision']) and p_request->'target'->>'type'='study'
   and jsonb_typeof(p_request->'target'->'expectedRevision')='number' and (p_request->'target'->>'expectedRevision')::numeric=study.revision,'REVISION_CONFLICT');
  member:=(p_request->>'memberId')::uuid;
  perform private.study_require(member<>study.owner_id,'FORBIDDEN');
  perform private.study_require(p_request->'role'='null'::jsonb or p_request->>'role' in ('editor','reviewer','viewer'),'INVALID_REQUEST');
  perform private.study_require(study.team_id is not null or p_request->'role'='null'::jsonb or p_request->>'role'='reviewer','CAPABILITY_UNAVAILABLE');
  if p_request->'role'='null'::jsonb then delete from private.study_members where study_id=sid and actor_id=member;
  else
   if study.team_id is not null then perform 1 from private.roles where user_id=member and team_id=study.team_id and role in ('owner','admin','member') for share;perform private.study_require(found,'FORBIDDEN');end if;
   insert into private.study_members values(sid,member,p_request->>'role') on conflict(study_id,actor_id) do update set role=excluded.role;end if;
  update private.studies set revision=revision+1,grant_epoch=grant_epoch+1 where id=sid returning * into study;
  value:=jsonb_build_object('type','member','studyId',sid,'studyRevision',study.revision,'memberId',member,'role',p_request->'role');
 elsif op='comment.append' then
  perform private.study_require(private.study_text(p_request->'text',4096) and p_request->>'text' !~ '[<>]','INVALID_REQUEST');
  insert into private.study_report_comments(study_id,report_id,report_hash,actor_id,client_id,body) values(sid,r.id,r.content_hash,actor,client,p_request->>'text') returning id into newid;
  value:=jsonb_build_object('type','comment','value',private.study_comment_record(newid));
 elsif op in ('review.record','review.delegation.issue') then
  perform private.study_require(p_request->>'reviewClass'='internal' and p_request->>'decision' in ('approve','reject','withdraw'),'INVALID_REQUEST');
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
  perform private.study_require(p_request->>'rendererVersion'='2.0.0' and p_request->>'viewModelVersion'='lca.study-report-view.v2','CAPABILITY_UNAVAILABLE');
  result:=private.study_advanced_review_new_intent(p_request,r.id);value:=result->'data';
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
 insert into private.study_command_receipts values(actor,op,'v5:'||sid::text,p_request->>'idempotencyKey',req,result,clock_timestamp());return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range or check_violation or not_null_violation or invalid_datetime_format then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');end$_$;


create or replace function "api"."qry_study_advanced_review_v1"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '15s'
    AS $$
declare op text:=p_request->>'operation';actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');allowed text[];rid uuid;r private.study_report_revisions%rowtype;
 s private.study_report_shares%rowtype;e private.study_review_exports%rowtype;value jsonb;ops jsonb;allowed_member_roles jsonb:='[]'::jsonb;core_read boolean:=false;core_write boolean:=false;kind text;lim integer;afterid uuid;nextid uuid;ids uuid[];resource_id uuid;
 selection jsonb;epoch text;cur private.study_cursors%rowtype;items jsonb:='[]'::jsonb;more boolean;
begin
 perform private.study_advanced_review_envelope(p_request,false);perform private.study_review_family(p_request,'lca.study-report.v2');perform private.study_require(private.study_client_allowed(client,'STUDY-READ-01'),'FORBIDDEN');
 if op='capability.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation']),'INVALID_REQUEST');
  if not(select enabled from private.study_advanced_review_config where singleton) then
   value:=jsonb_build_object('type','capabilities','contractVersion','5.0.0','runtimeEnabled',false,'operations',jsonb_build_array('capability.read'),'finalizationProfiles','[]'::jsonb,'reviewClasses','[]'::jsonb,'disclosurePolicies','[]'::jsonb);
  else
   ops:='["capability.read","resource.actions","comment.list","review.list","review.delegation.list","report.current","report.view","export.read","export.download","share.read","share.view","share.download","share.list"]';
   if private.study_client_allowed(client,'STUDY-WRITE-01') then
    ops:=ops||'["comment.append","review.record","report.finalize","export.request","share.create","share.revoke"]'::jsonb;
    if client is null then ops:=ops||'["review.delegation.issue","review.delegation.revoke"]'::jsonb;end if;
   end if;
   value:=jsonb_build_object('type','capabilities','contractVersion','5.0.0','runtimeEnabled',true,'operations',ops,
   'finalizationProfiles',jsonb_build_array('lca.study-report-unreviewed.v1','lca.study-report-internal-review.v1'),'reviewClasses',jsonb_build_array('internal'),'disclosurePolicies',jsonb_build_array('lca.study-report-summary-share.v1'));
  end if;return jsonb_build_object('ok',true,'data',value);
 end if;
 perform private.study_require((select enabled from private.study_advanced_review_config where singleton),'CAPABILITY_UNAVAILABLE');
 case op
 when 'resource.actions' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','resource']) and private.study_keys(p_request->'resource',array['type','id'])
   and p_request->'resource'->>'type' in ('reportRevision','share','export'),'INVALID_REQUEST');
  ops:=private.study_advanced_review_actions(p_request->'resource'->>'type',(p_request->'resource'->>'id')::uuid,actor,client);
  if p_request->'resource'->>'type'='study' and ops ? 'member.set' then
   select case when team_id is null then '["reviewer"]'::jsonb else '["editor","reviewer","viewer"]'::jsonb end into allowed_member_roles
    from private.studies where id=(p_request->'resource'->>'id')::uuid;
  end if;
  -- Coarse Study permissions reuse the existing authority. They do not confer
  -- rights to a particular revision, source, target or artifact.
  if p_request->'resource'->>'type'='study' then
   begin
    perform private.study_authorize((p_request->'resource'->>'id')::uuid,actor,client,'read');core_read:=true;
   exception when raise_exception then null;end;
   begin
    perform private.study_authorize((p_request->'resource'->>'id')::uuid,actor,client,'write');
    select status='active' into core_write from private.studies where id=(p_request->'resource'->>'id')::uuid;
   exception when raise_exception then null;end;
  end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','actions','resource',p_request->'resource','actions',ops,'allowedMemberRoles',allowed_member_roles,
   'corePermissions',jsonb_build_object('read',core_read,'write',coalesce(core_write,false))));
 when 'share.read','share.view','share.download' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','shareId']),'INVALID_REQUEST');
  s:=private.study_review_share_check((p_request->>'shareId')::uuid,actor,client,op<>'share.read');
  if op='share.read' then value:=jsonb_build_object('type','share','value',private.study_review_share_record(s.id));else return private.study_advanced_review_new_intent(p_request,s.report_id,s.id);end if;
  return jsonb_build_object('ok',true,'data',value);
 when 'export.read','export.download' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','exportId']),'INVALID_REQUEST');
  e:=private.study_review_export_check((p_request->>'exportId')::uuid,actor,client);
  if op='export.download' then return private.study_advanced_review_new_intent(p_request,e.report_id,null,e.id);end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','export','value',e.record));
 when 'report.current','report.view' then allowed:=array['reportRevisionId','expectedContentHash'];
 when 'comment.list','review.list','review.delegation.list','share.list' then allowed:=array['reportRevisionId','expectedContentHash','cursor','limit'];
 else perform private.study_require(false,'CAPABILITY_UNAVAILABLE');end case;
 perform private.study_require(private.study_keys(p_request,allowed||array['schemaVersion','requestId','operation']),'INVALID_REQUEST');
 rid:=(p_request->>'reportRevisionId')::uuid;select * into r from private.study_report_revisions where study_report_revisions.id=rid;
 perform private.study_review_authorize(r.study_id,actor,client,case when op='share.list' then 'manage' when op='review.delegation.list' then 'review' else 'read' end);
 perform private.study_require(r.status='frozen' and r.content_hash=p_request->>'expectedContentHash','REFERENCE_MISMATCH');perform private.study_review_disclosure(r.id);
 if op='report.current' then return jsonb_build_object('ok',true,'data',jsonb_build_object('type','reportState','value',private.study_review_state(r.id)));end if;
 if op='report.view' then return private.study_advanced_review_new_intent(p_request,r.id);end if;
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


create or replace function "api"."svc_study_review_advanced_intent_resolve_v1"("p_intent_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare i private.study_review_intents%rowtype;r private.study_report_revisions%rowtype;s private.study_report_shares%rowtype;e private.study_review_exports%rowtype;
 st jsonb;producer jsonb;runs jsonb;analyses jsonb;issuer uuid;artifact jsonb;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');i:=private.study_advanced_review_intent_check(p_intent_id);
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
  select jsonb_agg(jsonb_build_object('analysis',private.study_advanced_record(a.id),'factsArtifact',private.study_private_artifact(i.study_id,a.facts_artifact_id),'sourceSnapshotRef',(select ar.ref from private.study_source_snapshots ss join private.study_artifacts ar on ar.id=ss.artifact_id where ss.id=a.source_snapshot_id)) order by x.n)
   into analyses from jsonb_array_elements_text(r.analysis_ids) with ordinality x(v,n) join private.study_advanced_analyses a on a.id=x.v::uuid and a.study_id=i.study_id;
  producer:=jsonb_build_object('kind','reportAdvancedCommandContext','intentId',i.id,'expiresAt',i.expires_at,'operation','export.request',
   'request',jsonb_build_object('schemaVersion','lca.study-api.v5','requestId',i.request->>'requestId','idempotencyKey',coalesce(i.request->>'idempotencyKey',i.id::text),
    'operation','export.request','reportRevisionId',r.id,'expectedContentHash',r.content_hash,'rendererVersion','2.0.0','viewModelVersion','lca.study-report-view.v2'),
   'studyId',i.study_id,'actorId',issuer,'clientId',null,'grantEpoch',i.grant_epoch,'generatedAt',i.created_at,'reportRevisionId',r.id,'contentArtifactId',null,
   'exportId',i.export_id,'projectionArtifactId',i.projection_artifact_id,'resourcesArtifactId',i.resources_artifact_id,'bundleArtifactId',i.bundle_artifact_id,
   'report',private.study_report_record(r.id),'contentArtifact',private.study_private_artifact(i.study_id,r.content_artifact_id),'runs',runs,'analyses',analyses,
   'factsBindingHash',private.study_reporting_digest('lca.study-report-facts-binding.v1',r.facts_refs),'disclosureContextHash',i.disclosure_context_hash,
   'exportProfile',(select export_profile from private.study_advanced_review_config where singleton));
 else
  select * into s from private.study_report_shares where id=i.share_id;select * into e from private.study_review_exports where id=s.export_id;
  artifact:=private.study_private_artifact(i.study_id,case when i.operation='share.view' then e.projection_artifact_id else e.bundle_artifact_id end)||jsonb_build_object('kind','artifactCapability');
 end if;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('kind','studyAdvancedReviewContext','intentId',i.id,'expiresAt',i.expires_at,'operation',i.operation,'actorId',i.actor_id,'clientId',i.client_id,
 'request',i.request,'currentState',st,'producerContext',producer,'share',private.study_review_share_record(s.id),'export',e.record,'artifact',artifact));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end$$;


create or replace function "api"."svc_study_review_advanced_intent_consume_v1"("p_intent_id" "uuid", "p_completion" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$declare i private.study_review_intents%rowtype;r private.study_report_revisions%rowtype;f jsonb;manifest jsonb;receipt jsonb;profile jsonb;record jsonb;result jsonb;projection uuid;resources uuid;bundle uuid;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');i:=private.study_advanced_review_intent_check(p_intent_id);
 select * into i from private.study_review_intents where id=p_intent_id for update;
 if i.response is not null then return i.response;end if;
 perform private.study_require(i.operation='export.request','INVALID_REQUEST');select * into r from private.study_report_revisions where id=i.report_id;
 f:=private.study_finalization_record(i.finalization_id);
 select export_profile into profile from private.study_advanced_review_config where singleton;
 perform private.study_require(private.study_keys(p_completion,array['kind','projectionArtifact','resourcesArtifact','bundleArtifact','manifest','receipt']) and p_completion->>'kind'='validatedReviewExport','REFERENCE_MISMATCH');
 manifest:=p_completion->'manifest';receipt:=p_completion->'receipt';
 perform private.study_require(private.study_keys(manifest,array['schemaVersion','issuerId','exportId','studyId','reportRevisionId','reportContentHash','actorId','clientId','grantEpoch','policyId','disclosureContextHash','generatedAt','validitySnapshot','reviewIds','finalization','renderer','files'])
  and manifest->>'schemaVersion'='lca.study-export-manifest.v3' and manifest->>'issuerId'=profile->>'issuerId' and manifest->>'exportId'=i.export_id::text
  and manifest->>'studyId'=i.study_id::text and manifest->>'reportRevisionId'=r.id::text and manifest->>'reportContentHash'=r.content_hash
  and manifest->>'actorId'=i.actor_id::text and (manifest->>'clientId') is not distinct from i.client_id
  and jsonb_typeof(manifest->'grantEpoch')='number' and (manifest->>'grantEpoch')::numeric=i.grant_epoch
  and manifest->>'policyId'='lca.study-report-disclosure.v1' and manifest->>'disclosureContextHash'=i.disclosure_context_hash
  and (manifest->>'generatedAt')::timestamptz=i.created_at and manifest->'validitySnapshot'=private.study_report_record(r.id)->'validitySnapshot'
  and manifest->'finalization'=f and manifest->'reviewIds'=f->'acceptedReviewIds' and (f->>'finalizedAt')::timestamptz<=i.created_at
  and manifest->'renderer'=jsonb_build_object('version','2.0.0','viewModelVersion','lca.study-report-view.v2','artifactHash',profile->>'rendererArtifactHash'),'REFERENCE_MISMATCH');
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
 projection:=private.study_report_store_produced(i.study_id,p_completion->'projectionArtifact',i.projection_artifact_id,'reportProjection','lca.study-report-view.v2','projection');
 resources:=private.study_report_store_produced(i.study_id,p_completion->'resourcesArtifact',i.resources_artifact_id,'renderResources','lca.study-export-manifest.v3','resources');
 bundle:=private.study_report_store_produced(i.study_id,p_completion->'bundleArtifact',i.bundle_artifact_id,'reportExportBundle','lca.study-export-bundle.v3','bundle');
 record:=jsonb_build_object('studyId',i.study_id,'reportRevisionId',r.id,'reportContentHash',r.content_hash,'exportId',i.export_id,'finalization',f,'generatedAt',i.created_at,
  'projectionRef',p_completion->'projectionArtifact'->'artifactRef','resourcesRef',p_completion->'resourcesArtifact'->'artifactRef','bundleRef',p_completion->'bundleArtifact'->'artifactRef','receipt',receipt);
 insert into private.study_review_exports(id,study_id,report_id,actor_id,client_id,grant_epoch,finalization_id,record,manifest,projection_artifact_id,resources_artifact_id,bundle_artifact_id)
  values(i.export_id,i.study_id,r.id,i.actor_id,i.client_id,i.grant_epoch,i.finalization_id,record,manifest,projection,resources,bundle);
 result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','export','value',record));update private.study_review_intents set response=result where id=i.id;
 update private.study_command_receipts set response=result where actor_id=i.actor_id and operation=i.operation and scope='v5:'||i.study_id::text and idempotency_key=i.request->>'idempotencyKey';return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range or check_violation or not_null_violation or invalid_datetime_format then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');end$_$;


create or replace function "api"."svc_study_review_advanced_intent_reconcile_v1"("p_intent_id" "uuid", "p_artifact_id" "uuid", "p_content_hash" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare i private.study_review_intents%rowtype;a private.study_artifacts%rowtype;expected_ref jsonb;state text:='unknown';begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
 perform private.study_require(p_intent_id is not null and p_artifact_id is not null and private.study_text(to_jsonb(p_content_hash),64,'^[0-9a-f]{64}$'),'INVALID_REQUEST');
 select * into i from private.study_review_intents where id=p_intent_id;
 if found and i.request->>'schemaVersion'='lca.study-api.v5' and exists(select 1 from private.study_report_revisions where id=i.report_id and template_id='lca.study-report.v2') then
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
 return jsonb_build_object('ok',true,'data',jsonb_build_object('schemaVersion','lca.study-review-reconcile.v1','intentId',p_intent_id,'artifactId',p_artifact_id,'state',state,'deletionPermitted',false));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end$_$;


create or replace function "api"."cmd_study_review_v1"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '15s'
    AS $_$
declare op text:=p_request->>'operation';actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');sid uuid;rid uuid;member uuid;newid uuid;head uuid;allowed text[];
 req jsonb:=(p_request-'schemaVersion'-'requestId'-'idempotencyKey')||jsonb_build_object('_verifiedClientId',client);prev private.study_command_receipts%rowtype;r private.study_report_revisions%rowtype;d private.study_review_delegations%rowtype;
 s private.study_report_shares%rowtype;e private.study_review_exports%rowtype;study private.studies%rowtype;st jsonb;result jsonb;value jsonb;ts timestamptz;
begin
 perform private.study_review_envelope(p_request,true);perform private.study_review_family(p_request,'lca.study-report.v1');
 case op
 when 'member.set' then allowed:=array['target','memberId','role'];sid:=(p_request->'target'->>'id')::uuid;
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
 perform private.study_review_authorize(sid,actor,client,case when op in ('member.set','report.finalize','export.request','share.create','share.revoke') then 'manage'
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
 select * into prev from private.study_command_receipts where actor_id=actor and operation=op and scope='v4:'||sid::text and idempotency_key=p_request->>'idempotencyKey';
 if found then
  perform private.study_require(prev.request=req,'IDEMPOTENCY_CONFLICT');
  if op='review.record' and client is not null then
   select * into d from private.study_review_delegations where id=(p_request->>'delegationId')::uuid;
   perform private.study_require(d.actor_id=actor and d.client_id=client and d.revoked_at is null and d.consumed_review_id::text=prev.response->'data'->'value'->>'reviewId','FORBIDDEN');
  end if;
  if op='export.request' and prev.response->'data'->>'kind'='studyReviewIntent' then
   declare oldintent private.study_review_intents%rowtype;begin oldintent:=private.study_review_intent_check((prev.response->'data'->>'intentId')::uuid);if oldintent.response is not null then return oldintent.response;end if;end;
  end if;return private.study_review_refresh(prev.response);
 end if;
 perform private.study_require(study.status='active','FROZEN_REVISION');
 perform 1 from private.study_review_config where singleton and enabled for share;perform private.study_require(found,'CAPABILITY_UNAVAILABLE');
 if op='member.set' then
  perform private.study_require(private.study_keys(p_request->'target',array['type','id','expectedRevision']) and p_request->'target'->>'type'='study'
   and jsonb_typeof(p_request->'target'->'expectedRevision')='number' and (p_request->'target'->>'expectedRevision')::numeric=study.revision,'REVISION_CONFLICT');
  member:=(p_request->>'memberId')::uuid;
  perform private.study_require(member<>study.owner_id,'FORBIDDEN');
  perform private.study_require(p_request->'role'='null'::jsonb or p_request->>'role' in ('editor','reviewer','viewer'),'INVALID_REQUEST');
  perform private.study_require(study.team_id is not null or p_request->'role'='null'::jsonb or p_request->>'role'='reviewer','CAPABILITY_UNAVAILABLE');
  if p_request->'role'='null'::jsonb then delete from private.study_members where study_id=sid and actor_id=member;
  else
   if study.team_id is not null then perform 1 from private.roles where user_id=member and team_id=study.team_id and role in ('owner','admin','member') for share;perform private.study_require(found,'FORBIDDEN');end if;
   insert into private.study_members values(sid,member,p_request->>'role') on conflict(study_id,actor_id) do update set role=excluded.role;end if;
  update private.studies set revision=revision+1,grant_epoch=grant_epoch+1 where id=sid returning * into study;
  value:=jsonb_build_object('type','member','studyId',sid,'studyRevision',study.revision,'memberId',member,'role',p_request->'role');
 elsif op='comment.append' then
  perform private.study_require(private.study_text(p_request->'text',4096) and p_request->>'text' !~ '[<>]','INVALID_REQUEST');
  insert into private.study_report_comments(study_id,report_id,report_hash,actor_id,client_id,body) values(sid,r.id,r.content_hash,actor,client,p_request->>'text') returning id into newid;
  value:=jsonb_build_object('type','comment','value',private.study_comment_record(newid));
 elsif op in ('review.record','review.delegation.issue') then
  perform private.study_require(p_request->>'reviewClass'='internal' and p_request->>'decision' in ('approve','reject','withdraw'),'INVALID_REQUEST');
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
  perform private.study_require(p_request->>'rendererVersion'='1.0.0' and p_request->>'viewModelVersion'='lca.study-report-view.v1','CAPABILITY_UNAVAILABLE');
  result:=private.study_review_new_intent(p_request,r.id);value:=result->'data';
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
 insert into private.study_command_receipts values(actor,op,'v4:'||sid::text,p_request->>'idempotencyKey',req,result,clock_timestamp());return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range or check_violation or not_null_violation or invalid_datetime_format then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');end$_$;


create or replace function "api"."qry_study_review_v1"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '15s'
    AS $$
declare op text:=p_request->>'operation';actor uuid:=auth.uid();client text:=nullif(auth.jwt()->>'client_id','');allowed text[];rid uuid;r private.study_report_revisions%rowtype;
 s private.study_report_shares%rowtype;e private.study_review_exports%rowtype;value jsonb;ops jsonb;allowed_member_roles jsonb:='[]'::jsonb;core_read boolean:=false;core_write boolean:=false;kind text;lim integer;afterid uuid;nextid uuid;ids uuid[];resource_id uuid;
 selection jsonb;epoch text;cur private.study_cursors%rowtype;items jsonb:='[]'::jsonb;more boolean;
begin
 perform private.study_review_envelope(p_request,false);perform private.study_review_family(p_request,'lca.study-report.v1');perform private.study_require(private.study_client_allowed(client,'STUDY-READ-01'),'FORBIDDEN');
 if op='capability.read' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation']),'INVALID_REQUEST');
  if not(select enabled from private.study_review_config where singleton) then
   value:=jsonb_build_object('type','capabilities','contractVersion','4.0.0','runtimeEnabled',false,'operations',jsonb_build_array('capability.read'),'finalizationProfiles','[]'::jsonb,'reviewClasses','[]'::jsonb,'disclosurePolicies','[]'::jsonb);
  else
   ops:='["capability.read","resource.actions","comment.list","review.list","review.delegation.list","report.current","report.view","export.read","export.download","share.read","share.view","share.download","share.list"]';
   if private.study_client_allowed(client,'STUDY-WRITE-01') then
    ops:=ops||'["member.set","comment.append","review.record","report.finalize","export.request","share.create","share.revoke"]'::jsonb;
    if client is null then ops:=ops||'["review.delegation.issue","review.delegation.revoke"]'::jsonb;end if;
   end if;
   value:=jsonb_build_object('type','capabilities','contractVersion','4.0.0','runtimeEnabled',true,'operations',ops,
   'finalizationProfiles',jsonb_build_array('lca.study-report-unreviewed.v1','lca.study-report-internal-review.v1'),'reviewClasses',jsonb_build_array('internal'),'disclosurePolicies',jsonb_build_array('lca.study-report-summary-share.v1'));
  end if;return jsonb_build_object('ok',true,'data',value);
 end if;
 perform private.study_require((select enabled from private.study_review_config where singleton),'CAPABILITY_UNAVAILABLE');
 case op
 when 'resource.actions' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','resource']) and private.study_keys(p_request->'resource',array['type','id'])
   and p_request->'resource'->>'type' in ('study','reportRevision','share','export'),'INVALID_REQUEST');
  ops:=private.study_review_actions(p_request->'resource'->>'type',(p_request->'resource'->>'id')::uuid,actor,client);
  if p_request->'resource'->>'type'='study' and ops ? 'member.set' then
   select case when team_id is null then '["reviewer"]'::jsonb else '["editor","reviewer","viewer"]'::jsonb end into allowed_member_roles
    from private.studies where id=(p_request->'resource'->>'id')::uuid;
  end if;
  -- Coarse Study permissions reuse the existing authority. They do not confer
  -- rights to a particular revision, source, target or artifact.
  if p_request->'resource'->>'type'='study' then
   begin
    perform private.study_authorize((p_request->'resource'->>'id')::uuid,actor,client,'read');core_read:=true;
   exception when raise_exception then null;end;
   begin
    perform private.study_authorize((p_request->'resource'->>'id')::uuid,actor,client,'write');
    select status='active' into core_write from private.studies where id=(p_request->'resource'->>'id')::uuid;
   exception when raise_exception then null;end;
  end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','actions','resource',p_request->'resource','actions',ops,'allowedMemberRoles',allowed_member_roles,
   'corePermissions',jsonb_build_object('read',core_read,'write',coalesce(core_write,false))));
 when 'share.read','share.view','share.download' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','shareId']),'INVALID_REQUEST');
  s:=private.study_review_share_check((p_request->>'shareId')::uuid,actor,client,op<>'share.read');
  if op='share.read' then value:=jsonb_build_object('type','share','value',private.study_review_share_record(s.id));else return private.study_review_new_intent(p_request,s.report_id,s.id);end if;
  return jsonb_build_object('ok',true,'data',value);
 when 'export.read','export.download' then
  perform private.study_require(private.study_keys(p_request,array['schemaVersion','requestId','operation','exportId']),'INVALID_REQUEST');
  e:=private.study_review_export_check((p_request->>'exportId')::uuid,actor,client);
  if op='export.download' then return private.study_review_new_intent(p_request,e.report_id,null,e.id);end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('type','export','value',e.record));
 when 'report.current','report.view' then allowed:=array['reportRevisionId','expectedContentHash'];
 when 'comment.list','review.list','review.delegation.list','share.list' then allowed:=array['reportRevisionId','expectedContentHash','cursor','limit'];
 else perform private.study_require(false,'CAPABILITY_UNAVAILABLE');end case;
 perform private.study_require(private.study_keys(p_request,allowed||array['schemaVersion','requestId','operation']),'INVALID_REQUEST');
 rid:=(p_request->>'reportRevisionId')::uuid;select * into r from private.study_report_revisions where study_report_revisions.id=rid;
 perform private.study_review_authorize(r.study_id,actor,client,case when op='share.list' then 'manage' when op='review.delegation.list' then 'review' else 'read' end);
 perform private.study_require(r.status='frozen' and r.content_hash=p_request->>'expectedContentHash','REFERENCE_MISMATCH');perform private.study_review_disclosure(r.id);
 if op='report.current' then return jsonb_build_object('ok',true,'data',jsonb_build_object('type','reportState','value',private.study_review_state(r.id)));end if;
 if op='report.view' then return private.study_review_new_intent(p_request,r.id);end if;
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


create or replace function "api"."svc_study_review_intent_resolve_v1"("p_intent_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare i private.study_review_intents%rowtype;r private.study_report_revisions%rowtype;s private.study_report_shares%rowtype;e private.study_review_exports%rowtype;
 st jsonb;producer jsonb;runs jsonb;analyses jsonb;issuer uuid;artifact jsonb;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');perform private.study_require(exists(select 1 from private.study_review_intents guard_intent join private.study_report_revisions guard_report on guard_report.id=guard_intent.report_id where guard_intent.id=p_intent_id and guard_report.template_id='lca.study-report.v1' and guard_intent.request->>'schemaVersion'='lca.study-api.v4'),'CAPABILITY_UNAVAILABLE');i:=private.study_review_intent_check(p_intent_id);
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
  select jsonb_agg(jsonb_build_object('analysis',private.study_analysis_record(a.id),'factsArtifact',private.study_private_artifact(i.study_id,a.facts_artifact_id)) order by x.n)
   into analyses from jsonb_array_elements_text(r.analysis_ids) with ordinality x(v,n) join private.study_analyses a on a.id=x.v::uuid and a.study_id=i.study_id;
  producer:=jsonb_build_object('kind','reportCommandContext','intentId',i.id,'expiresAt',i.expires_at,'operation','export.request',
   'request',jsonb_build_object('schemaVersion','lca.study-api.v3','requestId',i.request->>'requestId','idempotencyKey',coalesce(i.request->>'idempotencyKey',i.id::text),
    'operation','export.request','reportRevisionId',r.id,'expectedContentHash',r.content_hash,'rendererVersion','1.0.0','viewModelVersion','lca.study-report-view.v1'),
   'studyId',i.study_id,'actorId',issuer,'clientId',null,'grantEpoch',i.grant_epoch,'generatedAt',i.created_at,'reportRevisionId',r.id,'contentArtifactId',null,
   'exportId',i.export_id,'projectionArtifactId',i.projection_artifact_id,'resourcesArtifactId',i.resources_artifact_id,'bundleArtifactId',i.bundle_artifact_id,
   'report',private.study_report_record(r.id),'contentArtifact',private.study_private_artifact(i.study_id,r.content_artifact_id),'runs',runs,'analyses',analyses,
   'factsBindingHash',private.study_reporting_digest('lca.study-report-facts-binding.v1',r.facts_refs),'disclosureContextHash',i.disclosure_context_hash,
   'exportProfile',(select export_profile from private.study_reporting_config where singleton));
 else
  select * into s from private.study_report_shares where id=i.share_id;select * into e from private.study_review_exports where id=s.export_id;
  artifact:=private.study_private_artifact(i.study_id,case when i.operation='share.view' then e.projection_artifact_id else e.bundle_artifact_id end)||jsonb_build_object('kind','artifactCapability');
 end if;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('kind','studyReviewContext','intentId',i.id,'expiresAt',i.expires_at,'operation',i.operation,'actorId',i.actor_id,'clientId',i.client_id,
 'request',i.request,'currentState',st,'producerContext',producer,'share',private.study_review_share_record(s.id),'export',e.record,'artifact',artifact));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end$$;


create or replace function "api"."svc_study_review_intent_consume_v1"("p_intent_id" "uuid", "p_completion" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$declare i private.study_review_intents%rowtype;r private.study_report_revisions%rowtype;f jsonb;manifest jsonb;receipt jsonb;profile jsonb;record jsonb;result jsonb;projection uuid;resources uuid;bundle uuid;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');perform private.study_require(exists(select 1 from private.study_review_intents guard_intent join private.study_report_revisions guard_report on guard_report.id=guard_intent.report_id where guard_intent.id=p_intent_id and guard_report.template_id='lca.study-report.v1' and guard_intent.request->>'schemaVersion'='lca.study-api.v4'),'CAPABILITY_UNAVAILABLE');i:=private.study_review_intent_check(p_intent_id);
 select * into i from private.study_review_intents where id=p_intent_id for update;
 if i.response is not null then return i.response;end if;
 perform private.study_require(i.operation='export.request','INVALID_REQUEST');select * into r from private.study_report_revisions where id=i.report_id;
 f:=private.study_finalization_record(i.finalization_id);
 select export_profile into profile from private.study_reporting_config where singleton;
 perform private.study_require(private.study_keys(p_completion,array['kind','projectionArtifact','resourcesArtifact','bundleArtifact','manifest','receipt']) and p_completion->>'kind'='validatedReviewExport','REFERENCE_MISMATCH');
 manifest:=p_completion->'manifest';receipt:=p_completion->'receipt';
 perform private.study_require(private.study_keys(manifest,array['schemaVersion','issuerId','exportId','studyId','reportRevisionId','reportContentHash','actorId','clientId','grantEpoch','policyId','disclosureContextHash','generatedAt','validitySnapshot','reviewIds','finalization','renderer','files'])
  and manifest->>'schemaVersion'='lca.study-export-manifest.v2' and manifest->>'issuerId'=profile->>'issuerId' and manifest->>'exportId'=i.export_id::text
  and manifest->>'studyId'=i.study_id::text and manifest->>'reportRevisionId'=r.id::text and manifest->>'reportContentHash'=r.content_hash
  and manifest->>'actorId'=i.actor_id::text and (manifest->>'clientId') is not distinct from i.client_id
  and jsonb_typeof(manifest->'grantEpoch')='number' and (manifest->>'grantEpoch')::numeric=i.grant_epoch
  and manifest->>'policyId'='lca.study-report-disclosure.v1' and manifest->>'disclosureContextHash'=i.disclosure_context_hash
  and (manifest->>'generatedAt')::timestamptz=i.created_at and manifest->'validitySnapshot'=private.study_report_record(r.id)->'validitySnapshot'
  and manifest->'finalization'=f and manifest->'reviewIds'=f->'acceptedReviewIds' and (f->>'finalizedAt')::timestamptz<=i.created_at
  and manifest->'renderer'=jsonb_build_object('version','1.0.0','viewModelVersion','lca.study-report-view.v1','artifactHash',profile->>'rendererArtifactHash'),'REFERENCE_MISMATCH');
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
 projection:=private.study_report_store_produced(i.study_id,p_completion->'projectionArtifact',i.projection_artifact_id,'reportProjection','lca.study-report-view.v1','projection');
 resources:=private.study_report_store_produced(i.study_id,p_completion->'resourcesArtifact',i.resources_artifact_id,'renderResources','lca.study-export-manifest.v2','resources');
 bundle:=private.study_report_store_produced(i.study_id,p_completion->'bundleArtifact',i.bundle_artifact_id,'reportExportBundle','lca.study-export-bundle.v2','bundle');
 record:=jsonb_build_object('studyId',i.study_id,'reportRevisionId',r.id,'reportContentHash',r.content_hash,'exportId',i.export_id,'finalization',f,'generatedAt',i.created_at,
  'projectionRef',p_completion->'projectionArtifact'->'artifactRef','resourcesRef',p_completion->'resourcesArtifact'->'artifactRef','bundleRef',p_completion->'bundleArtifact'->'artifactRef','receipt',receipt);
 insert into private.study_review_exports(id,study_id,report_id,actor_id,client_id,grant_epoch,finalization_id,record,manifest,projection_artifact_id,resources_artifact_id,bundle_artifact_id)
  values(i.export_id,i.study_id,r.id,i.actor_id,i.client_id,i.grant_epoch,i.finalization_id,record,manifest,projection,resources,bundle);
 result:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','export','value',record));update private.study_review_intents set response=result where id=i.id;
 update private.study_command_receipts set response=result where actor_id=i.actor_id and operation=i.operation and scope='v4:'||i.study_id::text and idempotency_key=i.request->>'idempotencyKey';return result;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range or check_violation or not_null_violation or invalid_datetime_format then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');end$_$;


create or replace function "api"."svc_study_report_advanced_intent_resolve_v1"("p_intent_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare i private.study_report_intents%rowtype;r private.study_report_revisions%rowtype;runids jsonb;analysisids jsonb;runs jsonb;analyses jsonb;begin
 perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');i:=private.study_report_advanced_intent_check(p_intent_id);
 if i.response is not null then return i.response;end if;
 if i.operation='report.create' then runids:=i.request->'runIds';analysisids:=i.request->'analysisIds';
 else select * into r from private.study_report_revisions where id=i.report_id;runids:=r.run_ids;analysisids:=r.analysis_ids;end if;
 select jsonb_agg(jsonb_build_object('run',private.study_record('run',rn.id),'revision',private.study_record('studyRevision',rn.study_revision_id),
 'scenario',private.study_record('scenarioRevision',rn.scenario_id),'preparation',private.study_record('modelPreparation',rn.preparation_id),
 'preparedArtifact',private.study_private_artifact(i.study_id,p.input_artifact_id),'resultArtifact',private.study_private_artifact(i.study_id,rn.result_artifact_id)) order by e.n)
 into runs from jsonb_array_elements_text(runids) with ordinality e(v,n) join private.study_runs rn on rn.id=e.v::uuid and rn.study_id=i.study_id
 join private.study_model_preparations p on p.id=rn.preparation_id;
 select jsonb_agg(jsonb_build_object('analysis',private.study_advanced_record(a.id),'factsArtifact',private.study_private_artifact(i.study_id,a.facts_artifact_id),'sourceSnapshotRef',(select ar.ref from private.study_source_snapshots ss join private.study_artifacts ar on ar.id=ss.artifact_id where ss.id=a.source_snapshot_id)) order by e.n)
 into analyses from jsonb_array_elements_text(analysisids) with ordinality e(v,n) join private.study_advanced_analyses a on a.id=e.v::uuid and a.study_id=i.study_id;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('kind','reportAdvancedCommandContext','intentId',i.id,'expiresAt',i.expires_at,'operation',i.operation,
 'request',i.request,'studyId',i.study_id,'actorId',i.actor_id,'clientId',i.client_id,'grantEpoch',i.grant_epoch,'generatedAt',i.created_at,
 'reportRevisionId',i.report_id,'contentArtifactId',i.content_artifact_id,'exportId',i.export_id,'projectionArtifactId',i.projection_artifact_id,
 'resourcesArtifactId',i.resources_artifact_id,'bundleArtifactId',i.bundle_artifact_id,'report',i.report_snapshot,
 'contentArtifact',case when r.id is not null then private.study_private_artifact(i.study_id,r.content_artifact_id) end,'runs',runs,'analyses',analyses,
 'exportProfile',case when i.operation='export.request' then (select export_profile from private.study_reporting_config where singleton) end,
 'disclosureContextHash',case when i.operation='export.request' then private.study_report_disclosure_context(i) end,
 'factsBindingHash',private.study_reporting_digest('lca.study-report-facts-binding.v1',private.study_report_advanced_rights(i.study_id,runids,analysisids,i.actor_id,i.client_id))));
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end$$;





-- Final exact ACL/manifest registration after every new function exists.
do $$declare n text;f record;ident text;begin
 foreach n in array array['study_advanced_config','study_advanced_analyses','study_advanced_parameter_intents','study_report_advanced_analyses','study_advanced_review_config'] loop
  execute format('alter table private.%I enable row level security',n);execute format('alter table private.%I force row level security',n);
  execute format('revoke all on private.%I from public,anon,authenticated,service_role',n);
 end loop;
 for f in select p.oid::regprocedure id from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname=any(array['study_advanced_artifact_authorize','study_advanced_artifact_intent','study_advanced_baseline','study_advanced_config_hash','study_advanced_config_valid','study_advanced_envelope','study_advanced_immutable','study_advanced_list','study_advanced_lock_job','study_advanced_number','study_advanced_parameters','study_advanced_record','study_advanced_request','study_advanced_review_actions','study_advanced_review_envelope','study_advanced_review_intent_check','study_advanced_review_new_intent','study_advanced_rights','study_advanced_task','study_report_advanced_command','study_report_advanced_content_valid','study_report_advanced_intent_check','study_report_advanced_rights','study_report_advanced_validation_check','study_review_family']) loop
  execute format('revoke all on function %s from public,anon,authenticated,service_role',f.id);
 end loop;
 for f in select p.oid::regprocedure id,p.proname,pg_catalog.oidvectortypes(p.proargtypes) args from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='api' and p.proname=any(array['cmd_study_advanced_review_v1','cmd_study_advanced_v1','qry_study_advanced_review_v1','qry_study_advanced_v1','svc_study_advanced_configure_v1','svc_study_analysis_advanced_complete_v1','svc_study_analysis_advanced_fail_v1','svc_study_analysis_advanced_read_input_v1','svc_study_analysis_advanced_reconcile_v1','svc_study_analysis_parameters_resolve_v1','svc_study_report_advanced_intent_consume_v1','svc_study_report_advanced_intent_reconcile_v1','svc_study_report_advanced_intent_resolve_v1','svc_study_review_advanced_configure_v1','svc_study_review_advanced_intent_consume_v1','svc_study_review_advanced_intent_reconcile_v1','svc_study_review_advanced_intent_resolve_v1']) loop
  execute format('revoke all on function %s from public,anon,authenticated,service_role',f.id);execute format('grant execute on function %s to %I',f.id,case when f.proname like 'svc_%' then 'service_role' else 'authenticated' end);
  ident:=format('api.%I(%s)',f.proname,f.args);insert into private.api_capability_grants values(ident,case when f.proname like 'svc_%' then 'STUDY-SERVICE-01' when f.proname like 'cmd_%' then 'STUDY-WRITE-01' else 'STUDY-READ-01' end,false,f.proname not like 'svc_%',f.proname like 'svc_%');
 end loop;
end$$;
notify pgrst,'reload schema';
commit;
