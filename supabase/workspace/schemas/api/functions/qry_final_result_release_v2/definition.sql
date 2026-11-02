CREATE OR REPLACE FUNCTION "api"."qry_final_result_release_v2"("p_release_run_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_auth jsonb:=api.assert_lca_release_manager(); v_data jsonb;
begin
 if not coalesce((v_auth->>'ok')::boolean,false) then return v_auth; end if;
 if p_release_run_id is null then raise exception using errcode='22023',message='Exact final Result run identity is required'; end if;
 select jsonb_build_object('releaseRunId',r.id,'releaseVersion',r.release_version,'status',r.status,'publishPlanHash',r.publish_plan_hash,
   'candidateHash',p.candidate_hash,'targetHash',p.target_hash,'selectionHash',r.selection_manifest_hash,'selectionCount',p.selection_count,
   'registeredResultCount',(select count(*) from private.final_result_release_members where release_run_id=r.id),
   'selectionSealed',exists(select 1 from private.final_result_release_selection_seals where release_run_id=r.id),
   'expectedCurrentPublicationId',p.expected_current_publication_id,'rollbackOfPublicationId',p.rollback_of_publication_id,
   'activeApproval',(select jsonb_build_object('approvalId',a.id,'approvalHash',a.approval_hash,'approvedBy',a.approved_by,'expiresAt',a.expires_at,
     'verificationId',a.audit_correlation->>'verificationId') from private.lca_release_approvals a where a.release_run_id=r.id and a.status='approved'),
   'publication',(select jsonb_build_object('publicationId',pub.id,'status',pub.status,'isCurrent',pub.is_current,'publishedAt',pub.published_at,
     'approvalId',pub.approval_id,'approvalHash',pub.approval_hash,'approvedBy',pub.approved_by,'executedBy',pub.executed_by,
     'idempotencyKey',pub.idempotency_key,'credentialFingerprint',pub.credential_fingerprint,'verificationId',binding.verification_id,
     'previousPublicationId',binding.previous_publication_id,'rollbackOfPublicationId',binding.rollback_of_publication_id)
     from private.lca_release_publications pub join private.final_result_publication_bindings binding on binding.publication_id=pub.id where pub.release_run_id=r.id),
   'readbackReceipt',r.readback_receipt,'publicationAuthorized',false) into v_data
 from private.lca_release_runs r join private.final_result_release_plans p on p.release_run_id=r.id
 where r.id=p_release_run_id and r.publication_format='final-result-pair.v2';
 -- publicationAuthorized=false means this read does not grant authority. The
 -- active approval can be expired or context-stale; execution must revalidate it.
 return jsonb_build_object('ok',true,'data',v_data);
end;
$$;

ALTER FUNCTION "api"."qry_final_result_release_v2"("p_release_run_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."qry_final_result_release_v2"("p_release_run_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."qry_final_result_release_v2"("p_release_run_id" "uuid") TO "authenticated";
