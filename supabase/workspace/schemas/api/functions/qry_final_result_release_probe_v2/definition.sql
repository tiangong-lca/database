CREATE OR REPLACE FUNCTION "api"."qry_final_result_release_probe_v2"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_runtime_revision" "uuid", "p_result_id" "uuid", "p_result_version" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
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
$_$;

ALTER FUNCTION "api"."qry_final_result_release_probe_v2"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_runtime_revision" "uuid", "p_result_id" "uuid", "p_result_version" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."qry_final_result_release_probe_v2"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_runtime_revision" "uuid", "p_result_id" "uuid", "p_result_version" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."qry_final_result_release_probe_v2"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_runtime_revision" "uuid", "p_result_id" "uuid", "p_result_version" "text") TO "authenticated";
