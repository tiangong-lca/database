CREATE OR REPLACE FUNCTION "api"."svc_result_identity_register"("p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
$_$;

ALTER FUNCTION "api"."svc_result_identity_register"("p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_result_identity_register"("p_request" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_result_identity_register"("p_request" "jsonb") TO "service_role";
