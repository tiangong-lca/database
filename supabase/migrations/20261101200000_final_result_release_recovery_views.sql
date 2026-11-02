begin;
-- Manager-only bounded recovery DTOs. Reads describe existing authority; they
-- never renew approval/readiness, infer permission from a client token, or write.
create function api.qry_final_result_publication_head_v2()
returns jsonb language plpgsql stable security definer set search_path='' as $$
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
create function api.qry_final_result_release_approval_v2(p_release_run_id uuid,p_approval_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
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
create or replace function api.qry_final_result_release_v2(p_release_run_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
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
revoke all on function api.qry_final_result_publication_head_v2(),api.qry_final_result_release_approval_v2(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function api.qry_final_result_publication_head_v2(),api.qry_final_result_release_approval_v2(uuid,uuid) to authenticated;
insert into private.api_capability_grants(routine_identity,capability_id,allow_anon,allow_authenticated,allow_service_role) values
 ('api.qry_final_result_publication_head_v2()','EDGE-REL-01',false,true,false),
 ('api.qry_final_result_release_approval_v2(uuid, uuid)','EDGE-REL-01',false,true,false);
notify pgrst,'reload schema';
commit;
