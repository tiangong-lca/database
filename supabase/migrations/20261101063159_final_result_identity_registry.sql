begin;

-- This registry binds the published meaning of a final Result, independently
-- of future Candidate/artifact/publication identities. It stores no numerics.
create table private.final_result_identities (
  result_id uuid not null,
  result_version text not null,
  registration_kind text not null default 'registered' check (registration_kind in ('registered','legacy')),
  registration_id uuid not null default gen_random_uuid() unique,
  hash_domain text check (hash_domain = 'tiangong.final-result-content.jcs.v1'),
  canonical_content_hash text check (canonical_content_hash ~ '^[0-9a-f]{64}$'),
  content_hash text check (content_hash ~ '^[0-9a-f]{64}$'),
  content_ref text,
  producer text not null check (length(producer) between 1 and 64),
  created_at timestamptz not null default now(),
  primary key (result_id,result_version),
  check ((registration_kind='registered' and result_version ~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$'
    and hash_domain is not null and canonical_content_hash is not null and content_hash is not null
    and content_ref is not null and content_ref = 'urn:sha256:' || canonical_content_hash)
    or (registration_kind='legacy' and hash_domain is null and canonical_content_hash is null
      and content_hash is null and content_ref is null))
);
alter table private.final_result_identities enable row level security;
revoke all on private.final_result_identities from public,anon,authenticated,service_role;
create trigger final_result_identities_immutable before update or delete
  on private.final_result_identities for each row execute function private.result_query_immutable_guard();

-- One unique ledger arbitrates v2 claims and legacy writes even under repeatable
-- read/serializable isolation. Legacy occupancy has no asserted content domain.
create index lca_release_dataset_global_process_identity_idx
  on private.lca_release_dataset_versions(dataset_uuid,dataset_version) where dataset_type='process';

create function private.final_result_legacy_claim(p_id uuid,p_version text)
returns void language plpgsql set search_path = '' as $$
declare v_kind text;
begin
  insert into private.final_result_identities(result_id,result_version,registration_kind,producer)
    values(p_id,p_version,'legacy','legacy-process-namespace') on conflict(result_id,result_version) do nothing;
  select registration_kind into strict v_kind from private.final_result_identities where result_id=p_id and result_version=p_version;
  if v_kind <> 'legacy' then
    raise exception using errcode='23505',message='Final Result identity is registered; legacy writes require explicit equivalence migration';
  end if;
end;
$$;
revoke all on function private.final_result_legacy_claim(uuid,text) from public,anon,authenticated,service_role;

create function private.final_result_legacy_write_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_old_id uuid; v_old_version text; v_new_id uuid; v_new_version text;
begin
  -- Project only the identity fields: process JSON may be large, and this
  -- trigger also runs for ordinary metadata/embedding updates.
  if tg_table_schema='public' and tg_table_name='processes' then
    if tg_op <> 'INSERT' then v_old_id:=old.id; v_old_version:=rtrim(old.version::text); end if;
    if tg_op <> 'DELETE' then v_new_id:=new.id; v_new_version:=rtrim(new.version::text); end if;
  elsif tg_table_schema='private' and tg_table_name='lca_release_dataset_versions' then
    if tg_op <> 'INSERT' and old.dataset_type='process' then
      v_old_id:=old.dataset_uuid; v_old_version:=old.dataset_version;
    end if;
    if tg_op <> 'DELETE' and new.dataset_type='process' then
      v_new_id:=new.dataset_uuid; v_new_version:=new.dataset_version;
    end if;
  elsif tg_table_schema='private' and tg_table_name='result_process_publications' then
    if tg_op <> 'INSERT' then v_old_id:=old.dataset_id; v_old_version:=old.dataset_version; end if;
    if tg_op <> 'DELETE' then v_new_id:=new.dataset_id; v_new_version:=new.dataset_version; end if;
  else
    raise exception using errcode='55000',message='Unexpected final Result identity guard target';
  end if;
  if v_old_id is not null then perform private.final_result_legacy_claim(v_old_id,v_old_version); end if;
  if v_new_id is not null and (v_new_id,v_new_version) is distinct from (v_old_id,v_old_version) then
    perform private.final_result_legacy_claim(v_new_id,v_new_version);
  end if;
  return null;
