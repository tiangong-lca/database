begin;

-- Final Result publication has no live legacy paired rows to translate. Keep
-- prior identity claims intact and refuse to reinterpret any staged row hashes.
lock table private.final_result_query_rows in access exclusive mode;
do $$
begin
  if exists (select 1 from private.final_result_query_rows) then
    raise exception using errcode='55000',
      message='Existing paired query rows require explicit disposition before switching the final Result row contract';
  end if;
end;
$$;
alter table private.final_result_query_rows
  drop constraint final_result_query_rows_result_id_result_version_fkey,
  drop column registration_id,
  add column canonical_content_hash text not null check (canonical_content_hash ~ '^[0-9a-f]{64}$');

-- Artifact rows carry their verified document digest. Candidate membership
-- checks it within one artifact set; public queries resolve by publication.
create or replace function private.final_result_query_row_hash(p_row jsonb)
returns text language sql immutable set search_path = '' as $$
  select encode(extensions.digest(convert_to(
    'tiangong.final-result-row.v2' || E'\n' || (p_row->>'ordinal') || E'\n'
    || (p_row->>'uuid') || E'\n' || (p_row->>'version') || E'\n'
    || (p_row->>'canonicalContentHash') || E'\n' || (p_row->>'contentHash') || E'\n'
    || (p_row->>'relationKind') || E'\n'
    || (select string_agg((value->>'uuid') || '@' || (value->>'version') || E'\n',''
        order by (value->>'uuid') collate "C",(value->>'version') collate "C")
        from jsonb_array_elements(p_row->'sources')),'UTF8'),'sha256'),'hex')
$$;

create or replace function api.svc_result_query_stage_v2(p_artifact_ref jsonb,p_manifest_text text,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid; v_manifest jsonb; v_file jsonb; v_row jsonb; v_source jsonb;
  v_names text[]; v_expected text[]; v_size bigint; v_total bigint:=0;
  v_count integer; v_impacts integer; v_ordinal integer; v_sources jsonb;
  v_existing private.final_result_query_artifacts%rowtype;
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
      or jsonb_typeof(v_row->'canonicalContentHash') is distinct from 'string'
      or coalesce(v_row->>'canonicalContentHash','') !~ '^[0-9a-f]{64}$'
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
    select * into v_old from private.final_result_query_rows
      where artifact_id=v_id and (row_ordinal=v_ordinal or (result_id=(v_row->>'uuid')::uuid and result_version=(v_row->>'version')));
    if found then
      if v_old.row_data<>v_row then
        raise exception using errcode='23505',message='Final Result query row identity conflict';
      end if;
    else
      if exists(select 1 from private.final_result_query_seals where artifact_id=v_id) then
        raise exception using errcode='55000',message='Sealed final Result query rows are immutable';
      end if;
      insert into private.final_result_query_rows(artifact_id,row_ordinal,result_id,result_version,canonical_content_hash,content_hash,relation_kind,row_data,row_hash) values(v_id,v_ordinal,(v_row->>'uuid')::uuid,(v_row->>'version'),
        v_row->>'canonicalContentHash',v_row->>'contentHash',v_row->>'relationKind',v_row,private.final_result_query_row_hash(v_row));
      insert into private.final_result_query_sources
        select v_id,v_ordinal,(value->>'uuid')::uuid,value->>'version' from jsonb_array_elements(v_sources);
    end if;
  end loop;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('artifactId',v_id,
    'registeredResultCount',(select count(*) from private.final_result_query_rows where artifact_id=v_id),
    'publicationAuthorized',false));
end;
$$;

