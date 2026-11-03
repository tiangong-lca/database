-- Database #894: durable research identities. Queue admission is W06, not an
-- implicit runtime enablement. No OAuth client receives a capability here.
begin;

-- Activation is a separately qualified W06 deployment action. This migration
-- registers no active algorithm/profile and broadens no client capability.
create table private.study_profiles (
  profile_id text primary key check(profile_id='lca.study-explicit-v1'),
  calculation_fingerprint text not null references private.lca_calculation_contracts(fingerprint),
  enabled boolean not null default false
);

create table private.studies (
  id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id),
  team_id uuid references private.teams(id), title text not null check(length(btrim(title)) between 1 and 512),
  status text not null default 'active' check(status in ('active','archived')),
  revision bigint not null default 1 check(revision between 1 and 9007199254740991),
  grant_epoch bigint not null default 1 check(grant_epoch > 0), current_revision_id uuid,
  created_at timestamptz not null default clock_timestamp()
);
create table private.study_members (
  study_id uuid not null references private.studies(id), actor_id uuid not null references auth.users(id),
  role text not null check(role in ('owner','editor','viewer')),
  primary key(study_id,actor_id)
);
create table private.study_artifacts (
  id uuid primary key, study_id uuid not null references private.studies(id),
  ref jsonb not null check(jsonb_typeof(ref)='object'),
  bucket text not null check(length(bucket) between 1 and 128),
  object_path text not null check(length(object_path) between 1 and 1024),
  created_at timestamptz not null default clock_timestamp(), unique(study_id,id),
  check(ref->>'id'=id::text), check(ref->>'digestScope'='artifact_bytes_sha256'),
  check(ref->>'contentHash' ~ '^[0-9a-f]{64}$'),
  check((ref->>'byteSize')::bigint between 1 and 4194304)
);
create table private.study_source_acquisitions (
  id uuid primary key, study_id uuid not null references private.studies(id),
  origin_ref jsonb not null, requested_by uuid not null references auth.users(id),
  job_id uuid not null unique references private.worker_jobs(id), snapshot_id uuid,
  unique(study_id,id)
);
create table private.study_source_snapshots (
  id uuid primary key, study_id uuid not null references private.studies(id),
  acquisition_id uuid not null unique, origin_ref jsonb not null,
  artifact_id uuid not null, license_ref text not null, issuer_id text not null,
  observed_at timestamptz not null, source_authorization jsonb not null check(jsonb_typeof(source_authorization)='object'), unique(study_id,id),
  foreign key(study_id,acquisition_id) references private.study_source_acquisitions(study_id,id),
  foreign key(study_id,artifact_id) references private.study_artifacts(study_id,id)
);
alter table private.study_source_acquisitions add foreign key(study_id,snapshot_id)
  references private.study_source_snapshots(study_id,id);
create table private.study_model_preparations (
  id uuid primary key, study_id uuid not null references private.studies(id),
  source jsonb not null, source_document jsonb not null, source_snapshot_id uuid, source_scenario_id uuid,
  source_study_revision_id uuid, source_parent_scenario_id uuid,
  method_refs jsonb not null check(jsonb_typeof(method_refs)='array'),
  profile_id text not null references private.study_profiles(profile_id), calculation_contract_ref jsonb not null,
  job_id uuid not null unique references private.worker_jobs(id),
  model_ref jsonb, input_artifact_id uuid, input_hash text check(input_hash ~ '^[0-9a-f]{64}$'),
  unique(study_id,id), foreign key(study_id,input_artifact_id) references private.study_artifacts(study_id,id),
  foreign key(study_id,source_snapshot_id) references private.study_source_snapshots(study_id,id),
  check((model_ref is null)=(input_artifact_id is null)),
  check(model_ref is not null or input_hash is null),
  check(coalesce((source->>'type'='modelSourceSnapshot' and source_snapshot_id is not null and source_scenario_id is null and source->>'snapshotId'=source_snapshot_id::text)
    or (source->>'type'='scenarioRevision' and source_scenario_id is not null and source_snapshot_id is null and source_study_revision_id is not null and source->>'scenarioRevisionId'=source_scenario_id::text),false)),
  check(calculation_contract_ref->>'kind'='calculation_contract' and calculation_contract_ref->>'schema'='lca.calculation-contract.v1' and calculation_contract_ref->>'sha256' ~ '^[0-9a-f]{64}$')
);
create table private.study_revisions (
  id uuid primary key default gen_random_uuid(), study_id uuid not null references private.studies(id),
  parent_revision_id uuid, revision bigint not null default 1 check(revision between 1 and 9007199254740991),
  status text not null default 'draft' check(status in ('draft','frozen')),
  content_hash text not null check(content_hash ~ '^[0-9a-f]{64}$'), definition jsonb not null,
  preparation_id uuid not null, model_ref jsonb not null,
  validation text not null default 'not_checked' check(validation in ('not_checked','passed')),
  validation_evidence jsonb, unique(study_id,id), check(parent_revision_id is distinct from id),
  foreign key(study_id,parent_revision_id) references private.study_revisions(study_id,id),
  foreign key(study_id,preparation_id) references private.study_model_preparations(study_id,id),
  check((status='frozen')=(validation='passed')),
  check((validation='passed')=(validation_evidence is not null))
);
alter table private.studies add foreign key(id,current_revision_id) references private.study_revisions(study_id,id);
create table private.study_scenarios (
  id uuid primary key default gen_random_uuid(), scenario_id uuid not null default gen_random_uuid(),
  study_id uuid not null references private.studies(id), study_revision_id uuid not null,
  parent_scenario_id uuid, revision bigint not null default 1 check(revision between 1 and 9007199254740991),
  status text not null default 'draft' check(status in ('draft','frozen')),
  content_hash text not null check(content_hash ~ '^[0-9a-f]{64}$'),
  overrides jsonb not null check(jsonb_typeof(overrides)='array' and jsonb_array_length(overrides)<=256),
  preparation_id uuid, effective_model_ref jsonb, unique(study_id,id), check(parent_scenario_id is distinct from id),
  foreign key(study_id,study_revision_id) references private.study_revisions(study_id,id),
  foreign key(study_id,parent_scenario_id) references private.study_scenarios(study_id,id),
  foreign key(study_id,preparation_id) references private.study_model_preparations(study_id,id),
  check((status='frozen')=(preparation_id is not null and effective_model_ref is not null))
);
alter table private.study_model_preparations add foreign key(study_id,source_study_revision_id)
  references private.study_revisions(study_id,id), add foreign key(study_id,source_parent_scenario_id)
  references private.study_scenarios(study_id,id), add foreign key(study_id,source_scenario_id) references private.study_scenarios(study_id,id);
