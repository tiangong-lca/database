CREATE OR REPLACE FUNCTION "api"."qry_final_result_release_approval_v2"("p_release_run_id" "uuid", "p_approval_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_auth jsonb:=api.assert_lca_release_manager(); v_data jsonb;
begin
 if not coalesce((v_auth->>'ok')::boolean,false) then return v_auth; end if;
 if p_release_run_id is null or p_approval_id is null then raise exception using errcode='22023',message='Exact final Result run and approval identities are required'; end if;
 select jsonb_build_object('approvalId',a.id,'releaseRunId',a.release_run_id,'publishPlanHash',a.publish_plan_hash,
   'approvalHash',a.approval_hash,'approvedBy',a.approved_by,'approvedAt',a.approved_at,'expiresAt',a.expires_at,
   'status',a.status,'reason',a.reason,'context',a.audit_correlation,'consumedAt',a.consumed_at,'consumedBy',a.consumed_by,'revokedAt',a.revoked_at)
   into v_data from private.lca_release_approvals a join private.lca_release_runs r on r.id=a.release_run_id
   where a.id=p_approval_id and a.release_run_id=p_release_run_id and r.publication_format='final-result-pair.v2'
     and a.audit_correlation->>'schemaVersion'='tiangong.final-result-approval.v2';
 return jsonb_build_object('ok',true,'data',v_data);
end;
$$;

ALTER FUNCTION "api"."qry_final_result_release_approval_v2"("p_release_run_id" "uuid", "p_approval_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."qry_final_result_release_approval_v2"("p_release_run_id" "uuid", "p_approval_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."qry_final_result_release_approval_v2"("p_release_run_id" "uuid", "p_approval_id" "uuid") TO "authenticated";