create or replace function api.svc_result_candidate_register_v2(p_candidate_text text,p_catalog_text text,p_receipt jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_candidate jsonb; v_catalog jsonb; v_hash text; v_catalog_hash text; v_target text;
  v_artifact jsonb; v_member jsonb; v_file jsonb; v_reference jsonb; v_name text;
  v_expected_ref jsonb; v_files jsonb; v_keys text[]; v_roots text[];
  v_actual_keys text[]; v_actual_roots text[]; v_formats text[];
  v_count integer; v_results bigint:=0; v_old private.final_result_candidates%rowtype;
  v_stored private.final_result_query_artifacts%rowtype; v_storage private.final_result_candidate_storage%rowtype;
  v_time timestamptz;
begin
  if p_candidate_text is null or p_catalog_text is null
    or octet_length(p_candidate_text) not between 1 and 134217728
    or octet_length(p_catalog_text) not between 1 and 134217728
    or octet_length(p_candidate_text)::bigint+octet_length(p_catalog_text)>134217728
    or not (p_candidate_text is json object with unique keys)
    or not (p_catalog_text is json object with unique keys)
    or jsonb_typeof(p_receipt) is distinct from 'object' or octet_length(p_receipt::text)>16384 then
    raise exception using errcode='22023',message='Invalid final Result Candidate registration';
  end if;
  v_candidate:=p_candidate_text::jsonb; v_catalog:=p_catalog_text::jsonb;
  v_hash:=encode(extensions.digest(convert_to(p_candidate_text,'UTF8'),'sha256'),'hex');
  v_catalog_hash:=encode(extensions.digest(convert_to(p_catalog_text,'UTF8'),'sha256'),'hex');
  if (select count(*) from jsonb_object_keys(v_candidate))<>18
    or (select count(*) from jsonb_object_keys(v_catalog))<>6
    or v_candidate->>'schemaVersion' is distinct from 'tiangong.release.release-candidate.v3'
    or v_candidate->>'status' is distinct from 'local_candidate'
    or v_candidate->'candidateQualified' is distinct from 'true'::jsonb
    or v_candidate->'publicationAuthorized' is distinct from 'false'::jsonb
    or v_candidate->>'profile' is distinct from 'result-process-full-closure.v1'
    or coalesce(v_candidate->>'releaseVersion','') !~ '^[0-9]{4}\.[0-9]{2}\.[0-9]+$'
    or coalesce(v_candidate->>'inputHash','') !~ '^[0-9a-f]{64}$'
    or jsonb_typeof(v_candidate->'inputHash') is distinct from 'string'
    or coalesce(v_candidate->>'packageSetHash','') !~ '^[0-9a-f]{64}$'
    or jsonb_typeof(v_candidate->'packageSetHash') is distinct from 'string'
    or v_candidate#>>'{publicationCatalog,sha256}' is distinct from v_catalog_hash
    or v_candidate#>>'{validation,outcome}' is distinct from 'passed'
    or v_candidate#>>'{validation,finalResultParity}' is distinct from 'passed'
    or v_candidate#>>'{validation,finalInputBinding}' is distinct from 'verified'
    or v_candidate#>>'{validation,delegatedTo}' is distinct from 'tidas-tools'
    or jsonb_typeof(v_candidate#>'{validation,reportPath}') is distinct from 'string'
    or jsonb_typeof(v_candidate#>'{validation,archiveReadbackReportPath}') is distinct from 'string'
    or jsonb_typeof(v_candidate->'queryArtifacts') is distinct from 'array'
    or jsonb_typeof(v_candidate->'packages') is distinct from 'array'
    or v_catalog->>'schemaVersion' is distinct from 'tiangong.release.candidate-publication-catalog.v1'
    or coalesce(v_catalog->>'canonicalDatasetIndexSha256','') !~ '^[0-9a-f]{64}$'
    or jsonb_typeof(v_catalog->'canonicalDatasetIndexSha256') is distinct from 'string'
    or coalesce(v_catalog->>'catalogSetHash','') !~ '^[0-9a-f]{64}$'
    or jsonb_typeof(v_catalog->'catalogSetHash') is distinct from 'string'
    or v_catalog->>'canonicalDatasetIndexSha256' is distinct from v_candidate->>'canonicalDatasetIndexSha256'
    or jsonb_typeof(v_catalog->'datasets') is distinct from 'array'
    or v_catalog#>'{components,unitProcess,available}' is distinct from 'false'::jsonb
    or v_catalog#>'{components,unitProcess,roots}' is distinct from '[]'::jsonb
    or v_catalog#>'{components,unitProcess,datasets}' is distinct from '[]'::jsonb
    or v_catalog#>'{components,result,available}' is distinct from 'true'::jsonb
    or jsonb_typeof(v_catalog#>'{components,result,roots}') is distinct from 'array'
    or jsonb_typeof(v_catalog#>'{components,result,datasets}') is distinct from 'array' then
    raise exception using errcode='22023',message='Final Result Candidate/catalog binding mismatch';
  end if;
  if (select count(*) from jsonb_object_keys(v_candidate->'validation'))<>6
    or (select count(*) from jsonb_object_keys(v_catalog->'components'))<>2
    or (select count(*) from jsonb_object_keys(v_catalog#>'{components,result}'))<>3
    or (select count(*) from jsonb_object_keys(v_catalog#>'{components,unitProcess}'))<>3 then
    raise exception using errcode='22023',message='Invalid final Result Candidate qualification fields';
  end if;
  foreach v_name in array array['finalInput','inputPlan','sourceLineage','pair','queryResults','publicationCatalog'] loop
    v_reference:=v_candidate->v_name;
    if jsonb_typeof(v_reference) is distinct from 'object'
      or jsonb_typeof(v_reference->'sha256') is distinct from 'string'
      or coalesce(v_reference->>'sha256','') !~ '^[0-9a-f]{64}$'
      or jsonb_typeof(v_reference->'path') is distinct from 'string'
      or coalesce(length(v_reference->>'path'),0) not between 1 and 512 then
      raise exception using errcode='22023',message='Invalid final Result Candidate evidence reference';
    end if;
    if (select count(*) from jsonb_object_keys(v_reference))<>2 then
      raise exception using errcode='22023',message='Invalid final Result Candidate evidence reference';
    end if;
  end loop;
  v_count:=private.final_result_query_uint(v_catalog->'datasetCount',2000000);
  if v_count=0 or jsonb_array_length(v_catalog->'datasets')<>v_count
    or jsonb_array_length(v_candidate->'queryArtifacts') not between 1 and v_count
    or jsonb_array_length(v_candidate->'packages')<>2 then
    raise exception using errcode='22023',message='Invalid final Result Candidate coverage';
  end if;
  if (select count(*) from jsonb_object_keys(p_receipt))<>7
    or p_receipt->>'schemaVersion' is distinct from 'tiangong.final-result-candidate-readback.v1'
    or p_receipt->>'verification' is distinct from 'full-get-sha256-and-package-closure'
    or p_receipt->>'candidateSha256' is distinct from v_hash
    or coalesce(p_receipt->>'targetHash','') !~ '^[0-9a-f]{64}$'
    or jsonb_typeof(p_receipt->'targetHash') is distinct from 'string'
    or coalesce(p_receipt->>'readbackId','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    or jsonb_typeof(p_receipt->'verifiedAt') is distinct from 'string' then
    raise exception using errcode='22023',message='Invalid final Result Candidate readback receipt';
  end if;
  v_target:=p_receipt->>'targetHash';
  perform pg_advisory_xact_lock(hashtextextended(v_hash,880));
  select * into v_old from private.final_result_candidates where candidate_hash=v_hash;
  select * into v_storage from private.final_result_candidate_storage where candidate_hash=v_hash and target_hash=v_target;
  if v_storage.candidate_hash is not null then
    if v_storage.receipt<>p_receipt or v_old.catalog_hash<>v_catalog_hash then
      raise exception using errcode='23505',message='Final Result Candidate storage identity conflict';
    end if;
    return jsonb_build_object('ok',true,'data',jsonb_build_object('candidateHash',v_hash,'targetHash',v_target,
      'memberCount',v_old.member_count,'resultCount',v_old.result_count,'readbackId',v_storage.readback_id,'publicationAuthorized',false));
  end if;
  v_time:=(p_receipt->>'verifiedAt')::timestamptz;
  if not isfinite(v_time) or v_time < clock_timestamp()-interval '15 minutes' or v_time > clock_timestamp()+interval '30 seconds' then
    raise exception using errcode='22023',message='Final Result Candidate readback is not fresh';
  end if;
  for v_artifact in select value from jsonb_array_elements(v_candidate->'queryArtifacts') loop
    if jsonb_typeof(v_artifact) is distinct from 'object'
      or coalesce(v_artifact->>'artifactId','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception using errcode='22023',message='Invalid final Result Candidate artifact';
    end if;
    if (select count(*) from jsonb_object_keys(v_artifact))<>6
      or jsonb_typeof(v_artifact->'path') is distinct from 'string'
      or coalesce(length(v_artifact->>'path'),0) not between 1 and 512 then
      raise exception using errcode='22023',message='Invalid final Result Candidate artifact';
    end if;
    v_expected_ref:=jsonb_build_object('schemaVersion',v_artifact->'schemaVersion','artifactId',v_artifact->'artifactId',
      'manifestSha256',v_artifact->'manifestSha256','manifestByteSize',v_artifact->'manifestByteSize');
    select a.* into v_stored from private.final_result_query_artifacts a
      join private.final_result_query_seals s on s.artifact_id=a.id and s.target_hash=v_target
      where a.id=(v_artifact->>'artifactId')::uuid;
    if not found or v_stored.artifact_ref<>v_expected_ref or v_stored.input_hash<>v_candidate->>'inputHash'
      or to_jsonb(v_stored.result_count) is distinct from v_artifact->'resultCount' then
      raise exception using errcode='22023',message='Final Result Candidate artifact is not sealed for this input and target';
    end if;
    v_results:=v_results+v_stored.result_count;
  end loop;
  if v_results>2000000 or (select count(distinct value->>'artifactId') from jsonb_array_elements(v_candidate->'queryArtifacts'))
    <>jsonb_array_length(v_candidate->'queryArtifacts') then
    raise exception using errcode='22023',message='Duplicate or oversized final Result Candidate artifact set';
  end if;
  for v_file in select value from jsonb_array_elements(v_candidate->'packages') loop
    if jsonb_typeof(v_file) is distinct from 'object'
      or coalesce(v_file->>'format','') not in ('tidas','ilcd')
      or jsonb_typeof(v_file->'sha256') is distinct from 'string'
      or coalesce(v_file->>'sha256','') !~ '^[0-9a-f]{64}$'
      or private.final_result_query_uint(v_file->'byteSize',34359738368)=0 then
      raise exception using errcode='22023',message='Invalid final Result Candidate package';
    end if;
    if (select count(*) from jsonb_object_keys(v_file))<>5
      or jsonb_typeof(v_file->'path') is distinct from 'string'
      or coalesce(length(v_file->>'path'),0) not between 1 and 512
      or private.final_result_query_uint(v_file->'memberCount',2000000)=0 then
      raise exception using errcode='22023',message='Invalid final Result Candidate package';
    end if;
  end loop;
  select array_agg(value->>'format' order by (value->>'format') collate "C") into v_formats from jsonb_array_elements(v_candidate->'packages');
  if v_formats<>array['ilcd','tidas'] then
    raise exception using errcode='22023',message='Final Result Candidate requires the exact Result-only ZIP pair';
  end if;
  select jsonb_agg(file order by (file->>'name') collate "C") into v_files from (
    select jsonb_build_object('name','result.'||(value->>'format')||'.zip','sha256',value->'sha256','byteSize',value->'byteSize') file
      from jsonb_array_elements(v_candidate->'packages')
    union all select jsonb_build_object('name','release-candidate.json','sha256',v_hash,'byteSize',octet_length(p_candidate_text))
    union all select jsonb_build_object('name','publication-catalog.json','sha256',v_catalog_hash,'byteSize',octet_length(p_catalog_text))
  ) files;
  if p_receipt->'files' is distinct from v_files then
    raise exception using errcode='22023',message='Final Result Candidate package readback mismatch';
  end if;
  if v_old.candidate_hash is null then
    insert into private.final_result_candidates(candidate_hash,input_hash,manifest,manifest_byte_size,catalog_hash,catalog_byte_size,member_count,result_count)
      values(v_hash,v_candidate->>'inputHash',v_candidate,octet_length(p_candidate_text),v_catalog_hash,octet_length(p_catalog_text),v_count,v_results);
    insert into private.final_result_candidate_artifacts
      select v_hash,(value->>'artifactId')::uuid from jsonb_array_elements(v_candidate->'queryArtifacts');
    for v_member in select value from jsonb_array_elements(v_catalog->'datasets') loop
      if jsonb_typeof(v_member) is distinct from 'object'
        or coalesce(v_member->>'datasetType','') not in ('process','flow','flowproperty','unitgroup','lciamethod','contact','source')
        or coalesce(v_member->>'uuid','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        or coalesce(v_member->>'version','') !~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$'
        or coalesce(v_member->>'canonicalContentHash','') !~ '^[0-9a-f]{64}$'
        or jsonb_typeof(v_member->'canonicalContentHash') is distinct from 'string'
        or jsonb_typeof(v_member->'references') is distinct from 'array'
        or v_member->'components' is distinct from '["result"]'::jsonb
        or coalesce(length(v_member->>'role'),0) not between 1 and 64
        or ((v_member->>'datasetType'='process') is distinct from (v_member->>'role'='result_process'))
        or v_member->>'key' is distinct from (v_member->>'datasetType')||':'||(v_member->>'uuid')||'@'||(v_member->>'version') then
        raise exception using errcode='22023',message='Invalid final Result Candidate member';
      end if;
      if (select count(*) from jsonb_object_keys(v_member))<>10
        or jsonb_typeof(v_member->'sha256') is distinct from 'string'
        or coalesce(v_member->>'sha256','') !~ '^[0-9a-f]{64}$'
        or jsonb_typeof(v_member->'path') is distinct from 'string'
        or coalesce(length(v_member->>'path'),0) not between 1 and 512 then
        raise exception using errcode='22023',message='Invalid final Result Candidate member';
      end if;
      insert into private.final_result_candidate_members values(v_hash,v_member->>'datasetType',(v_member->>'uuid')::uuid,
        v_member->>'version',v_member->>'key',v_member->>'role',v_member->>'canonicalContentHash');
    end loop;
    select array_agg(dataset_key order by dataset_key collate "C"),
      array_agg(dataset_key order by dataset_key collate "C") filter(where dataset_kind='process')
      into v_actual_keys,v_actual_roots from private.final_result_candidate_members where candidate_hash=v_hash;
    select array_agg(value order by value collate "C") into v_keys from jsonb_array_elements_text(v_catalog#>'{components,result,datasets}');
    select array_agg(value order by value collate "C") into v_roots from jsonb_array_elements_text(v_catalog#>'{components,result,roots}');
    if v_keys is distinct from v_actual_keys or v_roots is distinct from v_actual_roots or coalesce(cardinality(v_actual_roots),0)<>v_results then
      raise exception using errcode='22023',message='Final Result Candidate root/closure coverage mismatch';
    end if;
    if (select count(*) from private.final_result_candidate_members m
      join private.final_result_candidate_artifacts a on a.candidate_hash=m.candidate_hash
      join private.final_result_query_rows r on r.artifact_id=a.artifact_id and r.result_id=m.dataset_id and r.result_version=m.dataset_version
      where m.candidate_hash=v_hash and m.dataset_kind='process'
        and r.canonical_content_hash=m.canonical_content_hash)<>v_results
      or (select count(distinct (r.result_id,r.result_version)) from private.final_result_candidate_artifacts a
        join private.final_result_query_rows r on r.artifact_id=a.artifact_id where a.candidate_hash=v_hash)<>v_results then
      raise exception using errcode='22023',message='Final Result Candidate has mismatched or duplicated artifact Results';
    end if;
    for v_member in select value from jsonb_array_elements(v_catalog->'datasets') loop
      if (select count(distinct value) from jsonb_array_elements(v_member->'references'))<>jsonb_array_length(v_member->'references') then
        raise exception using errcode='22023',message='Duplicate final Result Candidate closure reference';
      end if;
      for v_reference in select value from jsonb_array_elements(v_member->'references') loop
        if jsonb_typeof(v_reference) is distinct from 'string' or not exists(
          select 1 from private.final_result_candidate_members where candidate_hash=v_hash and dataset_key=v_reference#>>'{}') then
          raise exception using errcode='22023',message='Final Result Candidate closure reference is absent';
        end if;
      end loop;
    end loop;
    -- The package scope is the actual forward closure, not just an asserted
    -- list that could smuggle unrelated documents into an authorized ZIP.
    if (with recursive edges as materialized (
      select member->>'key' as source,reference#>>'{}' as target
      from jsonb_array_elements(v_catalog->'datasets') member
      cross join lateral jsonb_array_elements(member->'references') reference
    ), reachable(key) as (
      select unnest(v_actual_roots)
      union select e.target from reachable r join edges e on e.source=r.key
    ) select count(*) from reachable)<>v_count then
      raise exception using errcode='22023',message='Final Result Candidate contains unreachable package members';
    end if;
  elsif v_old.catalog_hash<>v_catalog_hash then
    raise exception using errcode='23505',message='Final Result Candidate catalog identity conflict';
  end if;
  insert into private.final_result_candidate_storage(candidate_hash,target_hash,readback_id,receipt,verified_at)
    values(v_hash,v_target,(p_receipt->>'readbackId')::uuid,p_receipt,v_time);
  return jsonb_build_object('ok',true,'data',jsonb_build_object('candidateHash',v_hash,'targetHash',v_target,
    'memberCount',v_count,'resultCount',v_results,'readbackId',p_receipt->>'readbackId','publicationAuthorized',false));
end;
$$;

create or replace function api.qry_final_result_release_probe_v2(p_release_run_id uuid,p_publish_plan_hash text,p_runtime_revision uuid,
  p_result_id uuid,p_result_version text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_context jsonb:=private.final_result_release_probe_context(p_release_run_id,p_publish_plan_hash); v_data jsonb;
begin
  if not coalesce((v_context->>'ok')::boolean,false) then return v_context; end if;
  if p_runtime_revision::text is distinct from v_context#>>'{data,runtimeRevision}' then
    return private.lca_release_error('runtime_revision_conflict',409,'Exact admitted runtime revision is required');
  end if;
  if p_result_id is null or coalesce(p_result_version,'') !~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$' then
    raise exception using errcode='22023',message='Exact final Result probe identity is required';
  end if;
  select jsonb_build_object('artifact',a.artifact_ref,'result',jsonb_build_object('uuid',m.result_id,'version',m.result_version),
    'contentHash',q.content_hash,'lciAvailable',true,'lciaAvailable',a.impact_count>0) into v_data
    from private.final_result_release_members m join private.final_result_query_artifacts a on a.id=m.artifact_id
    join private.final_result_query_rows q on q.artifact_id=m.artifact_id and q.row_ordinal=m.row_ordinal
      and q.result_id=m.result_id and q.result_version=m.result_version
    where m.release_run_id=p_release_run_id and m.result_id=p_result_id and m.result_version=p_result_version;
  if v_data is null then return private.lca_release_error('final_result_probe_not_available',404,'Result is absent from the sealed publication selection'); end if;
  return jsonb_build_object('ok',true,'data',(v_context->'data')||v_data);
end;
$$;

create or replace function api.svc_final_result_readiness_artifacts_v2(p_verification_id uuid,p_proofs jsonb)
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

create or replace function api.cmd_final_result_release_activate_v2(p_release_run_id uuid,p_publish_plan_hash text,p_approval_id uuid,
 p_approval_hash text,p_verification_id uuid,p_idempotency_key text,p_credential_fingerprint text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_auth jsonb:=api.assert_lca_release_manager(); v_run private.lca_release_runs%rowtype;
 v_plan private.final_result_release_plans%rowtype; v_approval private.lca_release_approvals%rowtype;
 v_old private.lca_release_publications%rowtype; v_publication private.lca_release_publications%rowtype; v_previous uuid;
 v_ready jsonb; v_now timestamptz:=clock_timestamp();
begin
 if not coalesce((v_auth->>'ok')::boolean,false) then return v_auth; end if;
 if p_release_run_id is null or p_approval_id is null or p_verification_id is null
   or coalesce(p_publish_plan_hash,'') !~ '^[0-9a-f]{64}$' or coalesce(p_approval_hash,'') !~ '^[0-9a-f]{64}$'
   or coalesce(p_credential_fingerprint,'') !~ '^[0-9a-f]{64}$' or coalesce(length(p_idempotency_key),0) not between 1 and 128
   or btrim(p_idempotency_key)<>p_idempotency_key then raise exception using errcode='22023',message='Exact final Result activation arguments are required'; end if;
 select * into v_run from private.lca_release_runs where id=p_release_run_id for update;
 if not found or v_run.publication_format<>'final-result-pair.v2' or v_run.publish_plan_hash is distinct from p_publish_plan_hash then
   return private.lca_release_error('final_result_plan_not_found',404,'Exact final Result plan is required'); end if;
 select * into v_old from private.lca_release_publications where release_run_id=v_run.id
   or (executed_by=auth.uid() and idempotency_key=p_idempotency_key) order by (release_run_id=v_run.id) desc limit 1;
 if found then
   if v_old.release_run_id<>v_run.id or v_old.executed_by<>auth.uid() or v_old.approval_id<>p_approval_id or v_old.approval_hash<>p_approval_hash
     or v_old.idempotency_key<>p_idempotency_key or v_old.credential_fingerprint<>p_credential_fingerprint
     or not exists(select 1 from private.final_result_publication_bindings where publication_id=v_old.id and verification_id=p_verification_id) then
     return private.lca_release_error('publish_idempotency_conflict',409,'Publication identity already binds another execution'); end if;
   return jsonb_build_object('ok',true,'data',jsonb_build_object('publicationId',v_old.id,'releaseRunId',v_run.id,'releaseVersion',v_run.release_version,
     'status',v_old.status,'isCurrent',v_old.is_current,'publishedAt',v_old.published_at,'reused',true));
 end if;
 if v_run.status<>'approved' then return private.lca_release_error('release_not_approved',409,'Exact active approval is required'); end if;
 select * into v_approval from private.lca_release_approvals where id=p_approval_id and release_run_id=v_run.id for update;
 if not found or v_approval.status<>'approved' or v_approval.approval_hash<>p_approval_hash or v_approval.publish_plan_hash<>p_publish_plan_hash
   or v_approval.expires_at<=v_now or v_approval.audit_correlation->>'schemaVersion' is distinct from 'tiangong.final-result-approval.v2' then
   return private.lca_release_error('approval_invalid',409,'Exact unexpired final Result approval is required'); end if;
 perform 1 from private.final_result_query_runtime_head where singleton for share;
 perform 1 from private.roles where user_id in (auth.uid(),v_approval.approved_by) and team_id='00000000-0000-0000-0000-000000000000'
   and role='data_product_manager' order by user_id for share;
 if not private.lca_release_is_manager() then return private.lca_release_error('not_data_product_manager',403,'Live execution authority is required'); end if;
 -- Serialize with legacy publish/unpublish too: the global current pointer has
 -- one authority. A new readiness sample may refresh the same approved context.
 lock table private.lca_release_publications in exclusive mode;
 v_now:=clock_timestamp();
 if v_approval.expires_at<=v_now then return private.lca_release_error('approval_invalid',409,'Approval expired while waiting to activate'); end if;
 v_ready:=private.final_result_fresh_readiness(p_verification_id,v_run.id,p_publish_plan_hash,v_approval.approved_by);
 if (v_approval.audit_correlation-array['schemaVersion','verificationId','expectedApprovalId']) is distinct from jsonb_build_object(
   'candidateHash',v_ready->>'candidateHash','targetHash',v_ready->>'targetHash','selectionHash',v_ready->>'selectionHash',
   'runtimeRevision',v_ready->>'runtimeRevision','readerSha256',v_ready->>'readerSha256','permissionHash',v_ready->>'permissionHash') then
   return private.lca_release_error('approval_context_changed',409,'Fresh readiness must match the approved context'); end if;
 select * into strict v_plan from private.final_result_release_plans where release_run_id=v_run.id;
 select id into v_previous from private.lca_release_publications where publication_series_key='global' and publication_channel='public'
   and visibility_scope='public' and is_current and status='current' for update;
 if v_previous is distinct from v_plan.expected_current_publication_id then return private.lca_release_error('expected_current_conflict',409,'Current publication changed'); end if;
 if v_plan.rollback_of_publication_id is not null and not exists(select 1 from private.lca_release_publications p
   join private.final_result_release_plans old_plan on old_plan.release_run_id=p.release_run_id
   join private.lca_release_runs old_run on old_run.id=p.release_run_id
   where p.id=v_plan.rollback_of_publication_id and not p.is_current and p.status in ('superseded','unpublished')
     and old_plan.candidate_hash=v_plan.candidate_hash and old_run.selection_manifest_hash=v_run.selection_manifest_hash) then
   return private.lca_release_error('rollback_scope_mismatch',409,'Rollback must retain the exact historical Candidate and selection'); end if;
 if exists(select 1 from private.final_result_release_members m left join private.final_result_query_rows q
   on q.artifact_id=m.artifact_id and q.row_ordinal=m.row_ordinal and q.result_id=m.result_id and q.result_version=m.result_version
   where m.release_run_id=v_run.id and q.result_id is null) then
   raise exception using errcode='55000',message='Final Result publication content identity changed'; end if;
 if v_previous is not null then update private.lca_release_publications set is_current=false,status='superseded',superseded_at=v_now where id=v_previous; end if;
 insert into private.lca_release_publications(release_run_id,release_version,approval_id,approval_hash,publish_plan_hash,release_manifest_hash,
   artifact_set_hash,approved_by,executed_by,credential_fingerprint,idempotency_key,published_at,reason)
   values(v_run.id,v_run.release_version,v_approval.id,v_approval.approval_hash,p_publish_plan_hash,v_run.release_manifest_hash,v_run.artifact_set_hash,
     v_approval.approved_by,auth.uid(),p_credential_fingerprint,p_idempotency_key,v_now,v_run.publish_plan->>'reason') returning * into v_publication;
 insert into private.final_result_publication_bindings(publication_id,verification_id,previous_publication_id,rollback_of_publication_id)
   values(v_publication.id,p_verification_id,v_previous,v_plan.rollback_of_publication_id);
 if v_previous is not null then update private.lca_release_publications set superseded_by=v_publication.id where id=v_previous; end if;
 update private.lca_release_approvals set status='consumed',consumed_by=auth.uid(),consumed_at=v_now where id=v_approval.id;
 update private.lca_release_runs set status='published',published_at=v_now where id=v_run.id;
 insert into private.command_audit_log(command,actor_user_id,target_table,target_id,target_version,payload)
   values('cmd_final_result_release_activate_v2',auth.uid(),'lca_release_publications',v_publication.id,v_run.release_version,
     jsonb_build_object('releaseRunId',v_run.id,'publishPlanHash',p_publish_plan_hash,'approvalId',v_approval.id,'verificationId',p_verification_id,
       'previousPublicationId',v_previous,'rollbackOfPublicationId',v_plan.rollback_of_publication_id));
 return jsonb_build_object('ok',true,'data',jsonb_build_object('publicationId',v_publication.id,'releaseRunId',v_run.id,'releaseVersion',v_run.release_version,
   'status','current','isCurrent',true,'publishedAt',v_now,'reused',false));
exception when unique_violation then
 return private.lca_release_error('publication_conflict',409,'Release version or execution identity already has a publication');
end;
$$;

create or replace function api.qry_final_result_query_v2(p_result_id uuid,p_result_version text,p_publication_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_data jsonb; v_target text; v_runtime private.final_result_query_runtime_revisions%rowtype;
begin
 if auth.uid() is null then return private.lca_release_error('auth_required',401,'Authentication required'); end if;
 if p_result_id is null or coalesce(p_result_version,'') !~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$' then
   raise exception using errcode='22023',message='Exact final Result identity is required'; end if;
 select jsonb_build_object('publicationId',p.id,'releaseVersion',p.release_version,'scope',jsonb_build_object('kind','publication','publicationId',p.id),
   'artifact',a.artifact_ref,'result',jsonb_build_object('uuid',m.result_id,'version',m.result_version),'relationKind',q.relation_kind,
   'lciAvailable',true,'lciaAvailable',a.impact_count>0),plan.target_hash into v_data,v_target
 from private.lca_release_publications p join private.final_result_publication_bindings binding on binding.publication_id=p.id
 join private.lca_release_runs r on r.id=p.release_run_id and r.publication_format='final-result-pair.v2' and r.status in ('published','readback_verified')
 join private.final_result_release_plans plan on plan.release_run_id=r.id
 join private.final_result_release_members m on m.release_run_id=r.id and m.result_id=p_result_id and m.result_version=p_result_version
 join private.final_result_query_artifacts a on a.id=m.artifact_id
 join private.final_result_query_rows q on q.artifact_id=m.artifact_id and q.row_ordinal=m.row_ordinal and q.result_id=m.result_id and q.result_version=m.result_version
 where p.publication_series_key='global' and p.publication_channel='public' and p.visibility_scope='public' and p.is_current and p.status='current'
   and (p_publication_id is null or p.id=p_publication_id);
 if v_data is null then return private.lca_release_error('published_result_not_available',404,'Exact Result is not in the current publication'); end if;
 select rev.* into v_runtime from private.final_result_query_runtime_head h join private.final_result_query_runtime_revisions rev on rev.id=h.revision_id where h.singleton;
 if not found or not v_runtime.enabled or v_runtime.target_hash<>v_target then
   return private.lca_release_error('result_query_runtime_unavailable',503,'Published Result reader is unavailable'); end if;
 return jsonb_build_object('ok',true,'data',v_data||jsonb_build_object('runtimeRevision',v_runtime.id,'readerSha256',v_runtime.reader_sha256));
end;
$$;

commit;
