CREATE OR REPLACE FUNCTION "api"."qry_final_result_download"("p_publication_id" "uuid", "p_format" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_candidate text;
  v_target text;
  v_file jsonb;
begin
  if auth.uid() is null then
    return private.lca_release_error('auth_required', 401, 'Authentication required');
  end if;
  if p_publication_id is null or p_format is null or p_format not in ('tidas', 'ilcd') then
    raise exception using errcode = '22023', message = 'Exact publication and supported archive format are required';
  end if;

  select plan.candidate_hash, plan.target_hash, file.value
    into v_candidate, v_target, v_file
  from private.lca_release_publications p
  join private.final_result_publication_bindings binding on binding.publication_id = p.id
  join private.final_result_release_plans plan on plan.release_run_id = p.release_run_id
  join private.final_result_release_selection_seals seal on seal.release_run_id = plan.release_run_id
  join private.final_result_candidates candidate on candidate.candidate_hash = plan.candidate_hash
    and candidate.result_count = plan.selection_count
  join private.final_result_candidate_storage storage on storage.candidate_hash = plan.candidate_hash
    and storage.target_hash = plan.target_hash
  cross join lateral jsonb_array_elements(storage.receipt->'files') file
  where p.id = p_publication_id and p.is_current and p.status = 'current'
    and file.value->>'name' = 'result.' || p_format || '.7z';

  if not found then
    return private.lca_release_error('result_package_not_available', 404, 'No complete prebuilt archive is available for this publication');
  end if;
  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'publicationId', p_publication_id, 'candidateHash', v_candidate,
    'targetHash', v_target, 'file', v_file));
end;
$$;

ALTER FUNCTION "api"."qry_final_result_download"("p_publication_id" "uuid", "p_format" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."qry_final_result_download"("p_publication_id" "uuid", "p_format" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."qry_final_result_download"("p_publication_id" "uuid", "p_format" "text") TO "authenticated";