end;
$$;
revoke all on function private.final_result_legacy_write_guard() from public,anon,authenticated,service_role;
-- AFTER observes the final key after existing json_ordered/version normalization.
-- Rejection rolls back the row and transactional webhook/cache effects. Old keys
-- remain occupied after deletion or a version change; no Result is inferred.
create trigger final_result_identity_guard after insert or update or delete on public.processes
  for each row execute function private.final_result_legacy_write_guard();
create trigger final_result_identity_guard after insert or update or delete on private.lca_release_dataset_versions
  for each row execute function private.final_result_legacy_write_guard();
create trigger final_result_identity_guard after insert or update or delete on private.result_process_publications
  for each row execute function private.final_result_legacy_write_guard();

-- Trusted producer attests verified canonical document/dependency bytes. The
-- database independently computes the JCS envelope (only validated ASCII keys
-- and digests, no JSONB numeric serialization) and atomically claims identity.
create function api.svc_result_identity_register(p_request jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid; v_version text; v_content text; v_dependency jsonb;
  v_previous_key text; v_dependencies text:=''; v_envelope text; v_hash text;
  v_identity private.final_result_identities%rowtype;
begin
  if jsonb_typeof(p_request) is distinct from 'object' or pg_column_size(p_request)>8388608
    or p_request->>'schemaVersion' is distinct from 'tiangong.final-result-identity-request.v1'
    or p_request->>'hashDomain' is distinct from 'tiangong.final-result-content.jcs.v1'
    or jsonb_typeof(p_request->'result') is distinct from 'object'
    or jsonb_typeof(p_request->'semanticDependencies') is distinct from 'array'
    or coalesce(p_request->>'canonicalContentHash','') !~ '^[0-9a-f]{64}$'
    or coalesce(p_request->>'contentHash','') !~ '^[0-9a-f]{64}$'
    or coalesce(p_request#>>'{result,version}','') !~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$'
    or coalesce(p_request#>>'{result,uuid}','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    or jsonb_typeof(p_request->'producer') is distinct from 'string'
    or jsonb_typeof(p_request->'canonicalContentHash') is distinct from 'string'
    or jsonb_typeof(p_request->'contentHash') is distinct from 'string'
    or coalesce(length(p_request->>'producer'),0) not between 1 and 64 then
    raise exception using errcode='22023',message='Invalid final Result identity request';
  end if;
  if (select count(*) from jsonb_object_keys(p_request))<>7
    or (select count(*) from jsonb_object_keys(p_request->'result'))<>2
    or jsonb_array_length(p_request->'semanticDependencies') not between 1 and 50000 then
    raise exception using errcode='22023',message='Invalid final Result identity fields';
  end if;
  for v_dependency in select value from jsonb_array_elements(p_request->'semanticDependencies') loop
    if jsonb_typeof(v_dependency) is distinct from 'object'
      or jsonb_typeof(v_dependency->'contentHash') is distinct from 'string'
      or coalesce(v_dependency->>'contentHash','') !~ '^[0-9a-f]{64}$'
      or coalesce(v_dependency->>'key','') !~ '^(flow|flowproperty|unitgroup|lciamethod):[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}@[0-9]{2}\.[0-9]{2}\.[0-9]{3}$' then
      raise exception using errcode='22023',message='Invalid final Result semantic dependency';
    end if;
    if (select count(*) from jsonb_object_keys(v_dependency))<>2
      or (v_previous_key is not null and v_previous_key collate "C" >= (v_dependency->>'key') collate "C") then
      raise exception using errcode='22023',message='Final Result dependencies must be unique and canonically ordered';
    end if;
    v_previous_key:=v_dependency->>'key';
  end loop;
  select string_agg('{"contentHash":"' || (value->>'contentHash') || '","key":"' || (value->>'key') || '"}',',' order by ordinal)
    into v_dependencies from jsonb_array_elements(p_request->'semanticDependencies') with ordinality as entries(value,ordinal);
  v_id:=(p_request#>>'{result,uuid}')::uuid; v_version:=p_request#>>'{result,version}';
  v_content:=p_request->>'canonicalContentHash';
  v_envelope:='{"canonicalContentHash":"' || v_content
    || '","hashDomain":"tiangong.final-result-content.jcs.v1","semanticDependencies":[' || v_dependencies || ']}';
  v_hash:=encode(extensions.digest(convert_to(v_envelope,'UTF8'),'sha256'),'hex');
  if v_hash<>p_request->>'contentHash' then
    raise exception using errcode='22023',message='Final Result content envelope hash mismatch';
  end if;
  -- Legacy hash domains lack the frozen semantic-dependency evidence required
  -- here. Even equal-looking digests do not prove equivalence. No backfill or
  -- silent domain reinterpretation occurs in this migration.
  if exists(select 1 from public.processes where id=v_id and version=v_version)
    or exists(select 1 from private.result_process_publications where dataset_id=v_id and dataset_version=v_version)
    or exists(select 1 from private.lca_release_dataset_versions where dataset_type='process' and dataset_uuid=v_id and dataset_version=v_version) then
    raise exception using errcode='55000',message='Legacy Result identity is occupied; explicit equivalence migration or a new version is required';
  end if;
  insert into private.final_result_identities(result_id,result_version,hash_domain,canonical_content_hash,content_hash,content_ref,producer)
    values(v_id,v_version,p_request->>'hashDomain',v_content,v_hash,'urn:sha256:'||v_content,p_request->>'producer')
    on conflict(result_id,result_version) do nothing;
  select * into strict v_identity from private.final_result_identities where result_id=v_id and result_version=v_version;
  if v_identity.registration_kind='legacy' then
    raise exception using errcode='55000',message='Legacy Result identity is occupied; explicit equivalence migration or a new version is required';
  end if;
  if v_identity.hash_domain<>p_request->>'hashDomain' or v_identity.canonical_content_hash<>v_content or v_identity.content_hash<>v_hash then
    raise exception using errcode='23505',message='Final Result identity is already bound to different content';
  end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object(
    'schemaVersion','tiangong.final-result-identity-receipt.v1','registrationId',v_identity.registration_id,
    'result',jsonb_build_object('uuid',v_id,'version',v_version),'hashDomain',v_identity.hash_domain,
    'canonicalContentHash',v_identity.canonical_content_hash,'contentHash',v_identity.content_hash,
    'contentRef',v_identity.content_ref,'createdAt',v_identity.created_at));
end;
$$;

-- Occupancy is authoritative across registered and legacy producers. A page
-- never implies that unseen versions are available; registration is the CAS.
create function api.svc_result_identity_versions(p_result_id uuid,p_before_version text default null,p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_rows jsonb;
begin
  if p_result_id is null or p_limit is null or p_limit not between 1 and 256
    or (p_before_version is not null and p_before_version !~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$') then
    raise exception using errcode='22023',message='Invalid final Result version lookup';
  end if;
  with occupied as (
    select result_version as version from private.final_result_identities where result_id=p_result_id
    union select version::text from public.processes where id=p_result_id
    union select dataset_version from private.result_process_publications where dataset_id=p_result_id
    union select dataset_version from private.lca_release_dataset_versions where dataset_type='process' and dataset_uuid=p_result_id
  ), page as (
    select version from occupied where version ~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$'
      and (p_before_version is null or version collate "C" < p_before_version collate "C")
    order by version collate "C" desc limit p_limit
  )
  select coalesce(jsonb_agg(jsonb_build_object('version',page.version,'registrationId',case when identity.registration_kind='registered' then identity.registration_id else null end,
    'status',case when identity.registration_kind='registered' then 'registered' else 'legacy_requires_equivalence' end,
    'hashDomain',identity.hash_domain,'contentHash',identity.content_hash)
    order by page.version collate "C" desc),'[]'::jsonb) into v_rows
  from page left join private.final_result_identities identity on identity.result_id=p_result_id and identity.result_version=page.version;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('resultId',p_result_id,'versions',v_rows,
    'nextBeforeVersion',case when jsonb_array_length(v_rows)=p_limit then v_rows->(p_limit-1)->>'version' else null end));
end;
$$;
revoke all on function api.svc_result_identity_register(jsonb),api.svc_result_identity_versions(uuid,text,integer)
  from public,anon,authenticated,service_role;
grant execute on function api.svc_result_identity_register(jsonb),api.svc_result_identity_versions(uuid,text,integer) to service_role;
insert into private.api_capability_grants(routine_identity,capability_id,allow_anon,allow_authenticated,allow_service_role) values
  ('api.svc_result_identity_register(jsonb)','EDGE-DATA-PRODUCT-01',false,false,true),
  ('api.svc_result_identity_versions(uuid, text, integer)','EDGE-DATA-PRODUCT-01',false,false,true);
notify pgrst,'reload schema';
commit;