create table private.study_runs (
  id uuid primary key, study_id uuid not null references private.studies(id), study_revision_id uuid not null,
  scenario_id uuid not null, preparation_id uuid not null, input_hash text not null check(input_hash ~ '^[0-9a-f]{64}$'),
  model_ref jsonb not null, profile_id text not null, calculation_contract_ref jsonb not null,
  job_id uuid not null unique references private.worker_jobs(id), result_artifact_id uuid,
  validity text not null default 'current' check(validity in ('current','superseded','withdrawn','unknown')),
  validity_checked_at timestamptz not null default clock_timestamp(),
  unique(study_id,id), foreign key(study_id,study_revision_id) references private.study_revisions(study_id,id),
  foreign key(study_id,scenario_id) references private.study_scenarios(study_id,id),
  foreign key(study_id,preparation_id) references private.study_model_preparations(study_id,id),
  foreign key(study_id,result_artifact_id) references private.study_artifacts(study_id,id)
);
create table private.study_command_receipts (
  actor_id uuid not null references auth.users(id), operation text not null, scope text not null,
  idempotency_key text not null check(length(idempotency_key) between 1 and 128),
  request jsonb not null, response jsonb not null, created_at timestamptz not null default clock_timestamp(),
  primary key(actor_id,operation,scope,idempotency_key)
);
create table private.study_validation_intents (
  id uuid primary key default gen_random_uuid(), study_id uuid not null references private.studies(id),
  revision_id uuid not null, actor_id uuid not null references auth.users(id), client_id text,
  binding jsonb not null, expires_at timestamptz not null default clock_timestamp()+interval '2 minutes',
  response jsonb, consumed_at timestamptz,
  foreign key(study_id,revision_id) references private.study_revisions(study_id,id)
);
create table private.study_service_receipts (
  operation text not null, study_id uuid not null references private.studies(id),
  idempotency_key text not null check(length(idempotency_key) between 1 and 128),
  job_id uuid not null references private.worker_jobs(id), lease_token uuid not null,
  request jsonb not null, response jsonb not null,
  primary key(operation,study_id,idempotency_key)
);
create table private.study_cursors (
  id uuid primary key default gen_random_uuid(), actor_id uuid not null references auth.users(id), client_id text,
  selection jsonb not null, access_epoch text not null, after_id uuid not null,
  expires_at timestamptz not null default clock_timestamp()+interval '5 minutes'
);
-- Exact-ID uniqueness already supports the second key of composite Study FKs;
-- these indexes cover the remaining foreign-reference and actor-list lookups.
create index study_profile_calculation_idx on private.study_profiles(calculation_fingerprint);
create index study_owner_idx on private.studies(owner_id);
create index study_team_idx on private.studies(team_id);
create index study_current_revision_idx on private.studies(current_revision_id);
create index study_member_actor_idx on private.study_members(actor_id,study_id);
create index study_acquisition_actor_idx on private.study_source_acquisitions(requested_by);
create index study_acquisition_snapshot_idx on private.study_source_acquisitions(snapshot_id);
create index study_snapshot_artifact_idx on private.study_source_snapshots(artifact_id);
create index study_preparation_source_snapshot_idx on private.study_model_preparations(source_snapshot_id);
create index study_preparation_source_scenario_idx on private.study_model_preparations(source_scenario_id);
create index study_preparation_source_revision_idx on private.study_model_preparations(source_study_revision_id);
create index study_preparation_source_parent_idx on private.study_model_preparations(source_parent_scenario_id);
create index study_preparation_input_idx on private.study_model_preparations(input_artifact_id);
create index study_preparation_profile_idx on private.study_model_preparations(profile_id);
create index study_revision_parent_idx on private.study_revisions(parent_revision_id);
create index study_revision_preparation_idx on private.study_revisions(preparation_id);
create index study_scenario_revision_idx on private.study_scenarios(study_revision_id);
create index study_scenario_parent_idx on private.study_scenarios(parent_scenario_id);
create index study_scenario_preparation_idx on private.study_scenarios(preparation_id);
create index study_run_revision_idx on private.study_runs(study_revision_id);
create index study_run_scenario_idx on private.study_runs(scenario_id);
create index study_run_preparation_idx on private.study_runs(preparation_id);
create index study_run_result_idx on private.study_runs(result_artifact_id);
create index study_intent_actor_idx on private.study_validation_intents(actor_id);
create index study_intent_revision_idx on private.study_validation_intents(revision_id);
create index study_service_receipt_study_idx on private.study_service_receipts(study_id);
create index study_service_receipt_job_idx on private.study_service_receipts(job_id);
create index study_cursor_actor_idx on private.study_cursors(actor_id);
create index study_cursor_expiry_idx on private.study_cursors(expires_at);

-- These are identity hashes of Database-owned normalized research documents,
-- never Worker calculation fingerprints or input/model/artifact byte hashes.
create function private.study_content_hash(p_domain text,p_document jsonb) returns text
language sql immutable set search_path='' as $$
  select encode(extensions.digest(convert_to(p_domain || chr(10) || p_document::text,'UTF8'),'sha256'),'hex')
$$;
create function private.study_require(p_condition boolean,p_code text) returns void
language plpgsql set search_path='' as $$ begin
  if p_condition is not true then raise exception using errcode='P0001',message=p_code; end if;
end $$;
create function private.study_client_allowed(p_client text,p_capability text) returns boolean
language plpgsql security definer set search_path='' as $$ begin
  if p_client is null then return true; end if;
  perform 1 from private.oauth_client_registry where client_id=p_client and enabled for share;
  if not found then return false; end if;
  perform 1 from private.oauth_client_capability_grants where client_id=p_client and allowed and capability_id=p_capability for share;
  return found;
