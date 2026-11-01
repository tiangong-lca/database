CREATE OR REPLACE FUNCTION "api"."svc_result_query_seal_v2"("p_artifact_id" "uuid", "p_receipt" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
$_$;

ALTER FUNCTION "api"."svc_result_query_seal_v2"("p_artifact_id" "uuid", "p_receipt" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_result_query_seal_v2"("p_artifact_id" "uuid", "p_receipt" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_result_query_seal_v2"("p_artifact_id" "uuid", "p_receipt" "jsonb") TO "service_role";
