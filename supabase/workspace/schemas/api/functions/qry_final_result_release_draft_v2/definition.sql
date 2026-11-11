CREATE OR REPLACE FUNCTION "api"."qry_final_result_release_draft_v2"("p_release_run_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_auth jsonb:=api.assert_lca_release_manager(); v_data jsonb;
begin
 if not coalesce((v_auth->>'ok')::boolean,false) then return v_auth; end if;
 select jsonb_build_object('releaseRunId',r.id,'releaseVersion',r.release_version,'publishPlanHash',r.publish_plan_hash,'status',r.status,
   'replacesReleaseRunId',old.id,'replacesPublishPlanHash',old.publish_plan_hash,'replacedByReleaseRunId',r.replaced_by_run_id)
 into v_data from private.lca_release_runs r left join private.lca_release_runs old on old.replaced_by_run_id=r.id
 where r.id=p_release_run_id and r.publication_format='final-result-pair.v2';
 return jsonb_build_object('ok',true,'data',v_data);
end;
$$;

ALTER FUNCTION "api"."qry_final_result_release_draft_v2"("p_release_run_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."qry_final_result_release_draft_v2"("p_release_run_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."qry_final_result_release_draft_v2"("p_release_run_id" "uuid") TO "authenticated";
