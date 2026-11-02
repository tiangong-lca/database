begin;
-- Immutable trusted-verifier evidence. This does not advance the release run,
-- approve a human action, publish canonical rows or change current publication.
create table private.final_result_release_verifications (
  id uuid primary key,
  release_run_id uuid not null references private.final_result_release_plans(release_run_id),
  runtime_revision uuid not null references private.final_result_query_runtime_revisions(id),
  header jsonb not null check (pg_column_size(header)<=32768),
  created_at timestamptz not null default clock_timestamp()
);
create table private.final_result_release_artifact_proofs (
  verification_id uuid not null references private.final_result_release_verifications(id),
  artifact_id uuid not null references private.final_result_query_artifacts(id),
  proof jsonb not null check (pg_column_size(proof)<=65536),
  proof_sha256 text not null check (proof_sha256 ~ '^[0-9a-f]{64}$'),
  primary key(verification_id,artifact_id)
);
create table private.final_result_release_readiness (
  verification_id uuid primary key references private.final_result_release_verifications(id),
  receipt jsonb not null check (pg_column_size(receipt)<=32768),
  expires_at timestamptz not null,
  sealed_at timestamptz not null default clock_timestamp()
);
alter table private.final_result_release_verifications enable row level security;
alter table private.final_result_release_artifact_proofs enable row level security;
alter table private.final_result_release_readiness enable row level security;
revoke all on private.final_result_release_verifications,private.final_result_release_artifact_proofs,private.final_result_release_readiness from public,anon,authenticated,service_role;
create trigger final_result_release_verifications_immutable before update or delete on private.final_result_release_verifications
  for each row execute function private.result_query_immutable_guard();
create trigger final_result_release_artifact_proofs_immutable before update or delete on private.final_result_release_artifact_proofs
  for each row execute function private.result_query_immutable_guard();
create trigger final_result_release_readiness_immutable before update or delete on private.final_result_release_readiness
  for each row execute function private.result_query_immutable_guard();
create index final_result_release_verifications_run_idx on private.final_result_release_verifications(release_run_id);

