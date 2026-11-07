CREATE OR REPLACE FUNCTION "api"."qry_final_result_download_v2"("p_publication_id" "uuid", "p_format" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '20s'
    AS $$
declare v_candidate text; v_target text; v_file jsonb;
begin
 if auth.uid() is null then return private.lca_release_error('auth_required',401,'Authentication required'); end if;
 if p_publication_id is null or p_format is null or p_format not in ('tidas','ilcd') then
   raise exception using errcode='22023',message='Exact publication and supported archive format are required'; end if;
 select plan.candidate_hash,plan.target_hash into v_candidate,v_target from private.lca_release_publications p
 join private.final_result_publication_bindings b on b.publication_id=p.id
 join private.final_result_release_plans plan on plan.release_run_id=p.release_run_id
 where p.id=p_publication_id and p.is_current and p.status='current';
 if v_candidate is null or exists(select 1 from private.final_result_candidate_artifacts ca
   join private.final_result_query_rows q on q.artifact_id=ca.artifact_id where ca.candidate_hash=v_candidate
   and not exists(select 1 from private.lca_release_publications p join private.final_result_release_members m on m.release_run_id=p.release_run_id
     where p.id=p_publication_id and m.result_id=q.result_id and m.result_version=q.result_version))
   or not private.final_result_candidate_support_readable(v_candidate) then
   return private.lca_release_error('result_package_not_available',404,'No complete prebuilt archive is authorized for this actor'); end if;
 select f.value into v_file from private.final_result_candidate_storage s cross join lateral jsonb_array_elements(s.receipt->'files') f
   where s.candidate_hash=v_candidate and s.target_hash=v_target and f.value->>'name'='result.'||p_format||'.7z';
 if v_file is null then return private.lca_release_error('result_package_not_available',404,'No complete prebuilt archive is authorized for this actor'); end if;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('publicationId',p_publication_id,'candidateHash',v_candidate,'targetHash',v_target,'file',v_file));
end;
$$;

ALTER FUNCTION "api"."qry_final_result_download_v2"("p_publication_id" "uuid", "p_format" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."qry_final_result_download_v2"("p_publication_id" "uuid", "p_format" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."qry_final_result_download_v2"("p_publication_id" "uuid", "p_format" "text") TO "authenticated";
