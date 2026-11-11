CREATE OR REPLACE FUNCTION "private"."final_result_version_state"("p_release_version" "text") RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
 select jsonb_build_object('releaseVersion',p_release_version,'occupant',(
  select jsonb_build_object('releaseRunId',r.id,'publishPlanHash',r.publish_plan_hash,'format',r.publication_format,'status',r.status,
    'candidateHash',p.candidate_hash,'targetHash',p.target_hash,
    'replacesReleaseRunId',(select id from private.lca_release_runs old where old.replaced_by_run_id=r.id),
    'replaceable',r.publication_format='final-result-pair.v2' and r.status in ('prepared','ready_for_approval','failed')
      and not exists(select 1 from private.lca_release_approvals a where a.release_run_id=r.id)
      and not exists(select 1 from private.lca_release_publications pub where pub.release_run_id=r.id))
  from private.lca_release_runs r left join private.final_result_release_plans p on p.release_run_id=r.id
  where r.release_version=p_release_version and r.replaced_by_run_id is null));
$$;

ALTER FUNCTION "private"."final_result_version_state"("p_release_version" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."final_result_version_state"("p_release_version" "text") FROM PUBLIC;