end $$;
create function private.study_team_member(p_actor uuid,p_team uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select p_team is null or exists(select 1 from private.roles r where r.user_id=p_actor
    and r.team_id=p_team and r.role in ('owner','admin','member'))
$$;
create function private.study_authorize(p_study uuid,p_actor uuid,p_client text,p_action text) returns void
language plpgsql security definer set search_path='' as $$
declare s private.studies%rowtype; r text;
begin
  perform private.study_require(p_actor is not null,'AUTH_REQUIRED');
  perform private.study_require(private.study_client_allowed(p_client,case when p_action='read' then 'STUDY-READ-01' else 'STUDY-WRITE-01' end),'FORBIDDEN');
  select * into s from private.studies where id=p_study for update;
  perform private.study_require(found,'FORBIDDEN');
  select role into r from private.study_members where study_id=p_study and actor_id=p_actor;
  if s.team_id is not null then
    -- SHARE also fences non-key role demotions/deletion until this transaction
    -- commits. KEY SHARE would not fence an UPDATE of the role column.
    perform 1 from private.roles where user_id=p_actor and team_id=s.team_id and role in ('owner','admin','member') for share;
    perform private.study_require(found,'FORBIDDEN');
  end if;
  perform private.study_require(
    case p_action when 'read' then r in ('owner','editor','viewer') when 'write' then r in ('owner','editor') when 'manage' then r='owner' else false end,'FORBIDDEN');
end $$;
-- Structural persistence guards follow Edge's closed v2 records (v1 definition
-- vocabulary retained). Edge remains the wire owner; these prevent direct RPC
-- callers bypassing its parser and persisting unprojectable research records.
create function private.study_keys(p_value jsonb,p_keys text[]) returns boolean
language plpgsql immutable set search_path='' as $$ begin
  if jsonb_typeof(p_value) is distinct from 'object' then return false; end if;
  return p_value ?& p_keys and not exists(select 1 from jsonb_object_keys(p_value) k where k<>all(p_keys));
end $$;
create function private.study_text(p_value jsonb,p_max integer,p_pattern text default null) returns boolean
language plpgsql immutable set search_path='' as $$ declare v text; begin
  if jsonb_typeof(p_value) is distinct from 'string' then return false; end if;
  v:=p_value#>>'{}';
  -- Edge's qualified Zod4 text bounds count Unicode code points. Retain its
  -- separate UTF8 byte bound; do not substitute JS UTF16 string.length here.
  if length(v) not between 1 and p_max
    or octet_length(v)>p_max*4 or btrim(v,U&'\0009\000A\000B\000C\000D\0020\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF')=''
    or v ~ U&'[\0001-\0008\000B\000C\000E-\001F\007F]' then return false; end if;
  return p_pattern is null or v ~ p_pattern;
