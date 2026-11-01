CREATE OR REPLACE FUNCTION "api"."svc_result_query_runtime_configure_v2"("p_revision_id" "uuid", "p_expected_revision_id" "uuid", "p_target_hash" "text", "p_reader_sha256" "text", "p_enabled" boolean, "p_reason" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare v_head uuid; v_old private.final_result_query_runtime_revisions%rowtype;
begin
  if p_revision_id is null or coalesce(p_target_hash,'') !~ '^[0-9a-f]{64}$'
    or coalesce(p_reader_sha256,'') !~ '^[0-9a-f]{64}$' or p_enabled is null
    or coalesce(length(p_reason),0) not between 1 and 2000 or length(btrim(p_reason))=0 then
    raise exception using errcode='22023',message='Invalid final Result runtime admission';
  end if;
  perform pg_advisory_xact_lock(882,1);
  select revision_id into v_head from private.final_result_query_runtime_head where singleton for update;
  select * into v_old from private.final_result_query_runtime_revisions where id=p_revision_id;
  if found then
    if v_old.previous_revision_id is distinct from p_expected_revision_id or v_old.target_hash<>p_target_hash
      or v_old.reader_sha256<>p_reader_sha256 or v_old.enabled<>p_enabled or v_old.reason<>p_reason then
      raise exception using errcode='23505',message='Final Result runtime revision identity conflict';
    end if;
    return jsonb_build_object('ok',true,'data',jsonb_build_object('runtimeRevision',v_old.id,'isCurrent',v_head=v_old.id,
      'targetHash',v_old.target_hash,'readerSha256',v_old.reader_sha256,'enabled',v_old.enabled,'publicationAuthorized',false));
  end if;
  if v_head is distinct from p_expected_revision_id then
    return private.lca_release_error('runtime_revision_conflict',409,'Runtime admission changed; read the exact current revision');
  end if;
  insert into private.final_result_query_runtime_revisions(id,previous_revision_id,target_hash,reader_sha256,enabled,reason)
    values(p_revision_id,v_head,p_target_hash,p_reader_sha256,p_enabled,p_reason);
  insert into private.final_result_query_runtime_head(singleton,revision_id) values(true,p_revision_id)
    on conflict(singleton) do update set revision_id=excluded.revision_id;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('runtimeRevision',p_revision_id,'isCurrent',true,
    'targetHash',p_target_hash,'readerSha256',p_reader_sha256,'enabled',p_enabled,'publicationAuthorized',false));
end;
$_$;

ALTER FUNCTION "api"."svc_result_query_runtime_configure_v2"("p_revision_id" "uuid", "p_expected_revision_id" "uuid", "p_target_hash" "text", "p_reader_sha256" "text", "p_enabled" boolean, "p_reason" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_result_query_runtime_configure_v2"("p_revision_id" "uuid", "p_expected_revision_id" "uuid", "p_target_hash" "text", "p_reader_sha256" "text", "p_enabled" boolean, "p_reason" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_result_query_runtime_configure_v2"("p_revision_id" "uuid", "p_expected_revision_id" "uuid", "p_target_hash" "text", "p_reader_sha256" "text", "p_enabled" boolean, "p_reason" "text") TO "service_role";
