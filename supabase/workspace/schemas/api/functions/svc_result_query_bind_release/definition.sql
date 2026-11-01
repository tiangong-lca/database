CREATE OR REPLACE FUNCTION "api"."svc_result_query_bind_release"("p_release_run_id" "uuid", "p_artifact_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_run private.lca_release_runs%rowtype;
  v_artifact private.result_query_artifacts%rowtype;
  v_previous uuid;
begin
  select * into v_run from private.lca_release_runs where id=p_release_run_id for update;
  if v_run.publication_format='final-result-pair.v2' then
    raise exception using errcode='22023',message='Final Result releases require the versioned query binding contract';
  end if;
  select * into v_artifact from private.result_query_artifacts where id=p_artifact_id for share;
  if v_run.id is null or v_artifact.id is null or v_artifact.status <> 'ready'
    or v_run.status not in ('ready_for_approval','approved','published','readback_verified')
    or v_run.calculation_bundle_hash is distinct from v_artifact.manifest#>>'{source,bundleContentHash}'
    or v_run.calculation_bundle_ref->>'calculationId' is distinct from v_artifact.manifest#>>'{source,calculationId}'
    or v_run.calculation_bundle_ref->>'manifestSha256' is distinct from v_artifact.manifest#>>'{source,manifestSha256}'
    or v_run.release_manifest_hash is null then
    raise exception using errcode='22023',message='Release/query Bundle binding mismatch';
  end if;
  if not exists(select 1 from private.lca_release_dataset_versions where release_run_id=v_run.id and dataset_role='unit_process')
    or exists(select 1 from private.lca_release_dataset_versions d where d.release_run_id=v_run.id and d.dataset_role='unit_process'
      and not exists(select 1 from private.result_query_sources s where s.artifact_id=p_artifact_id
        and s.process_id=d.source_process_uuid and s.process_version=d.source_process_version)) then
    raise exception using errcode='22023',message='Query artifact does not cover release roots';
  end if;
  select artifact_id into v_previous from private.result_query_release_bindings where release_run_id=p_release_run_id;
  if found and v_previous <> p_artifact_id then
    raise exception using errcode='22023',message='Release query binding is immutable';
  end if;
  insert into private.result_query_release_bindings(release_run_id,artifact_id)
    values(p_release_run_id,p_artifact_id) on conflict(release_run_id) do nothing;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('releaseRunId',p_release_run_id,'artifactId',p_artifact_id));
end;
$$;

ALTER FUNCTION "api"."svc_result_query_bind_release"("p_release_run_id" "uuid", "p_artifact_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_result_query_bind_release"("p_release_run_id" "uuid", "p_artifact_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_result_query_bind_release"("p_release_run_id" "uuid", "p_artifact_id" "uuid") TO "service_role";
