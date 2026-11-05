CREATE OR REPLACE FUNCTION "api"."svc_result_candidate_register_v2"("p_candidate_text" "text", "p_catalog_text" "text", "p_receipt" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
$_$;

ALTER FUNCTION "api"."svc_result_candidate_register_v2"("p_candidate_text" "text", "p_catalog_text" "text", "p_receipt" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_result_candidate_register_v2"("p_candidate_text" "text", "p_catalog_text" "text", "p_receipt" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_result_candidate_register_v2"("p_candidate_text" "text", "p_catalog_text" "text", "p_receipt" "jsonb") TO "service_role";
