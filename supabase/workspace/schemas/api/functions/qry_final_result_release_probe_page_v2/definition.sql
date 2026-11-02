CREATE OR REPLACE FUNCTION "api"."qry_final_result_release_probe_page_v2"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_runtime_revision" "uuid" DEFAULT NULL::"uuid", "p_after_artifact_id" "uuid" DEFAULT NULL::"uuid", "p_limit" integer DEFAULT 100) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_context jsonb:=private.final_result_release_probe_context(p_release_run_id,p_publish_plan_hash);
  v_ids uuid[]; v_id uuid; v_first text; v_last text; v_count bigint; v_ref jsonb; v_items jsonb:='[]'; v_probes jsonb;
begin
  if not coalesce((v_context->>'ok')::boolean,false) then return v_context; end if;
  if p_limit is null or p_limit not between 1 and 100 or (p_after_artifact_id is not null and p_runtime_revision is null) then
    raise exception using errcode='22023',message='Invalid bounded final Result probe page';
  end if;
  if p_runtime_revision is not null and p_runtime_revision::text is distinct from v_context#>>'{data,runtimeRevision}' then
    return private.lca_release_error('runtime_revision_conflict',409,'Runtime changed during verification; restart with the current revision');
  end if;
  select array_agg(artifact_id order by artifact_id) into v_ids from (
    select distinct artifact_id from private.final_result_release_members where release_run_id=p_release_run_id
      and (p_after_artifact_id is null or artifact_id>p_after_artifact_id) order by artifact_id limit p_limit+1
  ) ids;
  foreach v_id in array coalesce(v_ids[1:p_limit],array[]::uuid[]) loop
    select min((result_id::text||'@'||result_version) collate "C"),max((result_id::text||'@'||result_version) collate "C"),count(*)
      into v_first,v_last,v_count from private.final_result_release_members where release_run_id=p_release_run_id and artifact_id=v_id;
    select artifact_ref into strict v_ref from private.final_result_query_artifacts where id=v_id;
    v_probes:=jsonb_build_array(jsonb_build_object('uuid',split_part(v_first,'@',1),'version',split_part(v_first,'@',2)));
    if v_first<>v_last then v_probes:=v_probes||jsonb_build_array(jsonb_build_object('uuid',split_part(v_last,'@',1),'version',split_part(v_last,'@',2))); end if;
    v_items:=v_items||jsonb_build_array(jsonb_build_object('artifact',v_ref,'selectedResultCount',v_count,'probes',v_probes));
  end loop;
  return jsonb_build_object('ok',true,'data',(v_context->'data')||jsonb_build_object('artifacts',v_items,
    'nextArtifactCursor',case when cardinality(v_ids)>p_limit then v_ids[p_limit] else null end));
end;
$$;

ALTER FUNCTION "api"."qry_final_result_release_probe_page_v2"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_runtime_revision" "uuid", "p_after_artifact_id" "uuid", "p_limit" integer) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."qry_final_result_release_probe_page_v2"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_runtime_revision" "uuid", "p_after_artifact_id" "uuid", "p_limit" integer) FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."qry_final_result_release_probe_page_v2"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_runtime_revision" "uuid", "p_after_artifact_id" "uuid", "p_limit" integer) TO "authenticated";
