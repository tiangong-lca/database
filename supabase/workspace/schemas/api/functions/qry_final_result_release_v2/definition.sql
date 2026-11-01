CREATE OR REPLACE FUNCTION "api"."qry_final_result_release_v2"("p_release_run_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_auth jsonb:=api.assert_lca_release_manager(); v_data jsonb;
begin
  if not coalesce((v_auth->>'ok')::boolean,false) then return v_auth; end if;
  select jsonb_build_object('releaseRunId',r.id,'releaseVersion',r.release_version,'status',r.status,'publishPlanHash',r.publish_plan_hash,
    'candidateHash',p.candidate_hash,'targetHash',p.target_hash,'selectionHash',r.selection_manifest_hash,'selectionCount',p.selection_count,
    'registeredResultCount',(select count(*) from private.final_result_release_members where release_run_id=r.id),
    'selectionSealed',exists(select 1 from private.final_result_release_selection_seals where release_run_id=r.id),
    'expectedCurrentPublicationId',p.expected_current_publication_id,'rollbackOfPublicationId',p.rollback_of_publication_id,
    'publicationAuthorized',false) into v_data
  from private.lca_release_runs r join private.final_result_release_plans p on p.release_run_id=r.id
  where r.id=p_release_run_id and r.publication_format='final-result-pair.v2';
  return jsonb_build_object('ok',true,'data',v_data);
end;
$$;

ALTER FUNCTION "api"."qry_final_result_release_v2"("p_release_run_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."qry_final_result_release_v2"("p_release_run_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."qry_final_result_release_v2"("p_release_run_id" "uuid") TO "authenticated";
