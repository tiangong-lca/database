CREATE OR REPLACE FUNCTION "private"."final_result_release_probe_context"("p_release_run_id" "uuid", "p_publish_plan_hash" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_auth jsonb:=api.assert_lca_release_manager(); v_run private.lca_release_runs%rowtype;
  v_plan private.final_result_release_plans%rowtype; v_runtime private.final_result_query_runtime_revisions%rowtype;
  v_current uuid; v_permission text;
begin
  if not coalesce((v_auth->>'ok')::boolean,false) then return v_auth; end if;
  select * into v_run from private.lca_release_runs where id=p_release_run_id;
  if not found or v_run.publication_format<>'final-result-pair.v2' or v_run.publish_plan_hash is distinct from p_publish_plan_hash
    or v_run.status not in ('prepared','ready_for_approval','approved') then
    return private.lca_release_error('final_result_probe_not_available',404,'Exact unpublished final Result plan is required');
  end if;
  select * into strict v_plan from private.final_result_release_plans where release_run_id=v_run.id;
  if not exists(select 1 from private.final_result_release_selection_seals where release_run_id=v_run.id and selection_hash=v_run.selection_manifest_hash) then
    return private.lca_release_error('final_result_selection_unsealed',409,'Complete selected membership must be sealed first');
  end if;
  select r.* into v_runtime from private.final_result_query_runtime_head h
    join private.final_result_query_runtime_revisions r on r.id=h.revision_id where h.singleton;
  if not found or not v_runtime.enabled or v_runtime.target_hash<>v_plan.target_hash then
    return private.lca_release_error('final_result_runtime_unavailable',409,'An enabled exact storage target and reader revision are required');
  end if;
  select id into v_current from private.lca_release_publications where publication_series_key='global'
    and publication_channel='public' and visibility_scope='public' and is_current and status='current';
  if v_current is distinct from v_plan.expected_current_publication_id then
    return private.lca_release_error('expected_current_conflict',409,'Current publication changed; prepare a new exact plan');
  end if;
  select encode(extensions.digest(convert_to('tiangong.final-result-manager-precondition.v1'||E'\n'||r.user_id::text||E'\n'||
    coalesce(extract(epoch from r.created_at)::text,'')||E'\n'||coalesce(extract(epoch from r.modified_at)::text,'')||E'\n','UTF8'),'sha256'),'hex')
    into v_permission from private.roles r where r.user_id=auth.uid()
      and r.team_id='00000000-0000-0000-0000-000000000000' and r.role='data_product_manager';
  if v_permission is null then return private.lca_release_error('not_data_product_manager',403,'Live manager role is required'); end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('releaseRunId',v_run.id,'publishPlanHash',v_run.publish_plan_hash,
    'candidateHash',v_plan.candidate_hash,'targetHash',v_plan.target_hash,'selectionHash',v_run.selection_manifest_hash,
    'selectionCount',v_plan.selection_count,'runtimeRevision',v_runtime.id,'readerSha256',v_runtime.reader_sha256,
    'actorId',auth.uid(),'permissionHash',v_permission,
    'scope',jsonb_build_object('kind','readiness','releaseRunId',v_run.id,'selectionHash',v_run.selection_manifest_hash),
    'publicationAuthorized',false));
end;
$$;

ALTER FUNCTION "private"."final_result_release_probe_context"("p_release_run_id" "uuid", "p_publish_plan_hash" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."final_result_release_probe_context"("p_release_run_id" "uuid", "p_publish_plan_hash" "text") FROM PUBLIC;