-- Only trusted service APIs use this explicit actor context. It does not change
-- JWT claims or give a service credential execute access to manager commands.
create function private.final_result_verification_context(p_run uuid,p_plan_hash text,p_actor uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_run private.lca_release_runs%rowtype; v_plan private.final_result_release_plans%rowtype;
 v_runtime private.final_result_query_runtime_revisions%rowtype; v_current uuid; v_permission text;
begin
 select * into v_run from private.lca_release_runs where id=p_run;
 if not found or v_run.publication_format<>'final-result-pair.v2' or v_run.publish_plan_hash is distinct from p_plan_hash
   or v_run.status not in ('prepared','ready_for_approval','approved') then
   raise exception using errcode='55000',message='Final Result verification context is no longer eligible'; end if;
 select * into strict v_plan from private.final_result_release_plans where release_run_id=p_run;
 if not exists(select 1 from private.final_result_release_selection_seals where release_run_id=p_run and selection_hash=v_run.selection_manifest_hash) then
   raise exception using errcode='55000',message='Final Result verification context is no longer eligible'; end if;
 select r.* into v_runtime from private.final_result_query_runtime_head h join private.final_result_query_runtime_revisions r on r.id=h.revision_id where h.singleton;
 select id into v_current from private.lca_release_publications where publication_series_key='global' and publication_channel='public'
   and visibility_scope='public' and is_current and status='current';
 select encode(extensions.digest(convert_to('tiangong.final-result-manager-precondition.v1'||E'\n'||r.user_id::text||E'\n'||
   coalesce(extract(epoch from r.created_at)::text,'')||E'\n'||coalesce(extract(epoch from r.modified_at)::text,'')||E'\n','UTF8'),'sha256'),'hex')
   into v_permission from private.roles r where r.user_id=p_actor and r.team_id='00000000-0000-0000-0000-000000000000' and r.role='data_product_manager';
 if v_permission is null or v_runtime.id is null or not v_runtime.enabled or v_runtime.target_hash<>v_plan.target_hash
   or v_current is distinct from v_plan.expected_current_publication_id then
   raise exception using errcode='55000',message='Final Result verification context is no longer eligible'; end if;
 return jsonb_build_object('releaseRunId',p_run,'publishPlanHash',p_plan_hash,'candidateHash',v_plan.candidate_hash,'targetHash',v_plan.target_hash,
   'selectionHash',v_run.selection_manifest_hash,'selectionCount',v_plan.selection_count,'runtimeRevision',v_runtime.id,'readerSha256',v_runtime.reader_sha256,
   'actorId',p_actor,'permissionHash',v_permission,'scope',jsonb_build_object('kind','readiness','releaseRunId',p_run,'selectionHash',v_run.selection_manifest_hash),
   'publicationAuthorized',false);
end;
$$;
revoke all on function private.final_result_verification_context(uuid,text,uuid) from public,anon,authenticated,service_role;

create function api.svc_final_result_readiness_begin_v2(p_header jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_run uuid; v_old jsonb; v_context jsonb; v_files jsonb; v_started timestamptz; v_checked timestamptz;
begin
 if p_header is null or jsonb_typeof(p_header)<>'object' or pg_column_size(p_header)>32768
   or octet_length(p_header::text)>32768 or (select count(*) from jsonb_object_keys(p_header))<>15
   or p_header->>'schemaVersion' is distinct from 'tiangong.final-result-readiness-attempt.v1' then
   raise exception using errcode='22023',message='Invalid final Result readiness attempt'; end if;
 v_id:=(p_header->>'verificationId')::uuid; v_run:=(p_header->>'releaseRunId')::uuid;
 if v_id is null or v_run is null then raise exception using errcode='22023',message='Invalid final Result readiness attempt'; end if;
 perform pg_advisory_xact_lock(883,hashtext(v_id::text));
 select header into v_old from private.final_result_release_verifications where id=v_id;
 if found then
   if v_old<>p_header then raise exception using errcode='23505',message='Final Result readiness attempt identity conflict'; end if;
   return jsonb_build_object('ok',true,'data',jsonb_build_object('verificationId',v_id,'releaseRunId',v_run,'reused',true,'publicationAuthorized',false));
 end if;
 v_context:=private.final_result_verification_context(v_run,p_header->>'publishPlanHash',(p_header->>'actorId')::uuid);
 if (p_header-array['schemaVersion','verificationId','startedAt','candidateFilesVerifiedAt','candidateFiles'])
    is distinct from (v_context-array['scope','publicationAuthorized']) then
   raise exception using errcode='22023',message='Final Result readiness context mismatch'; end if;
 v_started:=(p_header->>'startedAt')::timestamptz; v_checked:=(p_header->>'candidateFilesVerifiedAt')::timestamptz;
 if v_started is null or v_checked is null or not isfinite(v_started) or not isfinite(v_checked)
   or v_started<clock_timestamp()-interval '1 hour' or v_checked<v_started or v_checked>clock_timestamp()+interval '30 seconds' then
   raise exception using errcode='22023',message='Final Result file verification is stale or invalid'; end if;
 select receipt->'files' into v_files from private.final_result_candidate_storage
   where candidate_hash=p_header->>'candidateHash' and target_hash=p_header->>'targetHash';
 if p_header->'candidateFiles' is distinct from v_files then
   raise exception using errcode='22023',message='Final Result Candidate file coverage mismatch'; end if;
 insert into private.final_result_release_verifications(id,release_run_id,runtime_revision,header)
   values(v_id,v_run,(p_header->>'runtimeRevision')::uuid,p_header);
 return jsonb_build_object('ok',true,'data',jsonb_build_object('verificationId',v_id,'releaseRunId',v_run,'reused',false,'publicationAuthorized',false));
end;
$$;

create function api.svc_final_result_readiness_artifacts_v2(p_verification_id uuid,p_proofs jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_attempt private.final_result_release_verifications%rowtype; v_context jsonb; v_proof jsonb; v_old jsonb;
 v_id uuid; v_artifact private.final_result_query_artifacts%rowtype; v_files jsonb; v_probe jsonb; v_expected jsonb;
 v_first text; v_last text; v_count bigint; v_keys text[]; v_actual text[]; v_started timestamptz; v_checked timestamptz;
 v_n bigint; v_pages integer; v_impact integer; v_inserted integer:=0;
begin
 if p_verification_id is null or p_proofs is null or jsonb_typeof(p_proofs)<>'array' or jsonb_array_length(p_proofs) not between 1 and 100
   or pg_column_size(p_proofs)>1048576 or octet_length(p_proofs::text)>1048576 then
   raise exception using errcode='22023',message='Invalid bounded final Result readiness batch'; end if;
 perform pg_advisory_xact_lock(883,hashtext(p_verification_id::text));
 select * into v_attempt from private.final_result_release_verifications where id=p_verification_id;
 if not found then raise exception using errcode='55000',message='Final Result readiness attempt is absent'; end if;
 for v_proof in select value from jsonb_array_elements(p_proofs) loop
   if jsonb_typeof(v_proof)<>'object' or (select count(*) from jsonb_object_keys(v_proof))<>5
     or pg_column_size(v_proof)>65536 or octet_length(v_proof::text)>65536 then
     raise exception using errcode='22023',message='Invalid final Result artifact proof'; end if;
   v_id:=(v_proof#>>'{artifact,artifactId}')::uuid;
   select proof into v_old from private.final_result_release_artifact_proofs where verification_id=p_verification_id and artifact_id=v_id;
   if found then
     if v_old<>v_proof then raise exception using errcode='23505',message='Final Result artifact proof identity conflict'; end if;
     continue;
   end if;
   if exists(select 1 from private.final_result_release_readiness where verification_id=p_verification_id) then
     raise exception using errcode='55000',message='Final Result readiness is sealed'; end if;
   v_context:=private.final_result_verification_context(v_attempt.release_run_id,v_attempt.header->>'publishPlanHash',(v_attempt.header->>'actorId')::uuid);
   if (v_attempt.header-array['schemaVersion','verificationId','startedAt','candidateFilesVerifiedAt','candidateFiles'])
       is distinct from (v_context-array['scope','publicationAuthorized']) then
     raise exception using errcode='55000',message='Final Result verification context changed'; end if;
   select * into v_artifact from private.final_result_query_artifacts where id=v_id;
   select min((result_id::text||'@'||result_version) collate "C"),max((result_id::text||'@'||result_version) collate "C"),count(*)
     into v_first,v_last,v_count from private.final_result_release_members where release_run_id=v_attempt.release_run_id and artifact_id=v_id;
   if v_artifact.id is null or v_count=0 or v_proof->'artifact' is distinct from v_artifact.artifact_ref
     or v_proof->'selectedResultCount' is distinct from to_jsonb(v_count) then
     raise exception using errcode='22023',message='Final Result artifact selection mismatch'; end if;
   select receipt->'files' into v_files from private.final_result_query_seals where artifact_id=v_id and target_hash=v_context->>'targetHash';
   if v_proof->'files' is distinct from v_files then
     raise exception using errcode='22023',message='Final Result artifact file coverage mismatch'; end if;
   v_checked:=(v_proof->>'filesVerifiedAt')::timestamptz;
   if v_checked is null or not isfinite(v_checked) or v_checked<(v_attempt.header->>'startedAt')::timestamptz
     or (v_attempt.header->>'startedAt')::timestamptz<clock_timestamp()-interval '1 hour' or v_checked>clock_timestamp()+interval '30 seconds' then
     raise exception using errcode='22023',message='Final Result file verification is stale or invalid'; end if;
   v_keys:=case when v_first=v_last then array[v_first] else array[v_first,v_last] end;
   if jsonb_typeof(v_proof->'probes') is distinct from 'array' or jsonb_array_length(v_proof->'probes')<>cardinality(v_keys) then
     raise exception using errcode='22023',message='Final Result probe coverage mismatch'; end if;
   select array_agg((value#>>'{result,uuid}')||'@'||(value#>>'{result,version}') order by ((value#>>'{result,uuid}')||'@'||(value#>>'{result,version}')) collate "C")
     into v_actual from jsonb_array_elements(v_proof->'probes');
   if v_actual is distinct from v_keys then raise exception using errcode='22023',message='Final Result probe coverage mismatch'; end if;
   for v_probe in select value from jsonb_array_elements(v_proof->'probes') loop
     select v_context||jsonb_build_object('artifact',v_artifact.artifact_ref,'result',jsonb_build_object('uuid',m.result_id,'version',m.result_version),
       'contentHash',q.content_hash,'lciAvailable',true,'lciaAvailable',v_artifact.impact_count>0)
       into v_expected from private.final_result_release_members m join private.final_result_query_rows q
       on q.artifact_id=m.artifact_id and q.row_ordinal=m.row_ordinal and q.result_id=m.result_id and q.result_version=m.result_version
       join private.final_result_identities i on i.result_id=q.result_id and i.result_version=q.result_version
       and i.registration_id=q.registration_id and i.content_hash=q.content_hash and i.registration_kind='registered'
       where m.release_run_id=v_attempt.release_run_id and m.artifact_id=v_id and m.result_id=(v_probe#>>'{result,uuid}')::uuid and m.result_version=v_probe#>>'{result,version}';
     if v_expected is null or v_probe->>'schemaVersion' is distinct from 'tiangong.final-result-reader-probe.v1'
       or (v_probe-array['schemaVersion','startedAt','verifiedAt','lciNonzeroCount','lciPageCount','lciaCount','queryCount','observationsSha256']) is distinct from v_expected
       or coalesce(v_probe->>'observationsSha256','') !~ '^[0-9a-f]{64}$' then
       raise exception using errcode='22023',message='Final Result reader probe binding mismatch'; end if;
     v_started:=(v_probe->>'startedAt')::timestamptz; v_checked:=(v_probe->>'verifiedAt')::timestamptz;
     if v_started is null or v_checked is null or not isfinite(v_started) or not isfinite(v_checked)
       or v_started<greatest(clock_timestamp()-interval '15 minutes',(v_attempt.header->>'startedAt')::timestamptz)
       or v_checked<v_started or v_checked>clock_timestamp()+interval '30 seconds' then
       raise exception using errcode='22023',message='Final Result reader verification is stale or invalid'; end if;
     if jsonb_typeof(v_probe->'lciNonzeroCount') is distinct from 'number' or coalesce(v_probe->>'lciNonzeroCount','') !~ '^[0-9]+$' then
       raise exception using errcode='22023',message='Final Result probe count mismatch'; end if;
     v_n:=(v_probe->>'lciNonzeroCount')::bigint;
     v_pages:=1+ceil(greatest(v_n-1,0)::numeric/1000)::integer;
     v_impact:=v_artifact.impact_count;
     if v_n>2000000 or v_probe->'lciPageCount' is distinct from to_jsonb(v_pages)
       or v_probe->'lciaCount' is distinct from to_jsonb(v_impact)
       or v_probe->'queryCount' is distinct from to_jsonb(v_pages+1+case when v_impact>0 then 1 else 0 end) then
       raise exception using errcode='22023',message='Final Result probe count mismatch'; end if;
   end loop;
   insert into private.final_result_release_artifact_proofs(verification_id,artifact_id,proof,proof_sha256)
     values(p_verification_id,v_id,v_proof,encode(extensions.digest(convert_to(v_proof::text,'UTF8'),'sha256'),'hex'));
   v_inserted:=v_inserted+1;
 end loop;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('verificationId',p_verification_id,'insertedArtifactCount',v_inserted,'publicationAuthorized',false));
end;
$$;

create function api.svc_final_result_readiness_seal_v2(p_verification_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_attempt private.final_result_release_verifications%rowtype; v_context jsonb; v_receipt jsonb;
 v_count bigint; v_expected bigint; v_probe_count bigint; v_files bigint; v_expires timestamptz; v_hash text;
begin
 if p_verification_id is null then raise exception using errcode='22023',message='Final Result verification identity is required'; end if;
 perform pg_advisory_xact_lock(883,hashtext(p_verification_id::text));
 select receipt into v_receipt from private.final_result_release_readiness where verification_id=p_verification_id;
 if found then return jsonb_build_object('ok',true,'data',v_receipt); end if;
 select * into v_attempt from private.final_result_release_verifications where id=p_verification_id;
 if not found then raise exception using errcode='55000',message='Final Result readiness attempt is absent'; end if;
 v_context:=private.final_result_verification_context(v_attempt.release_run_id,v_attempt.header->>'publishPlanHash',(v_attempt.header->>'actorId')::uuid);
 if (v_attempt.header-array['schemaVersion','verificationId','startedAt','candidateFilesVerifiedAt','candidateFiles'])
     is distinct from (v_context-array['scope','publicationAuthorized']) then
   raise exception using errcode='55000',message='Final Result verification context changed'; end if;
 select count(distinct artifact_id) into v_expected from private.final_result_release_members where release_run_id=v_attempt.release_run_id;
 select count(*),coalesce(sum(jsonb_array_length(proof->'probes')),0),coalesce(sum(jsonb_array_length(proof->'files')),0)+4
   into v_count,v_probe_count,v_files from private.final_result_release_artifact_proofs where verification_id=p_verification_id;
 if v_count<>v_expected or v_count=0 then raise exception using errcode='55000',message='Final Result readiness coverage is incomplete'; end if;
 select least((v_attempt.header->>'startedAt')::timestamptz+interval '1 hour',min((p.value->>'startedAt')::timestamptz)+interval '15 minutes')
   into v_expires from private.final_result_release_artifact_proofs a cross join lateral jsonb_array_elements(a.proof->'probes') p
   where verification_id=p_verification_id;
 if v_expires<=clock_timestamp() then raise exception using errcode='55000',message='Final Result readiness evidence expired'; end if;
 -- Database-only JSONB proof hashes, never represented as canonical content/JCS.
 with numbered as (select artifact_id,proof_sha256,(row_number() over(order by artifact_id)-1)/500 block
   from private.final_result_release_artifact_proofs where verification_id=p_verification_id),
 blocks as (select block,encode(extensions.digest(convert_to(string_agg(artifact_id::text||'@'||proof_sha256||E'\n','' order by artifact_id),'UTF8'),'sha256'),'hex') hash
   from numbered group by block)
 select encode(extensions.digest(convert_to('tiangong.final-result-readiness-coverage.jsonb.v1'||E'\n'||string_agg(hash||E'\n','' order by block),'UTF8'),'sha256'),'hex') into v_hash from blocks;
 v_receipt:=v_context||jsonb_build_object('schemaVersion','tiangong.final-result-readiness.v1','verificationId',p_verification_id,
   'artifactCount',v_count,'probeCount',v_probe_count,'fileCount',v_files,'coverageHash',v_hash,'expiresAt',v_expires,'sealedAt',clock_timestamp());
 insert into private.final_result_release_readiness(verification_id,receipt,expires_at) values(p_verification_id,v_receipt,v_expires);
 return jsonb_build_object('ok',true,'data',v_receipt);
end;
$$;
create function api.svc_final_result_readiness_describe_v2(p_verification_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('ok',true,'data',(select jsonb_build_object('verificationId',v.id,'header',v.header,
   'registeredArtifactCount',(select count(*) from private.final_result_release_artifact_proofs where verification_id=v.id),
   'readinessReceipt',(select receipt from private.final_result_release_readiness where verification_id=v.id),'publicationAuthorized',false)
   from private.final_result_release_verifications v where v.id=p_verification_id));
$$;
revoke all on function api.svc_final_result_readiness_begin_v2(jsonb),api.svc_final_result_readiness_artifacts_v2(uuid,jsonb),
 api.svc_final_result_readiness_seal_v2(uuid),api.svc_final_result_readiness_describe_v2(uuid) from public,anon,authenticated,service_role;
grant execute on function api.svc_final_result_readiness_begin_v2(jsonb),api.svc_final_result_readiness_artifacts_v2(uuid,jsonb),
 api.svc_final_result_readiness_seal_v2(uuid),api.svc_final_result_readiness_describe_v2(uuid) to service_role;
insert into private.api_capability_grants(routine_identity,capability_id,allow_anon,allow_authenticated,allow_service_role) values
 ('api.svc_final_result_readiness_begin_v2(jsonb)','EDGE-DATA-PRODUCT-01',false,false,true),
 ('api.svc_final_result_readiness_artifacts_v2(uuid, jsonb)','EDGE-DATA-PRODUCT-01',false,false,true),
 ('api.svc_final_result_readiness_seal_v2(uuid)','EDGE-DATA-PRODUCT-01',false,false,true),
 ('api.svc_final_result_readiness_describe_v2(uuid)','EDGE-DATA-PRODUCT-01',false,false,true);
notify pgrst,'reload schema';
commit;
