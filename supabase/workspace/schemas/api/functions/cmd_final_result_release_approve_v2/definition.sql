CREATE OR REPLACE FUNCTION "api"."cmd_final_result_release_approve_v2"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_verification_id" "uuid", "p_approval_id" "uuid", "p_expected_approval_id" "uuid", "p_expires_at" timestamp with time zone, "p_reason" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare v_auth jsonb:=api.assert_lca_release_manager(); v_run private.lca_release_runs%rowtype;
 v_old private.lca_release_approvals%rowtype; v_active private.lca_release_approvals%rowtype;
 v_ready jsonb; v_context jsonb; v_hash text; v_now timestamptz:=clock_timestamp();
begin
 if not coalesce((v_auth->>'ok')::boolean,false) then return v_auth; end if;
 if p_release_run_id is null or p_verification_id is null or p_approval_id is null or coalesce(p_publish_plan_hash,'') !~ '^[0-9a-f]{64}$'
   or p_expires_at is null or not isfinite(p_expires_at) or coalesce(length(p_reason),0) not between 1 and 2000 or length(btrim(p_reason))=0 then
   raise exception using errcode='22023',message='Exact final Result approval arguments are required'; end if;
 select * into v_run from private.lca_release_runs where id=p_release_run_id for update;
 if not found or v_run.publication_format<>'final-result-pair.v2' or v_run.publish_plan_hash is distinct from p_publish_plan_hash then
   return private.lca_release_error('final_result_plan_not_found',404,'Exact final Result plan is required'); end if;
 select * into v_old from private.lca_release_approvals where id=p_approval_id;
 if found then
   if v_old.release_run_id<>v_run.id or v_old.publish_plan_hash<>p_publish_plan_hash or v_old.approved_by<>auth.uid()
     or v_old.expires_at<>p_expires_at or v_old.reason<>p_reason
     or v_old.audit_correlation->>'schemaVersion' is distinct from 'tiangong.final-result-approval.v2'
     or v_old.audit_correlation->>'verificationId' is distinct from p_verification_id::text
     or v_old.audit_correlation->>'expectedApprovalId' is distinct from p_expected_approval_id::text then
     return private.lca_release_error('approval_identity_conflict',409,'Approval identity already binds different evidence'); end if;
   return jsonb_build_object('ok',true,'data',jsonb_build_object('approvalId',v_old.id,'approvalHash',v_old.approval_hash,
     'status',v_old.status,'approvedBy',v_old.approved_by,'expiresAt',v_old.expires_at,'reused',true));
 end if;
 if v_run.status not in ('prepared','ready_for_approval','approved') or p_expires_at<=v_now or p_expires_at>v_now+interval '24 hours' then
   return private.lca_release_error('final_result_approval_not_available',409,'Unpublished plan and bounded future approval expiry are required'); end if;
 -- Keep the admitted revision and live actor grant stable through approval.
 perform 1 from private.final_result_query_runtime_head where singleton for share;
 perform 1 from private.roles where user_id=auth.uid() and team_id='00000000-0000-0000-0000-000000000000' and role='data_product_manager' for share;
 v_ready:=private.final_result_fresh_readiness(p_verification_id,v_run.id,p_publish_plan_hash,auth.uid());
 v_now:=clock_timestamp();
 if p_expires_at<=v_now or p_expires_at>v_now+interval '24 hours' then
   return private.lca_release_error('approval_expiry_invalid',409,'Approval expiry changed while waiting for its preconditions'); end if;
 select * into v_active from private.lca_release_approvals where release_run_id=v_run.id and status='approved' for update;
 if v_active.id is distinct from p_expected_approval_id then
   return private.lca_release_error('expected_approval_conflict',409,'Active approval changed; inspect and confirm the exact replacement'); end if;
 if v_active.id is not null then
   update private.lca_release_approvals set status=case when expires_at<=v_now then 'expired' else 'revoked' end,
     revoked_at=case when expires_at>v_now then v_now else revoked_at end where id=v_active.id;
 end if;
 v_context:=jsonb_build_object('schemaVersion','tiangong.final-result-approval.v2','verificationId',p_verification_id,
   'expectedApprovalId',p_expected_approval_id,'candidateHash',v_ready->>'candidateHash','targetHash',v_ready->>'targetHash',
   'selectionHash',v_ready->>'selectionHash','runtimeRevision',v_ready->>'runtimeRevision','readerSha256',v_ready->>'readerSha256',
   'permissionHash',v_ready->>'permissionHash');
 v_hash:=encode(extensions.digest(convert_to('tiangong.final-result-approval.jsonb.v2'||E'\n'||jsonb_build_object(
   'approvalId',p_approval_id,'releaseRunId',v_run.id,'publishPlanHash',p_publish_plan_hash,'approvedBy',auth.uid(),
   'expiresAt',p_expires_at,'reason',p_reason,'context',v_context)::text,'UTF8'),'sha256'),'hex');
 insert into private.lca_release_approvals(id,release_run_id,publish_plan_hash,approval_hash,approved_by,approved_at,expires_at,reason,audit_correlation)
   values(p_approval_id,v_run.id,p_publish_plan_hash,v_hash,auth.uid(),v_now,p_expires_at,p_reason,v_context);
 if v_run.status='prepared' then update private.lca_release_runs set status='ready_for_approval' where id=v_run.id; end if;
 update private.lca_release_runs set status='approved',approved_at=v_now where id=v_run.id;
 insert into private.command_audit_log(command,actor_user_id,target_table,target_id,target_version,payload)
   values('cmd_final_result_release_approve_v2',auth.uid(),'lca_release_approvals',p_approval_id,v_run.release_version,
     v_context||jsonb_build_object('releaseRunId',v_run.id,'publishPlanHash',p_publish_plan_hash,'approvalHash',v_hash,'expiresAt',p_expires_at));
 return jsonb_build_object('ok',true,'data',jsonb_build_object('approvalId',p_approval_id,'approvalHash',v_hash,'status','approved',
   'approvedBy',auth.uid(),'expiresAt',p_expires_at,'reused',false));
end;
$_$;

ALTER FUNCTION "api"."cmd_final_result_release_approve_v2"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_verification_id" "uuid", "p_approval_id" "uuid", "p_expected_approval_id" "uuid", "p_expires_at" timestamp with time zone, "p_reason" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."cmd_final_result_release_approve_v2"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_verification_id" "uuid", "p_approval_id" "uuid", "p_expected_approval_id" "uuid", "p_expires_at" timestamp with time zone, "p_reason" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."cmd_final_result_release_approve_v2"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_verification_id" "uuid", "p_approval_id" "uuid", "p_expected_approval_id" "uuid", "p_expires_at" timestamp with time zone, "p_reason" "text") TO "authenticated";
