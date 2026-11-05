CREATE OR REPLACE FUNCTION "api"."cmd_final_result_release_activate_v2"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_approval_id" "uuid", "p_approval_hash" "text", "p_verification_id" "uuid", "p_idempotency_key" "text", "p_credential_fingerprint" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare v_auth jsonb:=api.assert_lca_release_manager(); v_run private.lca_release_runs%rowtype;
 v_plan private.final_result_release_plans%rowtype; v_approval private.lca_release_approvals%rowtype;
 v_old private.lca_release_publications%rowtype; v_publication private.lca_release_publications%rowtype; v_previous uuid;
 v_ready jsonb; v_now timestamptz:=clock_timestamp();
begin
 if not coalesce((v_auth->>'ok')::boolean,false) then return v_auth; end if;
 if p_release_run_id is null or p_approval_id is null or p_verification_id is null
   or coalesce(p_publish_plan_hash,'') !~ '^[0-9a-f]{64}$' or coalesce(p_approval_hash,'') !~ '^[0-9a-f]{64}$'
   or coalesce(p_credential_fingerprint,'') !~ '^[0-9a-f]{64}$' or coalesce(length(p_idempotency_key),0) not between 1 and 128
   or btrim(p_idempotency_key)<>p_idempotency_key then raise exception using errcode='22023',message='Exact final Result activation arguments are required'; end if;
 select * into v_run from private.lca_release_runs where id=p_release_run_id for update;
 if not found or v_run.publication_format<>'final-result-pair.v2' or v_run.publish_plan_hash is distinct from p_publish_plan_hash then
   return private.lca_release_error('final_result_plan_not_found',404,'Exact final Result plan is required'); end if;
 select * into v_old from private.lca_release_publications where release_run_id=v_run.id
   or (executed_by=auth.uid() and idempotency_key=p_idempotency_key) order by (release_run_id=v_run.id) desc limit 1;
 if found then
   if v_old.release_run_id<>v_run.id or v_old.executed_by<>auth.uid() or v_old.approval_id<>p_approval_id or v_old.approval_hash<>p_approval_hash
     or v_old.idempotency_key<>p_idempotency_key or v_old.credential_fingerprint<>p_credential_fingerprint
     or not exists(select 1 from private.final_result_publication_bindings where publication_id=v_old.id and verification_id=p_verification_id) then
     return private.lca_release_error('publish_idempotency_conflict',409,'Publication identity already binds another execution'); end if;
   return jsonb_build_object('ok',true,'data',jsonb_build_object('publicationId',v_old.id,'releaseRunId',v_run.id,'releaseVersion',v_run.release_version,
     'status',v_old.status,'isCurrent',v_old.is_current,'publishedAt',v_old.published_at,'reused',true));
 end if;
 if v_run.status<>'approved' then return private.lca_release_error('release_not_approved',409,'Exact active approval is required'); end if;
 select * into v_approval from private.lca_release_approvals where id=p_approval_id and release_run_id=v_run.id for update;
 if not found or v_approval.status<>'approved' or v_approval.approval_hash<>p_approval_hash or v_approval.publish_plan_hash<>p_publish_plan_hash
   or v_approval.expires_at<=v_now or v_approval.audit_correlation->>'schemaVersion' is distinct from 'tiangong.final-result-approval.v2' then
   return private.lca_release_error('approval_invalid',409,'Exact unexpired final Result approval is required'); end if;
 perform 1 from private.final_result_query_runtime_head where singleton for share;
 perform 1 from private.roles where user_id in (auth.uid(),v_approval.approved_by) and team_id='00000000-0000-0000-0000-000000000000'
   and role='data_product_manager' order by user_id for share;
 if not private.lca_release_is_manager() then return private.lca_release_error('not_data_product_manager',403,'Live execution authority is required'); end if;
 -- Serialize with legacy publish/unpublish too: the global current pointer has
 -- one authority. A new readiness sample may refresh the same approved context.
 lock table private.lca_release_publications in exclusive mode;
 v_now:=clock_timestamp();
 if v_approval.expires_at<=v_now then return private.lca_release_error('approval_invalid',409,'Approval expired while waiting to activate'); end if;
 v_ready:=private.final_result_fresh_readiness(p_verification_id,v_run.id,p_publish_plan_hash,v_approval.approved_by);
 if (v_approval.audit_correlation-array['schemaVersion','verificationId','expectedApprovalId']) is distinct from jsonb_build_object(
   'candidateHash',v_ready->>'candidateHash','targetHash',v_ready->>'targetHash','selectionHash',v_ready->>'selectionHash',
   'runtimeRevision',v_ready->>'runtimeRevision','readerSha256',v_ready->>'readerSha256','permissionHash',v_ready->>'permissionHash') then
   return private.lca_release_error('approval_context_changed',409,'Fresh readiness must match the approved context'); end if;
 select * into strict v_plan from private.final_result_release_plans where release_run_id=v_run.id;
 select id into v_previous from private.lca_release_publications where publication_series_key='global' and publication_channel='public'
   and visibility_scope='public' and is_current and status='current' for update;
 if v_previous is distinct from v_plan.expected_current_publication_id then return private.lca_release_error('expected_current_conflict',409,'Current publication changed'); end if;
 if v_plan.rollback_of_publication_id is not null and not exists(select 1 from private.lca_release_publications p
   join private.final_result_release_plans old_plan on old_plan.release_run_id=p.release_run_id
   join private.lca_release_runs old_run on old_run.id=p.release_run_id
   where p.id=v_plan.rollback_of_publication_id and not p.is_current and p.status in ('superseded','unpublished')
     and old_plan.candidate_hash=v_plan.candidate_hash and old_run.selection_manifest_hash=v_run.selection_manifest_hash) then
   return private.lca_release_error('rollback_scope_mismatch',409,'Rollback must retain the exact historical Candidate and selection'); end if;
 if exists(select 1 from private.final_result_release_members m left join private.final_result_query_rows q
   on q.artifact_id=m.artifact_id and q.row_ordinal=m.row_ordinal and q.result_id=m.result_id and q.result_version=m.result_version
   where m.release_run_id=v_run.id and q.result_id is null) then
   raise exception using errcode='55000',message='Final Result publication content identity changed'; end if;
 if v_previous is not null then update private.lca_release_publications set is_current=false,status='superseded',superseded_at=v_now where id=v_previous; end if;
 insert into private.lca_release_publications(release_run_id,release_version,approval_id,approval_hash,publish_plan_hash,release_manifest_hash,
   artifact_set_hash,approved_by,executed_by,credential_fingerprint,idempotency_key,published_at,reason)
   values(v_run.id,v_run.release_version,v_approval.id,v_approval.approval_hash,p_publish_plan_hash,v_run.release_manifest_hash,v_run.artifact_set_hash,
     v_approval.approved_by,auth.uid(),p_credential_fingerprint,p_idempotency_key,v_now,v_run.publish_plan->>'reason') returning * into v_publication;
 insert into private.final_result_publication_bindings(publication_id,verification_id,previous_publication_id,rollback_of_publication_id)
   values(v_publication.id,p_verification_id,v_previous,v_plan.rollback_of_publication_id);
 if v_previous is not null then update private.lca_release_publications set superseded_by=v_publication.id where id=v_previous; end if;
 update private.lca_release_approvals set status='consumed',consumed_by=auth.uid(),consumed_at=v_now where id=v_approval.id;
 update private.lca_release_runs set status='published',published_at=v_now where id=v_run.id;
 insert into private.command_audit_log(command,actor_user_id,target_table,target_id,target_version,payload)
   values('cmd_final_result_release_activate_v2',auth.uid(),'lca_release_publications',v_publication.id,v_run.release_version,
     jsonb_build_object('releaseRunId',v_run.id,'publishPlanHash',p_publish_plan_hash,'approvalId',v_approval.id,'verificationId',p_verification_id,
       'previousPublicationId',v_previous,'rollbackOfPublicationId',v_plan.rollback_of_publication_id));
 return jsonb_build_object('ok',true,'data',jsonb_build_object('publicationId',v_publication.id,'releaseRunId',v_run.id,'releaseVersion',v_run.release_version,
   'status','current','isCurrent',true,'publishedAt',v_now,'reused',false));
exception when unique_violation then
 return private.lca_release_error('publication_conflict',409,'Release version or execution identity already has a publication');
end;
$_$;

ALTER FUNCTION "api"."cmd_final_result_release_activate_v2"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_approval_id" "uuid", "p_approval_hash" "text", "p_verification_id" "uuid", "p_idempotency_key" "text", "p_credential_fingerprint" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."cmd_final_result_release_activate_v2"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_approval_id" "uuid", "p_approval_hash" "text", "p_verification_id" "uuid", "p_idempotency_key" "text", "p_credential_fingerprint" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."cmd_final_result_release_activate_v2"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_approval_id" "uuid", "p_approval_hash" "text", "p_verification_id" "uuid", "p_idempotency_key" "text", "p_credential_fingerprint" "text") TO "authenticated";
