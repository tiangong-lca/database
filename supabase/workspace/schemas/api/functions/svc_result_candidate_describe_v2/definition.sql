CREATE OR REPLACE FUNCTION "api"."svc_result_candidate_describe_v2"("p_candidate_hash" "text", "p_target_hash" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare v_candidate private.final_result_candidates%rowtype; v_receipt jsonb;
begin
  if coalesce(p_candidate_hash,'') !~ '^[0-9a-f]{64}$' or coalesce(p_target_hash,'') !~ '^[0-9a-f]{64}$' then
    raise exception using errcode='22023',message='Invalid final Result Candidate lookup';
  end if;
  select * into v_candidate from private.final_result_candidates where candidate_hash=p_candidate_hash;
  if not found then return jsonb_build_object('ok',true,'data',null); end if;
  select receipt into v_receipt from private.final_result_candidate_storage where candidate_hash=p_candidate_hash and target_hash=p_target_hash;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('candidateHash',p_candidate_hash,'targetHash',p_target_hash,
    'inputHash',v_candidate.input_hash,'memberCount',v_candidate.member_count,'resultCount',v_candidate.result_count,
    'readbackReceipt',v_receipt,'publicationAuthorized',false));
end;
$_$;

ALTER FUNCTION "api"."svc_result_candidate_describe_v2"("p_candidate_hash" "text", "p_target_hash" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_result_candidate_describe_v2"("p_candidate_hash" "text", "p_target_hash" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_result_candidate_describe_v2"("p_candidate_hash" "text", "p_target_hash" "text") TO "service_role";
