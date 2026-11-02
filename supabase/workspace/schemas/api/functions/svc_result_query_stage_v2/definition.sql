CREATE OR REPLACE FUNCTION "api"."svc_result_query_stage_v2"("p_artifact_ref" "jsonb", "p_manifest_text" "text", "p_rows" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
$_$;

ALTER FUNCTION "api"."svc_result_query_stage_v2"("p_artifact_ref" "jsonb", "p_manifest_text" "text", "p_rows" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_result_query_stage_v2"("p_artifact_ref" "jsonb", "p_manifest_text" "text", "p_rows" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_result_query_stage_v2"("p_artifact_ref" "jsonb", "p_manifest_text" "text", "p_rows" "jsonb") TO "service_role";
