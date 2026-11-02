begin;
set local lock_timeout = '5s';

-- V2 belongs to the registered final Result, never to a synthetic calculation
-- package. These are private storage/mapping facts, not publication authority.
create table private.final_result_query_artifacts (
  id uuid primary key,
  input_hash text not null check (input_hash ~ '^[0-9a-f]{64}$'),
  artifact_ref jsonb not null,
  manifest_text text not null check (octet_length(manifest_text) between 1 and 1048576),
  manifest jsonb not null,
  result_count integer not null check (result_count between 1 and 2000000),
  impact_count integer not null check (impact_count between 0 and 4096),
  created_at timestamptz not null default now()
);
create table private.final_result_query_rows (
  artifact_id uuid not null references private.final_result_query_artifacts(id),
  row_ordinal integer not null check (row_ordinal between 0 and 1999999),
  result_id uuid not null,
  result_version text not null,
  registration_id uuid not null references private.final_result_identities(registration_id),
  content_hash text not null check (content_hash ~ '^[0-9a-f]{64}$'),
  relation_kind text not null check (relation_kind in ('direct','derived')),
  row_data jsonb not null,
  row_hash text not null check (row_hash ~ '^[0-9a-f]{64}$'),
  primary key (artifact_id,row_ordinal),
  unique (artifact_id,result_id,result_version),
  foreign key (result_id,result_version) references private.final_result_identities(result_id,result_version)
);
create table private.final_result_query_sources (
  artifact_id uuid not null,
  row_ordinal integer not null,
  source_id uuid not null,
  source_version text not null check (source_version ~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$'),
  primary key (artifact_id,row_ordinal,source_id,source_version),
  foreign key (artifact_id,row_ordinal) references private.final_result_query_rows(artifact_id,row_ordinal)
);
create index final_result_query_source_lookup_idx on private.final_result_query_sources(source_id,source_version,artifact_id,row_ordinal);
create table private.final_result_query_seals (
  artifact_id uuid not null references private.final_result_query_artifacts(id),
  target_hash text not null check (target_hash ~ '^[0-9a-f]{64}$'),
  row_bindings_hash text not null check (row_bindings_hash ~ '^[0-9a-f]{64}$'),
  readback_id uuid not null unique,
  receipt jsonb not null,
  sealed_at timestamptz not null default now(),
  primary key (artifact_id,target_hash)
);

alter table private.final_result_query_artifacts enable row level security;
alter table private.final_result_query_rows enable row level security;
alter table private.final_result_query_sources enable row level security;
alter table private.final_result_query_seals enable row level security;
revoke all on private.final_result_query_artifacts,private.final_result_query_rows,
  private.final_result_query_sources,private.final_result_query_seals from public,anon,authenticated,service_role;
create trigger final_result_query_artifacts_immutable before update or delete on private.final_result_query_artifacts
  for each row execute function private.result_query_immutable_guard();
create trigger final_result_query_rows_immutable before update or delete on private.final_result_query_rows
  for each row execute function private.result_query_immutable_guard();
create trigger final_result_query_sources_immutable before update or delete on private.final_result_query_sources
  for each row execute function private.result_query_immutable_guard();
create trigger final_result_query_seals_immutable before update or delete on private.final_result_query_seals
  for each row execute function private.result_query_immutable_guard();

create function private.final_result_query_uint(p_value jsonb,p_max bigint)
returns bigint language plpgsql immutable set search_path = '' as $$
begin
  if jsonb_typeof(p_value) is distinct from 'number' or (p_value#>>'{}') !~ '^(0|[1-9][0-9]{0,15})$' then
    raise exception using errcode='22023',message='Invalid final Result query integer';
  end if;
  if (p_value#>>'{}')::bigint > p_max then
    raise exception using errcode='22023',message='Final Result query integer exceeds budget';
  end if;
  return (p_value#>>'{}')::bigint;
end;
$$;

-- ASCII-only identity metadata has an explicit wire hash, independent of JSONB
-- serialization and of the canonical Result content hash. Every line ends LF.
create function private.final_result_query_row_hash(p_row jsonb)
returns text language sql immutable set search_path = '' as $$
  select encode(extensions.digest(convert_to(
    'tiangong.final-result-row.v1' || E'\n' || (p_row->>'ordinal') || E'\n'
    || (p_row->>'uuid') || E'\n' || (p_row->>'version') || E'\n'
    || (p_row->>'registrationId') || E'\n' || (p_row->>'contentHash') || E'\n'
    || (p_row->>'relationKind') || E'\n'
    || (select string_agg((value->>'uuid') || '@' || (value->>'version') || E'\n',''
        order by (value->>'uuid') collate "C",(value->>'version') collate "C")
        from jsonb_array_elements(p_row->'sources')),'UTF8'),'sha256'),'hex')
$$;

create function api.svc_result_query_stage_v2(p_artifact_ref jsonb,p_manifest_text text,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid; v_manifest jsonb; v_file jsonb; v_row jsonb; v_source jsonb;
  v_names text[]; v_expected text[]; v_size bigint; v_total bigint:=0;
  v_count integer; v_impacts integer; v_ordinal integer; v_sources jsonb;
  v_existing private.final_result_query_artifacts%rowtype;
  v_identity private.final_result_identities%rowtype;
  v_old private.final_result_query_rows%rowtype;
begin
  if jsonb_typeof(p_artifact_ref) is distinct from 'object'
    or jsonb_typeof(p_rows) is distinct from 'array'
    or p_manifest_text is null or octet_length(p_manifest_text) not between 1 and 1048576
    or pg_column_size(p_rows)>1048576 or octet_length(p_rows::text)>1048576 then
    raise exception using errcode='22023',message='Invalid final Result query stage input';
  end if;
  if jsonb_array_length(p_rows) not between 1 and 500
    or (select count(*) from jsonb_object_keys(p_artifact_ref))<>4
    or p_artifact_ref->>'schemaVersion' is distinct from 'tiangong.query-artifact.v2'
    or jsonb_typeof(p_artifact_ref->'manifestSha256') is distinct from 'string'
    or coalesce(p_artifact_ref->>'artifactId','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    or coalesce(p_artifact_ref->>'manifestSha256','') !~ '^[0-9a-f]{64}$'
    or private.final_result_query_uint(p_artifact_ref->'manifestByteSize',1048576) <> octet_length(p_manifest_text)
    or encode(extensions.digest(convert_to(p_manifest_text,'UTF8'),'sha256'),'hex') <> p_artifact_ref->>'manifestSha256' then
    raise exception using errcode='22023',message='Final Result query manifest bytes mismatch';
  end if;
  if not (p_manifest_text is json object with unique keys) then
    raise exception using errcode='22023',message='Invalid final Result query manifest';
  end if;
  v_manifest:=p_manifest_text::jsonb;
  if jsonb_typeof(v_manifest) is distinct from 'object' then
    raise exception using errcode='22023',message='Invalid final Result query manifest';
  end if;
  if (select count(*) from jsonb_object_keys(v_manifest))<>8
    or v_manifest->>'schemaVersion' is distinct from 'tiangong.query-artifact.v2'
    or v_manifest->>'artifactId' is distinct from p_artifact_ref->>'artifactId'
    or jsonb_typeof(v_manifest->'source') is distinct from 'object'
    or v_manifest#>>'{source,schemaVersion}' is distinct from 'tiangong.final-result-projection.v1'
    or jsonb_typeof(v_manifest#>'{source,inputHash}') is distinct from 'string'
    or coalesce(v_manifest#>>'{source,inputHash}','') !~ '^[0-9a-f]{64}$'
    or jsonb_typeof(v_manifest->'files') is distinct from 'array' then
    raise exception using errcode='22023',message='Invalid final Result query manifest';
  end if;
  if (select count(*) from jsonb_object_keys(v_manifest->'source'))<>2 then
    raise exception using errcode='22023',message='Invalid final Result query source';
  end if;
  v_count:=private.final_result_query_uint(v_manifest->'resultCount',2000000);
  v_impacts:=private.final_result_query_uint(v_manifest->'impactCount',4096);
  perform private.final_result_query_uint(v_manifest->'inventoryCount',2000000);
  perform private.final_result_query_uint(v_manifest->'lciNonzeroCount',4000000000000);
  if v_count=0 or (v_manifest->>'lciNonzeroCount')::bigint > v_count::bigint * (v_manifest->>'inventoryCount')::bigint then
    raise exception using errcode='22023',message='Invalid final Result query dimensions';
  end if;
  v_expected:=case when v_impacts=0 then array['inventory-items.json.gz','lci.h5','results.json.gz']
    else array['impacts.json.gz','inventory-items.json.gz','lci.h5','lcia.h5','results.json.gz'] end;
  if jsonb_array_length(v_manifest->'files')<>cardinality(v_expected) then
    raise exception using errcode='22023',message='Invalid final Result query file set';
  end if;
  for v_file in select value from jsonb_array_elements(v_manifest->'files') loop
    if jsonb_typeof(v_file) is distinct from 'object' then
      raise exception using errcode='22023',message='Invalid final Result query file';
    end if;
    if not coalesce(v_file->>'name'=any(v_expected),false)
      or jsonb_typeof(v_file->'sha256') is distinct from 'string'
      or coalesce(v_file->>'sha256','') !~ '^[0-9a-f]{64}$'
      or (select count(*) from jsonb_object_keys(v_file)) <> (case when v_file->>'name' like '%.gz' then 4 else 3 end) then
      raise exception using errcode='22023',message='Invalid final Result query file';
    end if;
    v_size:=private.final_result_query_uint(v_file->'byteSize',34359738368);
    if v_size=0 then raise exception using errcode='22023',message='Empty final Result query file'; end if;
    v_total:=v_total+v_size;
    if v_file->>'name' like '%.gz' then
      if private.final_result_query_uint(v_file->'plainByteSize',134217728)=0 then
        raise exception using errcode='22023',message='Empty final Result query index';
      end if;
    end if;
  end loop;
  select array_agg(value->>'name' order by (value->>'name') collate "C") into v_names from jsonb_array_elements(v_manifest->'files');
  if v_names<>v_expected or v_total>34359738368 then
    raise exception using errcode='22023',message='Final Result query file set or budget mismatch';
  end if;
  v_id:=(p_artifact_ref->>'artifactId')::uuid;
  perform pg_advisory_xact_lock(hashtextextended(v_id::text,879));
  select * into v_existing from private.final_result_query_artifacts where id=v_id for update;
  if found then
    if v_existing.artifact_ref<>p_artifact_ref or v_existing.manifest_text<>p_manifest_text then
      raise exception using errcode='23505',message='Final Result query artifact identity conflict';
    end if;
  else
    insert into private.final_result_query_artifacts(id,input_hash,artifact_ref,manifest_text,manifest,result_count,impact_count)
      values(v_id,v_manifest#>>'{source,inputHash}',p_artifact_ref,p_manifest_text,v_manifest,v_count,v_impacts);
  end if;
  for v_row in select value from jsonb_array_elements(p_rows) loop
    if jsonb_typeof(v_row) is distinct from 'object' then
      raise exception using errcode='22023',message='Invalid final Result query row';
    end if;
    if (select count(*) from jsonb_object_keys(v_row))<>7
      or coalesce(v_row->>'uuid','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      or coalesce(v_row->>'version','') !~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$'
      or coalesce(v_row->>'registrationId','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      or jsonb_typeof(v_row->'contentHash') is distinct from 'string'
      or coalesce(v_row->>'contentHash','') !~ '^[0-9a-f]{64}$'
      or coalesce(v_row->>'relationKind','') not in ('direct','derived')
      or jsonb_typeof(v_row->'sources') is distinct from 'array' then
      raise exception using errcode='22023',message='Invalid final Result query row';
    end if;
    v_ordinal:=private.final_result_query_uint(v_row->'ordinal',v_count-1);
    if jsonb_array_length(v_row->'sources') not between 1 and 4096
      or (v_row->>'relationKind'='direct' and jsonb_array_length(v_row->'sources')<>1) then
      raise exception using errcode='22023',message='Invalid final Result query lineage';
    end if;
    for v_source in select value from jsonb_array_elements(v_row->'sources') loop
      if jsonb_typeof(v_source) is distinct from 'object' then
        raise exception using errcode='22023',message='Invalid final Result query source identity';
      end if;
      if (select count(*) from jsonb_object_keys(v_source))<>2
        or coalesce(v_source->>'uuid','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        or coalesce(v_source->>'version','') !~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$' then
        raise exception using errcode='22023',message='Invalid final Result query source identity';
      end if;
    end loop;
    select jsonb_agg(value order by (value->>'uuid') collate "C",(value->>'version') collate "C") into v_sources
      from (select distinct value from jsonb_array_elements(v_row->'sources')) sources;
    if jsonb_array_length(v_sources)<>jsonb_array_length(v_row->'sources') then
      raise exception using errcode='22023',message='Duplicate final Result query source identity';
    end if;
    v_row:=jsonb_set(v_row,'{sources}',v_sources);
    select * into v_identity from private.final_result_identities
      where result_id=(v_row->>'uuid')::uuid and result_version=v_row->>'version';
    if not found or v_identity.registration_kind<>'registered'
      or v_identity.registration_id<>(v_row->>'registrationId')::uuid
      or v_identity.content_hash<>v_row->>'contentHash' then
      raise exception using errcode='22023',message='Final Result query row has no matching registered content';
    end if;
    select * into v_old from private.final_result_query_rows
      where artifact_id=v_id and (row_ordinal=v_ordinal or (result_id=v_identity.result_id and result_version=v_identity.result_version));
    if found then
      if v_old.row_data<>v_row then
        raise exception using errcode='23505',message='Final Result query row identity conflict';
      end if;
    else
      if exists(select 1 from private.final_result_query_seals where artifact_id=v_id) then
        raise exception using errcode='55000',message='Sealed final Result query rows are immutable';
      end if;
      insert into private.final_result_query_rows values(v_id,v_ordinal,v_identity.result_id,v_identity.result_version,
        v_identity.registration_id,v_identity.content_hash,v_row->>'relationKind',v_row,private.final_result_query_row_hash(v_row));
      insert into private.final_result_query_sources
        select v_id,v_ordinal,(value->>'uuid')::uuid,value->>'version' from jsonb_array_elements(v_sources);
    end if;
  end loop;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('artifactId',v_id,
    'registeredResultCount',(select count(*) from private.final_result_query_rows where artifact_id=v_id),
    'publicationAuthorized',false));
end;
$$;

-- A trusted storage verifier supplies full GET/hash evidence, including the
-- actual result-axis/registration mapping. SQL validates its exact scope; it
-- does not pretend to fetch S3 or attest the reader executable. A seal is not
-- approval, current publication, fresh availability, or actor authorization.
create function api.svc_result_query_seal_v2(p_artifact_id uuid,p_receipt jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_artifact private.final_result_query_artifacts%rowtype;
  v_old private.final_result_query_seals%rowtype;
  v_count bigint; v_root text; v_files jsonb; v_time timestamptz;
begin
  if p_artifact_id is null or jsonb_typeof(p_receipt) is distinct from 'object'
    or pg_column_size(p_receipt)>1048576 or octet_length(p_receipt::text)>1048576 then
    raise exception using errcode='22023',message='Invalid final Result query seal receipt';
  end if;
  if (select count(*) from jsonb_object_keys(p_receipt))<>9
    or p_receipt->>'schemaVersion' is distinct from 'tiangong.final-result-query-readback.v1'
    or p_receipt->>'verification' is distinct from 'full-get-sha256-and-axis'
    or jsonb_typeof(p_receipt->'targetHash') is distinct from 'string'
    or jsonb_typeof(p_receipt->'rowBindingsSha256') is distinct from 'string'
    or coalesce(p_receipt->>'targetHash','') !~ '^[0-9a-f]{64}$'
    or coalesce(p_receipt->>'rowBindingsSha256','') !~ '^[0-9a-f]{64}$'
    or coalesce(p_receipt->>'readbackId','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    or jsonb_typeof(p_receipt->'verifiedAt') is distinct from 'string' then
    raise exception using errcode='22023',message='Invalid final Result query seal receipt';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_artifact_id::text,879));
  select * into v_artifact from private.final_result_query_artifacts where id=p_artifact_id for update;
  if not found or p_receipt->'artifact' is distinct from v_artifact.artifact_ref
    or p_receipt->>'inputHash' is distinct from v_artifact.input_hash then
    raise exception using errcode='22023',message='Final Result query seal artifact mismatch';
  end if;
  select * into v_old from private.final_result_query_seals
    where artifact_id=p_artifact_id and target_hash=p_receipt->>'targetHash';
  if found then
    if v_old.receipt<>p_receipt then
      raise exception using errcode='23505',message='Final Result query seal identity conflict';
    end if;
  else
    v_time:=(p_receipt->>'verifiedAt')::timestamptz;
    if not isfinite(v_time) or v_time < clock_timestamp()-interval '15 minutes' or v_time > clock_timestamp()+interval '30 seconds' then
      raise exception using errcode='22023',message='Final Result query readback is not fresh';
    end if;
    select count(*) into v_count from private.final_result_query_rows where artifact_id=p_artifact_id;
    if v_count<>v_artifact.result_count then
      raise exception using errcode='22023',message='Final Result query axis is incomplete';
    end if;
    -- 500 consecutive ordinals per block bounds aggregation to 32,500 bytes;
    -- at most 4,000 block hashes (260,000 bytes) form the final root. Never
    -- concatenate the entire 2M-row axis or trust caller-supplied row counts.
    select encode(extensions.digest(convert_to('tiangong.final-result-row-bindings.v1' || E'\n'
      || string_agg(block_hash || E'\n','' order by block),'UTF8'),'sha256'),'hex') into v_root
    from (select row_ordinal/500 as block,
      encode(extensions.digest(convert_to(string_agg(row_hash || E'\n','' order by row_ordinal),'UTF8'),'sha256'),'hex') as block_hash
      from private.final_result_query_rows where artifact_id=p_artifact_id group by row_ordinal/500) blocks;
    if v_root is distinct from p_receipt->>'rowBindingsSha256' then
      raise exception using errcode='22023',message='Final Result query axis readback mismatch';
    end if;
    select jsonb_agg(file order by (file->>'name') collate "C") into v_files from (
      select jsonb_build_object('name',value->>'name','sha256',value->>'sha256','byteSize',value->'byteSize') file
        from jsonb_array_elements(v_artifact.manifest->'files')
      union all select jsonb_build_object('name','manifest.json','sha256',v_artifact.artifact_ref->>'manifestSha256',
        'byteSize',v_artifact.artifact_ref->'manifestByteSize')
    ) files;
    if p_receipt->'files' is distinct from v_files then
      raise exception using errcode='22023',message='Final Result query file readback mismatch';
    end if;
    insert into private.final_result_query_seals(artifact_id,target_hash,row_bindings_hash,readback_id,receipt)
      values(p_artifact_id,p_receipt->>'targetHash',v_root,(p_receipt->>'readbackId')::uuid,p_receipt);
  end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('artifactId',p_artifact_id,
    'targetHash',p_receipt->>'targetHash','readbackId',p_receipt->>'readbackId',
    'rowBindingsSha256',p_receipt->>'rowBindingsSha256','sealed',true,'publicationAuthorized',false));
end;
$$;

revoke all on function private.final_result_query_uint(jsonb,bigint),private.final_result_query_row_hash(jsonb),
  api.svc_result_query_stage_v2(jsonb,text,jsonb),api.svc_result_query_seal_v2(uuid,jsonb) from public,anon,authenticated,service_role;
grant execute on function api.svc_result_query_stage_v2(jsonb,text,jsonb),api.svc_result_query_seal_v2(uuid,jsonb) to service_role;
insert into private.api_capability_grants(routine_identity,capability_id,allow_anon,allow_authenticated,allow_service_role) values
  ('api.svc_result_query_stage_v2(jsonb, text, jsonb)','EDGE-DATA-PRODUCT-01',false,false,true),
  ('api.svc_result_query_seal_v2(uuid, jsonb)','EDGE-DATA-PRODUCT-01',false,false,true);
notify pgrst,'reload schema';
commit;
