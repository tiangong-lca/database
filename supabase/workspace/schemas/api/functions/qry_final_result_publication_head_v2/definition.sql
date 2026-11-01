CREATE OR REPLACE FUNCTION "api"."qry_final_result_publication_head_v2"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_auth jsonb:=api.assert_lca_release_manager(); v_data jsonb;
begin
 if not coalesce((v_auth->>'ok')::boolean,false) then return v_auth; end if;
 select jsonb_build_object('publicationId',p.id,'releaseRunId',p.release_run_id,'releaseVersion',p.release_version,
   'format',r.publication_format,'candidateHash',plan.candidate_hash,'selectionHash',r.selection_manifest_hash,'targetHash',plan.target_hash)
   into v_data from private.lca_release_publications p join private.lca_release_runs r on r.id=p.release_run_id
   left join private.final_result_release_plans plan on plan.release_run_id=r.id
   where p.is_current and p.status='current' and p.publication_series_key='global' and p.publication_channel='public' and p.visibility_scope='public';
 return jsonb_build_object('ok',true,'data',v_data);
end;
$$;

ALTER FUNCTION "api"."qry_final_result_publication_head_v2"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."qry_final_result_publication_head_v2"() FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."qry_final_result_publication_head_v2"() TO "authenticated";