end $$;
create function private.study_method_refs_valid(p_refs jsonb) returns boolean
language plpgsql immutable set search_path='' as $$ declare r jsonb; ids text[]:='{}'; begin
  if jsonb_typeof(p_refs) is distinct from 'array' then return false; end if;
  if jsonb_array_length(p_refs) not between 1 and 32 then return false; end if;
  for r in select * from jsonb_array_elements(p_refs) loop
    if not private.study_keys(r,array['type','datasetType','id','version'])
      or r->>'type' is distinct from 'datasetRevision' or r->>'datasetType' is distinct from 'lciamethod'
      or not private.study_text(r->'id',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$')
      or not private.study_text(r->'version',128,'^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$')
      or r->>'id'=any(ids) then return false; end if;
    ids:=ids||(r->>'id');
  end loop;
  return true;
end $$;
create function private.study_definition_valid(p_definition jsonb) returns boolean
language plpgsql immutable set search_path='' as $$ declare f jsonb; a jsonb; begin
  if not private.study_keys(p_definition,array['goal','functionalUnit','systemBoundary','methodRefs','assumptions'])
    or not private.study_text(p_definition->'goal',4096) or not private.study_text(p_definition->'systemBoundary',4096)
    or not private.study_method_refs_valid(p_definition->'methodRefs')
    or jsonb_typeof(p_definition->'assumptions') is distinct from 'array' then return false; end if;
  f:=p_definition->'functionalUnit';
  if not private.study_keys(f,array['amount','unit','referenceFlowId'])
    or not private.study_text(f->'amount',64,'^([1-9][0-9]*(\.[0-9]+)?|0\.[0-9]*[1-9][0-9]*)$')
    or not private.study_text(f->'unit',128) or not private.study_text(f->'referenceFlowId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$')
    or jsonb_array_length(p_definition->'assumptions')>128 then return false; end if;
  for a in select * from jsonb_array_elements(p_definition->'assumptions') loop
    if not private.study_keys(a,array['id','statement','evidenceRef'])
      or not private.study_text(a->'id',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$')
      or not private.study_text(a->'statement',4096)
      or not private.study_text(a->'evidenceRef',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$') then return false; end if;
  end loop;
  return true;
end $$;
create function private.study_overrides_valid(p_overrides jsonb) returns boolean
language plpgsql immutable set search_path='' as $$ declare o jsonb; paths text[]:='{}'; amount double precision; begin
  if jsonb_typeof(p_overrides) is distinct from 'array' then return false; end if;
  if jsonb_array_length(p_overrides)>256 then return false; end if;
  for o in select * from jsonb_array_elements(p_overrides) loop
    if not private.study_keys(o,array['path','value'])
      or not private.study_text(o->'path',256,'^/instances/[A-Za-z0-9_-]+/exchanges/[A-Za-z0-9_-]+/amount$')
      or jsonb_typeof(o->'value') is distinct from 'number' or o->>'path'=any(paths) then return false; end if;
    amount:=(o->>'value')::double precision;
    if amount='Infinity'::double precision or amount='-Infinity'::double precision or amount='NaN'::double precision then return false; end if;
    paths:=paths||(o->>'path');
  end loop;
  return true;
exception when data_exception then return false;
end $$;
alter table private.study_model_preparations add check(private.study_method_refs_valid(method_refs));
alter table private.study_revisions add check(private.study_definition_valid(definition));
alter table private.study_scenarios add check(private.study_overrides_valid(overrides));
create function private.study_access_epoch(p_actor uuid,p_study uuid) returns text
language sql stable security definer set search_path='' as $$
  select private.study_content_hash('lca.study-access-epoch.v1',coalesce(jsonb_agg(jsonb_build_object(
    'studyId',s.id,'grantEpoch',s.grant_epoch,'studyRole',m.role,'teamRole',r.role) order by s.id),'[]'::jsonb))
  from private.study_members m join private.studies s on s.id=m.study_id
  left join private.roles r on r.user_id=p_actor and r.team_id=s.team_id
  where m.actor_id=p_actor and (p_study is null or s.id=p_study)
$$;
create function private.study_assert_provenance(p_study uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
  perform private.study_require(not exists(
    with recursive edges(a,b) as (
      select 'r:'||id,'p:'||preparation_id from private.study_revisions where study_id=p_study
      union all select 'r:'||id,'r:'||parent_revision_id from private.study_revisions where study_id=p_study and parent_revision_id is not null
      union all select 's:'||id,'r:'||study_revision_id from private.study_scenarios where study_id=p_study
      union all select 's:'||id,'s:'||parent_scenario_id from private.study_scenarios where study_id=p_study and parent_scenario_id is not null
      union all select 's:'||id,'p:'||preparation_id from private.study_scenarios where study_id=p_study and preparation_id is not null
      -- Captured draft source edges exclude the later frozen Scenario's own preparation.
      union all select 'p:'||id,'r:'||source_study_revision_id from private.study_model_preparations where study_id=p_study and source_study_revision_id is not null
      union all select 'p:'||id,'s:'||source_parent_scenario_id from private.study_model_preparations where study_id=p_study and source_parent_scenario_id is not null
    ), reach(a,b) as (
      select a,b from edges
      union select r.a,e.b from reach r join edges e on e.a=r.b
    ) select 1 from reach where a=b
  ),'REFERENCE_MISMATCH');
end $$;
create function private.study_qualified_preparation(p_study uuid,p_id uuid) returns private.study_model_preparations
language plpgsql security definer set search_path='' as $$
declare p private.study_model_preparations%rowtype;
begin
  select * into p from private.study_model_preparations where study_id=p_study and id=p_id;
  perform private.study_require(found,'REFERENCE_MISMATCH');
  perform private.study_require(p.model_ref is not null and p.input_artifact_id is not null
    and exists(select 1 from private.worker_jobs where id=p.job_id and status='completed'),'CAPABILITY_UNAVAILABLE');
  perform private.study_require(exists(select 1 from private.study_profiles where profile_id=p.profile_id and enabled
    and calculation_fingerprint=p.calculation_contract_ref->>'sha256'),'CAPABILITY_UNAVAILABLE');
  return p;
end $$;
create function private.study_record(p_kind text,p_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v jsonb;
begin
  case p_kind
  when 'study' then select jsonb_build_object('studyId',id,'revision',revision,'scope',case when team_id is null then jsonb_build_object('kind','user','id',owner_id) else jsonb_build_object('kind','team','id',team_id) end,'title',title,'status',status,'currentRevisionId',current_revision_id) into v from private.studies where id=p_id;
  when 'studyRevision' then select jsonb_build_object('revisionId',id,'studyId',study_id,'revision',revision,'parentRevisionId',parent_revision_id,'status',status,'contentHash',content_hash,'definition',definition,'modelPreparationId',preparation_id,'modelRef',model_ref,'validation',validation) into v from private.study_revisions where id=p_id;
  when 'scenarioRevision' then select jsonb_build_object('scenarioId',scenario_id,'scenarioRevisionId',id,'studyId',study_id,'studyRevisionId',study_revision_id,'parentScenarioRevisionId',parent_scenario_id,'revision',revision,'status',status,'contentHash',content_hash,'overrides',overrides,'modelPreparationId',preparation_id,'effectiveModelRef',effective_model_ref) into v from private.study_scenarios where id=p_id;
  when 'modelPreparation' then select jsonb_build_object('preparationId',p.id,'studyId',p.study_id,'source',p.source,'methodRefs',p.method_refs,'profileId',p.profile_id,'calculationContractRef',p.calculation_contract_ref,'execution',jsonb_build_object('jobId',p.job_id,'status',j.status),'modelRef',p.model_ref,'inputArtifactRef',a.ref,'inputHash',p.input_hash) into v from private.study_model_preparations p join private.worker_jobs j on j.id=p.job_id left join private.study_artifacts a on a.id=p.input_artifact_id where p.id=p_id;
  when 'modelSourceSnapshot' then select jsonb_build_object('snapshotId',s.id,'studyId',s.study_id,'originRef',s.origin_ref,'sourceArtifactRef',a.ref,'digestScope','artifact_bytes_sha256','licenseRef',s.license_ref,'issuerId',s.issuer_id,'observedAt',s.observed_at) into v from private.study_source_snapshots s join private.study_artifacts a on a.id=s.artifact_id where s.id=p_id;
  when 'modelSourceAcquisition' then select jsonb_build_object('acquisitionId',a.id,'studyId',a.study_id,'originRef',a.origin_ref,'execution',jsonb_build_object('jobId',a.job_id,'status',j.status),'snapshot',case when a.snapshot_id is null then null else private.study_record('modelSourceSnapshot',a.snapshot_id) end) into v from private.study_source_acquisitions a join private.worker_jobs j on j.id=a.job_id where a.id=p_id;
  when 'run' then select jsonb_build_object('runId',r.id,'studyId',r.study_id,'studyRevisionId',r.study_revision_id,'scenarioRevisionId',r.scenario_id,'modelPreparationId',r.preparation_id,'effectiveModelRef',r.model_ref,'inputHash',r.input_hash,'profileId',r.profile_id,'calculationContractRef',r.calculation_contract_ref,'engineId','solver-worker','execution',jsonb_build_object('jobId',r.job_id,'status',j.status),'resultRef',a.ref,'validity',jsonb_build_object('status',r.validity,'checkedAt',r.validity_checked_at,'reasonCodes','[]'::jsonb)) into v from private.study_runs r join private.worker_jobs j on j.id=r.job_id left join private.study_artifacts a on a.id=r.result_artifact_id where r.id=p_id;
  else perform private.study_require(false,'CAPABILITY_UNAVAILABLE');
  end case;
  perform private.study_require(v is not null,'FORBIDDEN');
  return v;
end $$;

-- CLOSED ACTOR DISPATCH. Exact public v2 fields; no trusted producer/evidence fields.
create function api.cmd_study_v1(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' set statement_timeout='15s' as $$
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
end $$;

create function api.svc_study_revision_freeze_consume_v1(p_intent_id uuid,p_outcome text,p_error_code text default null) returns jsonb
language plpgsql security definer set search_path='' set statement_timeout='15s' as $$
declare i private.study_validation_intents%rowtype; r private.study_revisions%rowtype; prep private.study_model_preparations%rowtype; current_binding jsonb; v_response jsonb;
begin
  perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
  select * into i from private.study_validation_intents where id=p_intent_id;
  perform private.study_require(found,'FORBIDDEN');
  -- Shared ordering: Study, intent, revision, then preparation/job. No service
  -- function acquires a worker row before its owning Study row.
  perform private.study_authorize(i.study_id,i.actor_id,i.client_id,'write');
  select * into i from private.study_validation_intents where id=p_intent_id for update;
  if i.response is not null then
    perform private.study_require(p_outcome='passed','IDEMPOTENCY_CONFLICT'); return i.response;
  end if;
  perform private.study_require(i.expires_at>clock_timestamp(),'CAPABILITY_UNAVAILABLE');
  perform private.study_require((select status='active' from private.studies where id=i.study_id),'FROZEN_REVISION');
  select * into r from private.study_revisions where id=i.revision_id for update;
  perform private.study_require(r.revision=(i.binding->>'expectedRevision')::bigint,'REVISION_CONFLICT');
  perform private.study_require(r.status='draft','FROZEN_REVISION');
  prep:=private.study_qualified_preparation(i.study_id,r.preparation_id);
  current_binding:=jsonb_build_object('revisionId',r.id,'expectedRevision',r.revision,'contentHash',r.content_hash,'modelPreparationId',r.preparation_id,'modelRef',r.model_ref,'definition',r.definition);
  perform private.study_require(current_binding=i.binding and r.model_ref=prep.model_ref and r.definition->'methodRefs'=prep.method_refs,'REFERENCE_MISMATCH');
  perform private.study_require(p_outcome<>'unavailable','CAPABILITY_UNAVAILABLE');
  perform private.study_require(p_outcome='passed' and p_error_code is null,'INVALID_REQUEST');
  update private.study_revisions set status='frozen',validation='passed',revision=revision+1,
    validation_evidence=jsonb_build_object('schemaVersion','lca.study-validation.v1','intentId',i.id,'binding',i.binding,'validatedAt',clock_timestamp()) where id=r.id;
  v_response:=jsonb_build_object('ok',true,'data',jsonb_build_object('type','studyRevision','value',private.study_record('studyRevision',r.id)));
  update private.study_validation_intents set response=v_response,consumed_at=clock_timestamp() where id=i.id;
  return v_response;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end $$;

-- The W06 adapter creates these domain/job bindings in one admission transaction.
-- W03 exposes no actor command that invents a job or a Worker-issued receipt.
create function private.study_lock_job(p_study uuid,p_job uuid,p_token uuid,p_kind text,p_subject text,p_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare j private.worker_jobs%rowtype;
begin
  perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
  perform 1 from private.studies where id=p_study for update;
  perform private.study_require(found,'REFERENCE_MISMATCH');
  select * into j from private.worker_jobs where id=p_job for update;
  perform private.study_require(found and j.job_kind=p_kind and j.worker_runtime='calculator'
    and j.payload_json->>'studyId'=p_study::text and j.payload_json->>p_subject=p_id::text,'REFERENCE_MISMATCH');
  perform private.study_require(j.status='running' and j.lease_token=p_token and j.lease_expires_at>clock_timestamp(),'FORBIDDEN');
end $$;
create function private.study_store_artifact(p_study uuid,p_ref jsonb,p_bucket text,p_path text,p_type text) returns uuid
language plpgsql security definer set search_path='' as $$
declare aid uuid:=(p_ref->>'id')::uuid;
begin
  perform private.study_require(p_ref->>'type'=p_type and p_ref->>'digestScope'='artifact_bytes_sha256'
    and private.study_keys(p_ref,array['type','id','contentHash','digestScope','byteSize','mediaType','schemaVersion'])
    and private.study_text(p_ref->'id',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$')
    and private.study_text(p_ref->'contentHash',64,'^[0-9a-f]{64}$')
    and jsonb_typeof(p_ref->'byteSize')='number' and (p_ref->>'byteSize')::numeric=trunc((p_ref->>'byteSize')::numeric)
    and (p_ref->>'byteSize')::numeric between 1 and 4194304
    and p_ref->>'mediaType' in ('application/json','application/zip','text/html')
    and length(p_ref->>'schemaVersion') between 1 and 128,'REFERENCE_MISMATCH');
  perform private.study_require(p_bucket='study-artifacts' and p_path ~ ('^study/'||p_study::text||'/'||aid::text||'/[A-Za-z0-9_-]+\.(json|zip|html)$'),'REFERENCE_MISMATCH');
  insert into private.study_artifacts(id,study_id,ref,bucket,object_path) values(aid,p_study,p_ref,p_bucket,p_path)
    on conflict(id) do nothing;
  perform private.study_require(exists(select 1 from private.study_artifacts where id=aid and study_id=p_study and ref=p_ref and bucket=p_bucket and object_path=p_path),'IDEMPOTENCY_CONFLICT');
  return aid;
end $$;
create function private.study_complete(p_kind text,p_id uuid,p_job uuid,p_token uuid,p_completion jsonb,p_key text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare sid uuid; job uuid; expected_kind text; subject text; artifact_kind text; artifact_key text;
  p private.study_model_preparations%rowtype; a private.study_source_acquisitions%rowtype; r private.study_runs%rowtype;
  previous private.study_service_receipts%rowtype; request jsonb; response jsonb; result jsonb; artifact uuid; snapshot uuid; jresult jsonb;
begin
  perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
  perform private.study_require(length(p_key) between 1 and 128 and jsonb_typeof(p_completion)='object','INVALID_REQUEST');
  case p_kind
    when 'modelPreparation' then
      select * into p from private.study_model_preparations where id=p_id;
      sid:=p.study_id; job:=p.job_id; expected_kind:='study.model_prepare'; subject:='preparationId'; artifact_kind:='modelInput'; artifact_key:='inputArtifactRef';
    when 'modelSourceAcquisition' then
      select * into a from private.study_source_acquisitions where id=p_id;
      sid:=a.study_id; job:=a.job_id; expected_kind:='study.source_acquire'; subject:='acquisitionId'; artifact_kind:='modelSource'; artifact_key:='sourceArtifactRef';
    when 'run' then
      select * into r from private.study_runs where id=p_id;
      sid:=r.study_id; job:=r.job_id; expected_kind:='study.run'; subject:='runId'; artifact_kind:='runResult'; artifact_key:='resultRef';
    else perform private.study_require(false,'INVALID_REQUEST');
  end case;
  perform private.study_require(sid is not null and job=p_job,'REFERENCE_MISMATCH');
  perform 1 from private.studies where id=sid for update;
  request:=jsonb_build_object('id',p_id,'jobId',p_job,'leaseToken',p_token,'completion',p_completion);
  select * into previous from private.study_service_receipts where operation=p_kind and study_id=sid and idempotency_key=p_key;
  if found then
    perform private.study_require(previous.request=request,'IDEMPOTENCY_CONFLICT');
    -- A terminal acknowledgement may be recovered using its original exact lease;
    -- a fresh or foreign lease cannot impersonate the committed completion.
    perform private.study_require(previous.job_id=p_job and previous.lease_token=p_token,'FORBIDDEN');
    return previous.response;
  end if;
  perform private.study_lock_job(sid,p_job,p_token,expected_kind,subject,p_id);
  if p_kind='modelPreparation' then
    perform private.study_require(p.model_ref is null,'IDEMPOTENCY_CONFLICT');
    perform private.study_require(p_completion->'calculationContractRef'=p.calculation_contract_ref and p_completion->>'profileId'=p.profile_id,'REFERENCE_MISMATCH');
    perform private.study_require(private.study_keys(p_completion->'modelRef',array['type','modelRevisionId','contentHash','digestScope'])
      and p_completion->'modelRef'->>'type'='modelRevision' and p_completion->'modelRef'->>'digestScope'='worker_prepared_model'
      and private.study_text(p_completion->'modelRef'->'contentHash',64,'^[0-9a-f]{64}$')
      and private.study_text(p_completion->'modelRef'->'modelRevisionId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'REFERENCE_MISMATCH');
    perform private.study_require(p_completion->>'inputHash' is null or p_completion->>'inputHash' ~ '^[0-9a-f]{64}$','REFERENCE_MISMATCH');
    perform private.study_require(p.source->>'type'<>'scenarioRevision' or p_completion->>'inputHash' is not null,'REFERENCE_MISMATCH');
  elsif p_kind='modelSourceAcquisition' then
    perform private.study_require(a.snapshot_id is null,'IDEMPOTENCY_CONFLICT');
    perform private.study_require(p_completion->'originRef'=a.origin_ref and length(p_completion->>'licenseRef') between 1 and 128
      and length(p_completion->>'issuerId') between 1 and 128 and p_completion->>'observedAt' is not null,'REFERENCE_MISMATCH');
    perform private.study_require(p_completion->'sourceAuthorization'->>'schemaVersion'='lca.study-source-authorization.v1'
      and p_completion->'sourceAuthorization'->>'requestedBy'=a.requested_by::text
      and p_completion->'sourceAuthorization'->'originRef'=a.origin_ref
      and jsonb_typeof(p_completion->'sourceAuthorization'->'sourceScope')='array','REFERENCE_MISMATCH');
  else
    perform private.study_require(r.result_artifact_id is null,'IDEMPOTENCY_CONFLICT');
    perform private.study_require(p_completion->>'inputHash'=r.input_hash and p_completion->'calculationContractRef'=r.calculation_contract_ref,'REFERENCE_MISMATCH');
  end if;
  artifact:=private.study_store_artifact(sid,p_completion->artifact_key,p_completion->>'storageBucket',p_completion->>'storageObjectPath',artifact_kind);
  if p_kind='modelPreparation' then
    update private.study_model_preparations set model_ref=p_completion->'modelRef',input_artifact_id=artifact,input_hash=p_completion->>'inputHash' where id=p_id;
  elsif p_kind='modelSourceAcquisition' then
    snapshot:=(p_completion->>'snapshotId')::uuid;
    insert into private.study_source_snapshots(id,study_id,acquisition_id,origin_ref,artifact_id,license_ref,issuer_id,observed_at,source_authorization)
      values(snapshot,sid,p_id,a.origin_ref,artifact,p_completion->>'licenseRef',p_completion->>'issuerId',(p_completion->>'observedAt')::timestamptz,p_completion->'sourceAuthorization');
    update private.study_source_acquisitions set snapshot_id=snapshot where id=p_id;
  else update private.study_runs set result_artifact_id=artifact where id=p_id; end if;
  -- Generic worker_job_payload(false) includes result_json. Never place private
  -- source scope, model/numerics or storage locators in that shared projection.
  jresult:=private.worker_record_job_result(p_job,p_token,'completed',
    jsonb_build_object('schemaVersion','lca.study-job-receipt.v1','studyId',sid,'resourceType',p_kind,'resourceId',p_id),
    'lca.study-job-receipt.v1',p_completion->artifact_key);
  perform private.study_require((jresult->>'ok')::boolean,'FORBIDDEN');
  perform private.study_assert_provenance(sid);
  response:=jsonb_build_object('ok',true,'data',jsonb_build_object('type',p_kind,'value',private.study_record(p_kind,p_id)));
  insert into private.study_service_receipts values(p_kind,sid,p_key,p_job,p_token,request,response);
  return response;
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or numeric_value_out_of_range or not_null_violation or check_violation or invalid_datetime_format then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
when foreign_key_violation or unique_violation then return jsonb_build_object('ok',false,'code','REFERENCE_MISMATCH');
end $$;
create function api.svc_study_model_preparation_complete_v1(p_preparation_id uuid,p_job_id uuid,p_lease_token uuid,p_completion jsonb,p_idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.study_complete('modelPreparation',p_preparation_id,p_job_id,p_lease_token,p_completion,p_idempotency_key) $$;
create function api.svc_study_source_record_v1(p_acquisition_id uuid,p_job_id uuid,p_lease_token uuid,p_completion jsonb,p_idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.study_complete('modelSourceAcquisition',p_acquisition_id,p_job_id,p_lease_token,p_completion,p_idempotency_key) $$;
create function api.svc_study_run_complete_v1(p_run_id uuid,p_job_id uuid,p_lease_token uuid,p_completion jsonb,p_idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.study_complete('run',p_run_id,p_job_id,p_lease_token,p_completion,p_idempotency_key) $$;
create function private.study_read_worker_input(p_kind text,p_id uuid,p_job uuid,p_token uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p private.study_model_preparations%rowtype; r private.study_runs%rowtype; sid uuid; result jsonb;
begin
  perform private.study_require(coalesce(util.is_service_request(),false),'FORBIDDEN');
  if p_kind='modelPreparation' then
    select * into p from private.study_model_preparations where id=p_id;
    sid:=p.study_id; perform private.study_require(p.job_id=p_job,'REFERENCE_MISMATCH');
    perform private.study_lock_job(sid,p_job,p_token,'study.model_prepare','preparationId',p_id);
    result:=jsonb_build_object('preparation',private.study_record('modelPreparation',p.id),'sourceDocument',p.source_document,'methodRefs',p.method_refs);
  else
    select * into r from private.study_runs where id=p_id;
    sid:=r.study_id; perform private.study_require(r.job_id=p_job,'REFERENCE_MISMATCH');
    perform private.study_lock_job(sid,p_job,p_token,'study.run','runId',p_id);
    result:=jsonb_build_object('run',private.study_record('run',r.id),'preparation',private.study_record('modelPreparation',r.preparation_id),'revision',private.study_record('studyRevision',r.study_revision_id),'scenario',private.study_record('scenarioRevision',r.scenario_id));
  end if;
  return jsonb_build_object('ok',true,'data',result);
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
end $$;
create function api.svc_study_model_preparation_read_input_v1(p_preparation_id uuid,p_job_id uuid,p_lease_token uuid) returns jsonb
language sql security definer set search_path='' as $$ select private.study_read_worker_input('modelPreparation',p_preparation_id,p_job_id,p_lease_token) $$;
create function api.svc_study_run_read_input_v1(p_run_id uuid,p_job_id uuid,p_lease_token uuid) returns jsonb
language sql security definer set search_path='' as $$ select private.study_read_worker_input('run',p_run_id,p_job_id,p_lease_token) $$;

create function api.qry_study_v1(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' set statement_timeout='15s' as $$
declare op text:=p_request->>'operation'; actor uuid:=auth.uid(); client text:=nullif(auth.jwt()->>'client_id',''); sid uuid; rid uuid; kind text; v jsonb; items jsonb; lim integer; after_id uuid; ids uuid[]; more boolean; cursor_row private.study_cursors%rowtype; cursor_id uuid; selection jsonb; epoch text; operations jsonb; allowed text[];
begin
  perform private.study_require(actor is not null and not coalesce(util.is_service_request(),false),'AUTH_REQUIRED');
  perform private.study_require(private.study_client_allowed(client,'STUDY-READ-01'),'FORBIDDEN');
  perform private.study_require(jsonb_typeof(p_request)='object' and p_request->>'schemaVersion'='lca.study-api.v2'
    and octet_length(p_request::text)<=262144 and length(p_request->>'requestId') between 1 and 128,'INVALID_REQUEST');
  case op
    when 'capability.read' then allowed:='{}';
    when 'study.list' then allowed:=array['cursor','limit'];
    when 'study.read' then allowed:=array['studyId'];
    when 'study.resources.list' then allowed:=array['studyId','kind','cursor','limit'];
    when 'revision.read' then allowed:=array['revisionId'];
    when 'scenario.read' then allowed:=array['scenarioRevisionId'];
    when 'model.read' then allowed:=array['preparationId'];
    when 'model.source.read' then allowed:=array['acquisitionId'];
    when 'run.read' then allowed:=array['runId'];
    else perform private.study_require(false,'CAPABILITY_UNAVAILABLE');
  end case;
  perform private.study_require(not exists(select 1 from jsonb_object_keys(p_request) k where k<>all(allowed||array['operation','schemaVersion','requestId'])),'INVALID_REQUEST');
  if op='capability.read' then
    operations:=jsonb_build_array('capability.read','study.read','study.list','study.resources.list','revision.read','scenario.read','model.read','model.source.read','run.read');
    if private.study_client_allowed(client,'STUDY-WRITE-01') then
      operations:=operations||jsonb_build_array('study.create','study.archive','study.select_revision','member.set','revision.create','revision.save','revision.freeze','scenario.create','scenario.save','scenario.freeze');
    end if;
    return jsonb_build_object('ok',true,'data',jsonb_build_object('type','capabilities','contractVersion','2.0.0','runtimeEnabled',true,
      'operations',operations,'profiles','[]'::jsonb));
  end if;
  if op in ('study.list','study.resources.list') then
    lim:=(p_request->>'limit')::integer; perform private.study_require(lim between 1 and 100,'INVALID_REQUEST');
    if op='study.resources.list' then sid:=(p_request->>'studyId')::uuid; perform private.study_authorize(sid,actor,client,'read'); end if;
    selection:=p_request-'requestId'-'cursor'; epoch:=private.study_access_epoch(actor,sid);
    if p_request->>'cursor' is not null then
      perform private.study_require(p_request->>'cursor' ~ '^[0-9a-f]{32}$','INVALID_REQUEST');
      select * into cursor_row from private.study_cursors where id=(p_request->>'cursor')::uuid;
      perform private.study_require(found and cursor_row.actor_id=actor and cursor_row.client_id is not distinct from client
        and cursor_row.selection=selection and cursor_row.access_epoch=epoch and cursor_row.expires_at>clock_timestamp(),'FORBIDDEN');
      after_id:=cursor_row.after_id;
    end if;
  end if;
  if op='study.list' then
    select array_agg(id order by id) into ids from(select s.id from private.studies s join private.study_members m on m.study_id=s.id where m.actor_id=actor and private.study_team_member(actor,s.team_id) and (after_id is null or s.id>after_id) order by s.id limit lim+1)t;
    more:=cardinality(ids)>lim; ids:=ids[1:lim];
    -- Recheck and lock every selected Study before returning its current projection.
    foreach rid in array coalesce(ids,'{}') loop perform private.study_authorize(rid,actor,client,'read'); end loop;
    select coalesce(jsonb_agg(private.study_record('study',id) order by id),'[]'::jsonb) into items from unnest(ids)id;
    if more then insert into private.study_cursors(actor_id,client_id,selection,access_epoch,after_id) values(actor,client,selection,epoch,ids[lim]) returning id into cursor_id; end if;
    v:=jsonb_build_object('type','studyPage','items',items,'nextCursor',case when more then replace(cursor_id::text,'-','') else null end);
  else
    case op
      when 'study.read','study.resources.list' then sid:=(p_request->>'studyId')::uuid; kind:='study'; rid:=sid;
      when 'revision.read' then rid:=(p_request->>'revisionId')::uuid; select study_id into sid from private.study_revisions where id=rid; kind:='studyRevision';
      when 'scenario.read' then rid:=(p_request->>'scenarioRevisionId')::uuid; select study_id into sid from private.study_scenarios where id=rid; kind:='scenarioRevision';
      when 'model.read' then rid:=(p_request->>'preparationId')::uuid; select study_id into sid from private.study_model_preparations where id=rid; kind:='modelPreparation';
      when 'model.source.read' then rid:=(p_request->>'acquisitionId')::uuid; select study_id into sid from private.study_source_acquisitions where id=rid; kind:='modelSourceAcquisition';
      when 'run.read' then rid:=(p_request->>'runId')::uuid; select study_id into sid from private.study_runs where id=rid; kind:='run';
      else perform private.study_require(false,'CAPABILITY_UNAVAILABLE');
    end case;
    perform private.study_authorize(sid,actor,client,'read');
    if op='study.resources.list' then
      kind:=p_request->>'kind';
      select array_agg(id order by id) into ids from (
        select id from (
          select id from private.study_revisions where study_id=sid and kind='studyRevision'
          union all select id from private.study_scenarios where study_id=sid and kind='scenarioRevision'
          union all select id from private.study_source_snapshots where study_id=sid and kind='modelSourceSnapshot'
          union all select id from private.study_source_acquisitions where study_id=sid and kind='modelSourceAcquisition'
          union all select id from private.study_model_preparations where study_id=sid and kind='modelPreparation'
          union all select id from private.study_runs where study_id=sid and kind='run'
        )u where after_id is null or id>after_id order by id limit lim+1)t;
      perform private.study_require(kind in ('studyRevision','scenarioRevision','modelSourceSnapshot','modelSourceAcquisition','modelPreparation','run'),'CAPABILITY_UNAVAILABLE');
      more:=cardinality(ids)>lim; ids:=ids[1:lim];
      select coalesce(jsonb_agg(jsonb_build_object('type',kind,'value',private.study_record(kind,id)) order by id),'[]'::jsonb) into items from unnest(ids)id;
      if more then insert into private.study_cursors(actor_id,client_id,selection,access_epoch,after_id) values(actor,client,selection,epoch,ids[lim]) returning id into cursor_id; end if;
      v:=jsonb_build_object('type','resourcePage','studyId',sid,'kind',kind,'items',items,'nextCursor',case when more then replace(cursor_id::text,'-','') else null end);
    else v:=jsonb_build_object('type',kind,'value',private.study_record(kind,rid)); end if;
  end if;
  return jsonb_build_object('ok',true,'data',v);
exception when raise_exception then return jsonb_build_object('ok',false,'code',sqlerrm);
when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range then return jsonb_build_object('ok',false,'code','INVALID_REQUEST');
end $$;

-- Defense against accidental direct/internal mutations of accepted immutable facts.
create function private.study_guard_immutable() returns trigger language plpgsql set search_path='' as $$
begin
  if tg_op='DELETE' then raise exception 'FROZEN_REVISION'; end if;
  if tg_table_name in ('study_revisions','study_scenarios') then
    if old.status='frozen' then raise exception 'FROZEN_REVISION'; end if;
    if tg_table_name='study_revisions' then
      if old.parent_revision_id is distinct from new.parent_revision_id then raise exception 'REFERENCE_MISMATCH'; end if;
    else
      if old.parent_scenario_id is distinct from new.parent_scenario_id or old.study_revision_id<>new.study_revision_id then raise exception 'REFERENCE_MISMATCH'; end if;
    end if;
  elsif tg_table_name='study_model_preparations' then
    if (to_jsonb(old)-'model_ref'-'input_artifact_id'-'input_hash') is distinct from (to_jsonb(new)-'model_ref'-'input_artifact_id'-'input_hash') then raise exception 'REFERENCE_MISMATCH'; end if;
    if old.model_ref is not null and to_jsonb(old) is distinct from to_jsonb(new) then raise exception 'FROZEN_REVISION'; end if;
  elsif tg_table_name='study_source_acquisitions' then
    if (to_jsonb(old)-'snapshot_id') is distinct from (to_jsonb(new)-'snapshot_id') then raise exception 'REFERENCE_MISMATCH'; end if;
    if old.snapshot_id is not null and old.snapshot_id is distinct from new.snapshot_id then raise exception 'FROZEN_REVISION'; end if;
  elsif tg_table_name='study_runs' then
    if (to_jsonb(old)-'result_artifact_id') is distinct from (to_jsonb(new)-'result_artifact_id') then raise exception 'REFERENCE_MISMATCH'; end if;
    if old.result_artifact_id is not null and old.result_artifact_id is distinct from new.result_artifact_id then raise exception 'FROZEN_REVISION'; end if;
  else raise exception 'FROZEN_REVISION'; end if;
  return new;
end $$;
create trigger study_revision_immutable before update or delete on private.study_revisions for each row execute function private.study_guard_immutable();
create trigger study_scenario_immutable before update or delete on private.study_scenarios for each row execute function private.study_guard_immutable();
create trigger study_artifact_immutable before update or delete on private.study_artifacts for each row execute function private.study_guard_immutable();
create trigger study_snapshot_immutable before update or delete on private.study_source_snapshots for each row execute function private.study_guard_immutable();
create trigger study_preparation_immutable before update or delete on private.study_model_preparations for each row execute function private.study_guard_immutable();
create trigger study_acquisition_immutable before update or delete on private.study_source_acquisitions for each row execute function private.study_guard_immutable();
create trigger study_run_immutable before update or delete on private.study_runs for each row execute function private.study_guard_immutable();

do $$ declare n text; f record; begin
  foreach n in array array['study_profiles','studies','study_members','study_artifacts','study_source_acquisitions','study_source_snapshots','study_model_preparations','study_revisions','study_scenarios','study_runs','study_command_receipts','study_validation_intents','study_service_receipts','study_cursors'] loop
    execute format('alter table private.%I enable row level security',n);
    execute format('alter table private.%I force row level security',n);
    execute format('revoke all on private.%I from public,anon,authenticated,service_role',n);
  end loop;
  for f in select p.oid::regprocedure as id from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname like 'study_%' loop
    execute format('revoke all on function %s from public,anon,authenticated,service_role',f.id);
  end loop;
end $$;
revoke all on function api.cmd_study_v1(jsonb),api.qry_study_v1(jsonb),api.svc_study_revision_freeze_consume_v1(uuid,text,text) from public,anon,authenticated,service_role;
grant execute on function api.cmd_study_v1(jsonb),api.qry_study_v1(jsonb) to authenticated;
grant execute on function api.svc_study_revision_freeze_consume_v1(uuid,text,text) to service_role;
insert into private.api_capability_grants(routine_identity,capability_id,allow_anon,allow_authenticated,allow_service_role) values
 ('api.cmd_study_v1(jsonb)','STUDY-WRITE-01',false,true,false),
 ('api.qry_study_v1(jsonb)','STUDY-READ-01',false,true,false),
 ('api.svc_study_revision_freeze_consume_v1(uuid, text, text)','STUDY-SERVICE-01',false,false,true);
do $$ declare f record; ident text; begin
  for f in select p.oid::regprocedure as id,n.nspname,p.proname,pg_catalog.oidvectortypes(p.proargtypes) as args
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='api' and p.proname like 'svc_study_%' and p.proname<>'svc_study_revision_freeze_consume_v1' loop
    execute format('revoke all on function %s from public,anon,authenticated,service_role',f.id);
    execute format('grant execute on function %s to service_role',f.id);
    ident:=format('%I.%I(%s)',f.nspname,f.proname,f.args);
    insert into private.api_capability_grants values(ident,'STUDY-SERVICE-01',false,false,true);
  end loop;
end $$;
commit;
