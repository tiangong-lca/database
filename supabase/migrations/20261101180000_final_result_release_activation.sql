begin;
-- V2 human approval and atomic activation reuse the one release authority.
create table private.final_result_publication_bindings (
  publication_id uuid primary key references private.lca_release_publications(id),
  verification_id uuid not null references private.final_result_release_readiness(verification_id),
  previous_publication_id uuid references private.lca_release_publications(id),
  rollback_of_publication_id uuid references private.lca_release_publications(id)
);
alter table private.final_result_publication_bindings enable row level security;
revoke all on private.final_result_publication_bindings from public,anon,authenticated,service_role;
create trigger final_result_publication_bindings_immutable before update or delete on private.final_result_publication_bindings
 for each row execute function private.result_query_immutable_guard();

create function private.final_result_fresh_readiness(p_verification uuid,p_run uuid,p_plan_hash text,p_actor uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_ready private.final_result_release_readiness%rowtype; v_context jsonb;
begin
 select * into v_ready from private.final_result_release_readiness where verification_id=p_verification;
 if not found or v_ready.expires_at<=clock_timestamp() then
   raise exception using errcode='55000',message='Fresh final Result readiness is required'; end if;
 v_context:=private.final_result_verification_context(p_run,p_plan_hash,p_actor);
 if (v_ready.receipt-array['schemaVersion','verificationId','artifactCount','probeCount','fileCount','coverageHash','expiresAt','sealedAt'])
   is distinct from v_context then raise exception using errcode='55000',message='Final Result readiness preconditions changed'; end if;
 return v_ready.receipt;
end;
$$;
revoke all on function private.final_result_fresh_readiness(uuid,uuid,text,uuid) from public,anon,authenticated,service_role;

create function api.cmd_final_result_release_approve_v2(p_release_run_id uuid,p_publish_plan_hash text,p_verification_id uuid,
 p_approval_id uuid,p_expected_approval_id uuid,p_expires_at timestamptz,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
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
$$;

create function api.cmd_final_result_release_activate_v2(p_release_run_id uuid,p_publish_plan_hash text,p_approval_id uuid,
 p_approval_hash text,p_verification_id uuid,p_idempotency_key text,p_credential_fingerprint text)
returns jsonb language plpgsql security definer set search_path='' as $$
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
   left join private.final_result_identities i on i.result_id=q.result_id and i.result_version=q.result_version and i.registration_id=q.registration_id
     and i.content_hash=q.content_hash and i.registration_kind='registered'
   where m.release_run_id=v_run.id and (q.result_id is null or i.result_id is null)) then
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
$$;
-- Public query descriptors become available at the same activation commit.
-- Independent post-activation observation is a separate operation.

-- Source visibility uses the existing NOBYPASSRLS reader and all present/future
-- restrictive policies. Publishing derived C never grants access to parent A/B.
-- PL/pgSQL keeps relation-policy invalidation on a separate SPI plan; a cached
-- outer definer must not retain a SQL-language helper plan after policy changes.
create function private.final_result_source_readable(p_id uuid,p_version text)
returns boolean language plpgsql stable security definer set search_path='' set row_security=on as $$
begin
 return auth.uid() is not null and exists(select 1 from public.processes where id=p_id and version=p_version::character(9) and state_code<>120);
end;
$$;
create function private.final_result_candidate_support_readable(p_candidate text)
returns boolean language plpgsql stable security definer set search_path='' set row_security=on as $$
begin
 return not exists(
   select m.dataset_kind,m.dataset_id,m.dataset_version from private.final_result_candidate_members m
     where m.candidate_hash=p_candidate and m.dataset_role<>'result_process'
   except
   (select 'process',m.dataset_id,m.dataset_version from private.final_result_candidate_members m join public.processes d on d.id=m.dataset_id and d.version=m.dataset_version::character(9)
       where m.candidate_hash=p_candidate and m.dataset_kind='process' and d.state_code<>120
    union all select 'flow',m.dataset_id,m.dataset_version from private.final_result_candidate_members m join public.flows d on d.id=m.dataset_id and d.version=m.dataset_version::character(9)
       where m.candidate_hash=p_candidate and m.dataset_kind='flow'
    union all select 'flowproperty',m.dataset_id,m.dataset_version from private.final_result_candidate_members m join public.flowproperties d on d.id=m.dataset_id and d.version=m.dataset_version::character(9)
       where m.candidate_hash=p_candidate and m.dataset_kind='flowproperty'
    union all select 'unitgroup',m.dataset_id,m.dataset_version from private.final_result_candidate_members m join public.unitgroups d on d.id=m.dataset_id and d.version=m.dataset_version::character(9)
       where m.candidate_hash=p_candidate and m.dataset_kind='unitgroup'
    union all select 'lciamethod',m.dataset_id,m.dataset_version from private.final_result_candidate_members m join public.lciamethods d on d.id=m.dataset_id and d.version=m.dataset_version::character(9)
       where m.candidate_hash=p_candidate and m.dataset_kind='lciamethod'
    union all select 'contact',m.dataset_id,m.dataset_version from private.final_result_candidate_members m join public.contacts d on d.id=m.dataset_id and d.version=m.dataset_version::character(9)
       where m.candidate_hash=p_candidate and m.dataset_kind='contact'
    union all select 'source',m.dataset_id,m.dataset_version from private.final_result_candidate_members m join public.sources d on d.id=m.dataset_id and d.version=m.dataset_version::character(9)
       where m.candidate_hash=p_candidate and m.dataset_kind='source'));
end;
$$;
create temp table final_result_owner_authority on commit drop as
select (select to_jsonb(m) from pg_catalog.pg_auth_members m where m.roleid='api_internal_executor'::regrole
  and m.member='postgres'::regrole and m.grantor=current_user::regrole) own_grant,
  (select coalesce(jsonb_agg(to_jsonb(m) order by m.grantor,m.oid),'[]'::jsonb) from pg_catalog.pg_auth_members m
   where m.roleid='api_internal_executor'::regrole and m.member='postgres'::regrole) memberships;
create temp table final_result_schema_authority on commit drop as select oid,nspowner,nspacl from pg_catalog.pg_namespace where oid='private'::regnamespace;
do $$ begin
 if current_user<>'postgres' or exists(select 1 from pg_roles where rolname='api_internal_executor' and (rolsuper or rolbypassrls or rolcanlogin))
   or has_schema_privilege('api_internal_executor','private','create') then
   raise exception using errcode='42501',message='Final Result RLS owner precondition changed'; end if;
 grant api_internal_executor to postgres with inherit false,set true;
end $$;
grant create on schema private to api_internal_executor;
alter function private.final_result_source_readable(uuid,text) owner to api_internal_executor;
alter function private.final_result_candidate_support_readable(text) owner to api_internal_executor;
grant select on private.final_result_candidate_members to api_internal_executor;
create policy final_result_candidate_package_internal on private.final_result_candidate_members for select to api_internal_executor using (true);
set local role api_internal_executor;
revoke all on function private.final_result_source_readable(uuid,text),private.final_result_candidate_support_readable(text) from public,anon,authenticated,service_role;
grant execute on function private.final_result_source_readable(uuid,text),private.final_result_candidate_support_readable(text) to postgres;
reset role;
revoke create on schema private from api_internal_executor;
do $$ declare original record; after_memberships jsonb;
begin
 select * into original from final_result_owner_authority;
 if original.own_grant is null then revoke api_internal_executor from postgres;
 else execute format('grant api_internal_executor to postgres with admin %s,inherit %s,set %s',
   original.own_grant->>'admin_option',original.own_grant->>'inherit_option',original.own_grant->>'set_option'); end if;
 select coalesce(jsonb_agg(to_jsonb(m) order by m.grantor,m.oid),'[]'::jsonb) into after_memberships from pg_catalog.pg_auth_members m
   where m.roleid='api_internal_executor'::regrole and m.member='postgres'::regrole;
 if after_memberships is distinct from original.memberships or exists(select 1 from final_result_schema_authority old join pg_catalog.pg_namespace n using(oid)
   where old.nspowner is distinct from n.nspowner or old.nspacl is distinct from n.nspacl) then
   raise exception using errcode='55000',message='Final Result owner authority did not restore'; end if;
end $$;

create function api.qry_final_result_query_v2(p_result_id uuid,p_result_version text,p_publication_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_data jsonb; v_target text; v_runtime private.final_result_query_runtime_revisions%rowtype;
begin
 if auth.uid() is null then return private.lca_release_error('auth_required',401,'Authentication required'); end if;
 if p_result_id is null or coalesce(p_result_version,'') !~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$' then
   raise exception using errcode='22023',message='Exact final Result identity is required'; end if;
 select jsonb_build_object('publicationId',p.id,'releaseVersion',p.release_version,'scope',jsonb_build_object('kind','publication','publicationId',p.id),
   'artifact',a.artifact_ref,'result',jsonb_build_object('uuid',m.result_id,'version',m.result_version),'relationKind',q.relation_kind,
   'lciAvailable',true,'lciaAvailable',a.impact_count>0),plan.target_hash into v_data,v_target
 from private.lca_release_publications p join private.final_result_publication_bindings binding on binding.publication_id=p.id
 join private.lca_release_runs r on r.id=p.release_run_id and r.publication_format='final-result-pair.v2' and r.status in ('published','readback_verified')
 join private.final_result_release_plans plan on plan.release_run_id=r.id
 join private.final_result_release_members m on m.release_run_id=r.id and m.result_id=p_result_id and m.result_version=p_result_version
 join private.final_result_query_artifacts a on a.id=m.artifact_id
 join private.final_result_query_rows q on q.artifact_id=m.artifact_id and q.row_ordinal=m.row_ordinal and q.result_id=m.result_id and q.result_version=m.result_version
 join private.final_result_identities i on i.result_id=q.result_id and i.result_version=q.result_version and i.registration_id=q.registration_id
   and i.content_hash=q.content_hash and i.registration_kind='registered'
 where p.publication_series_key='global' and p.publication_channel='public' and p.visibility_scope='public' and p.is_current and p.status='current'
   and (p_publication_id is null or p.id=p_publication_id);
 if v_data is null then return private.lca_release_error('published_result_not_available',404,'Exact Result is not in the current publication'); end if;
 select rev.* into v_runtime from private.final_result_query_runtime_head h join private.final_result_query_runtime_revisions rev on rev.id=h.revision_id where h.singleton;
 if not found or not v_runtime.enabled or v_runtime.target_hash<>v_target then
   return private.lca_release_error('result_query_runtime_unavailable',503,'Published Result reader is unavailable'); end if;
 return jsonb_build_object('ok',true,'data',v_data||jsonb_build_object('runtimeRevision',v_runtime.id,'readerSha256',v_runtime.reader_sha256));
end;
$$;
create function api.qry_source_final_results_v2(p_source_id uuid,p_source_version text,p_after_key text default null,p_limit integer default 100,p_publication_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_publication private.lca_release_publications%rowtype; v_format text; v_rows jsonb; v_next text;
begin
 if auth.uid() is null then return private.lca_release_error('auth_required',401,'Authentication required'); end if;
 if p_source_id is null or coalesce(p_source_version,'') !~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$'
   or p_limit is null or p_limit not between 1 and 100 or (p_after_key is not null and (p_publication_id is null or p_after_key !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}@[0-9]{2}\.[0-9]{2}\.[0-9]{3}$')) then
   raise exception using errcode='22023',message='Invalid bounded exact source Result lookup'; end if;
 if not private.final_result_source_readable(p_source_id,p_source_version) then
   return private.lca_release_error('source_not_available',404,'Exact source Process is not readable'); end if;
 select p.* into v_publication from private.lca_release_publications p where p.publication_series_key='global' and p.publication_channel='public'
   and p.visibility_scope='public' and p.is_current and p.status='current';
 if not found then
   if p_publication_id is not null then return private.lca_release_error('publication_changed',409,'Restart source Result selection against current publication'); end if;
   return jsonb_build_object('ok',true,'data',jsonb_build_object('publication',null,'results','[]'::jsonb,'nextResultKey',null));
 end if;
 if p_publication_id is not null and p_publication_id<>v_publication.id then return private.lca_release_error('publication_changed',409,'Restart source Result selection against current publication'); end if;
 select publication_format into v_format from private.lca_release_runs where id=v_publication.release_run_id;
 if v_format='final-result-pair.v2' then
   with chosen as (select m.result_id,m.result_version,m.result_id::text||'@'||m.result_version key,a.impact_count
     from private.final_result_publication_bindings b join private.final_result_release_members m on m.release_run_id=v_publication.release_run_id
     join private.final_result_query_rows q on q.artifact_id=m.artifact_id and q.row_ordinal=m.row_ordinal and q.result_id=m.result_id and q.result_version=m.result_version and q.relation_kind='direct'
     join private.final_result_query_sources s on s.artifact_id=q.artifact_id and s.row_ordinal=q.row_ordinal and s.source_id=p_source_id and s.source_version=p_source_version
     join private.final_result_query_artifacts a on a.id=m.artifact_id where b.publication_id=v_publication.id
       and (p_after_key is null or (m.result_id::text||'@'||m.result_version) collate "C">p_after_key collate "C")
     order by m.result_id,m.result_version collate "C" limit p_limit+1),
   numbered as (select *,row_number() over(order by key collate "C") n from chosen)
   select coalesce(jsonb_agg(jsonb_build_object('uuid',result_id,'version',result_version,'relationKind','direct','lciAvailable',true,'lciaAvailable',impact_count>0)
     order by key collate "C") filter(where n<=p_limit),'[]'::jsonb),case when count(*)>p_limit then max(key collate "C") filter(where n=p_limit) else null end
     into v_rows,v_next from numbered;
 end if;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('publication',jsonb_build_object('publicationId',v_publication.id,
   'releaseVersion',v_publication.release_version,'format',v_format),'results',coalesce(v_rows,'[]'::jsonb),'nextResultKey',v_next));
end;
$$;
create function api.qry_final_result_download_v2(p_publication_id uuid,p_format text)
returns jsonb language plpgsql stable security definer set search_path='' set statement_timeout='20s' as $$
declare v_candidate text; v_target text; v_file jsonb;
begin
 if auth.uid() is null then return private.lca_release_error('auth_required',401,'Authentication required'); end if;
 if p_publication_id is null or p_format is null or p_format not in ('tidas','ilcd') then
   raise exception using errcode='22023',message='Exact publication and supported ZIP format are required'; end if;
 select plan.candidate_hash,plan.target_hash into v_candidate,v_target from private.lca_release_publications p
 join private.final_result_publication_bindings b on b.publication_id=p.id
 join private.final_result_release_plans plan on plan.release_run_id=p.release_run_id
 where p.id=p_publication_id and p.is_current and p.status='current';
 if v_candidate is null or exists(select 1 from private.final_result_candidate_artifacts ca
   join private.final_result_query_rows q on q.artifact_id=ca.artifact_id where ca.candidate_hash=v_candidate
   and not exists(select 1 from private.lca_release_publications p join private.final_result_release_members m on m.release_run_id=p.release_run_id
     where p.id=p_publication_id and m.result_id=q.result_id and m.result_version=q.result_version))
   or not private.final_result_candidate_support_readable(v_candidate) then
   return private.lca_release_error('result_package_not_available',404,'No complete prebuilt ZIP is authorized for this actor'); end if;
 select f.value into v_file from private.final_result_candidate_storage s cross join lateral jsonb_array_elements(s.receipt->'files') f
   where s.candidate_hash=v_candidate and s.target_hash=v_target and f.value->>'name'='result.'||p_format||'.zip';
 if v_file is null then return private.lca_release_error('result_package_not_available',404,'No complete prebuilt ZIP is authorized for this actor'); end if;
 return jsonb_build_object('ok',true,'data',jsonb_build_object('publicationId',p_publication_id,'candidateHash',v_candidate,'targetHash',v_target,'file',v_file));
end;
$$;

-- Preserve legacy bodies and ACLs except this exact version discriminator. A
-- NULL Bundle/empty artifact set must never reinterpret a final Result release.
do $legacy_dispatch$
declare target record; definition text; occurrences integer;
begin
 for target in select * from (values
('api.cmd_lca_release_publish(uuid,uuid,text,text,text,text,text,jsonb)','38ff6d694a94dc47dbe2b3ed0d95401d','  if v_run.id is null then
    return private.lca_release_error(''release_run_not_found'', 404, ''Release run not found'');
  end if;','  if v_run.id is null then
    return private.lca_release_error(''release_run_not_found'', 404, ''Release run not found'');
  end if;
  if v_run.publication_format<>''legacy-four-zip.v1'' then
    return private.lca_release_error(''final_result_versioned_api_required'',409,''Use the explicit final Result release API'');
  end if;'),
('private.cmd_lca_release_artifacts_finalize_service(uuid,text,jsonb,text,jsonb,jsonb)','5e07b159382e9cebf635f9a59fc289db','  if v_run.id is null then
    return private.lca_release_error(''release_run_not_found'', 404, ''Release run not found'');
  end if;','  if v_run.id is null then
    return private.lca_release_error(''release_run_not_found'', 404, ''Release run not found'');
  end if;
  if v_run.publication_format<>''legacy-four-zip.v1'' then
    return private.lca_release_error(''final_result_versioned_api_required'',409,''Use the explicit final Result release API'');
  end if;'),
('api.cmd_lca_release_approve(uuid,text,timestamp with time zone,text,jsonb)','e94328b8fe8f28d5dc3726b36555ae86','  if v_run.id is null then
    return private.lca_release_error(''release_run_not_found'', 404, ''Release run not found'');
  end if;','  if v_run.id is null then
    return private.lca_release_error(''release_run_not_found'', 404, ''Release run not found'');
  end if;
  if v_run.publication_format<>''legacy-four-zip.v1'' then
    return private.lca_release_error(''final_result_versioned_api_required'',409,''Use the explicit final Result release API'');
  end if;'),
('api.cmd_lca_release_readback_verify(uuid,text,jsonb,jsonb)','8c3d40b3f22f60aaa37fdfb11c466d4f','  if v_run.id is null then
    return private.lca_release_error(''release_run_not_found'', 404, ''Release run not found'');
  end if;','  if v_run.id is null then
    return private.lca_release_error(''release_run_not_found'', 404, ''Release run not found'');
  end if;
  if v_run.publication_format<>''legacy-four-zip.v1'' then
    return private.lca_release_error(''final_result_versioned_api_required'',409,''Use the explicit final Result release API'');
  end if;'),
('api.get_lca_release_run(uuid)','d5a25c304bfd6760b9aaaa044be90ebe','  return jsonb_build_object(
    ''ok'', true,
    ''data'', jsonb_build_object(','  if v_run.publication_format<>''legacy-four-zip.v1'' then
    return private.lca_release_error(''final_result_versioned_api_required'',409,''Use the explicit final Result release API'');
  end if;
  return jsonb_build_object(
    ''ok'', true,
    ''data'', jsonb_build_object('),
('api.svc_result_query_bind_release(uuid,uuid)','ce76911654537cece493abad537b404f','  select * into v_artifact from private.result_query_artifacts where id=p_artifact_id for share;','  if v_run.publication_format=''final-result-pair.v2'' then
    raise exception using errcode=''22023'',message=''Final Result releases require the versioned query binding contract'';
  end if;
  select * into v_artifact from private.result_query_artifacts where id=p_artifact_id for share;')
 ) patches(identity,source_md5,needle,replacement) loop
   if (select md5(prosrc) from pg_proc where oid=target.identity::regprocedure) is distinct from target.source_md5 then
     raise exception using errcode='55000',message='Final Result legacy dispatch predecessor drift'; end if;
   definition:=pg_get_functiondef(target.identity::regprocedure);
   occurrences:=(length(definition)-length(replace(definition,target.needle,'')))/length(target.needle);
   if occurrences<>1 then raise exception using errcode='55000',message='Final Result legacy dispatch boundary drift'; end if;
   execute replace(definition,target.needle,target.replacement);
 end loop;
end;
$legacy_dispatch$;

revoke all on function api.cmd_final_result_release_approve_v2(uuid,text,uuid,uuid,uuid,timestamptz,text),
 api.cmd_final_result_release_activate_v2(uuid,text,uuid,text,uuid,text,text),api.qry_final_result_query_v2(uuid,text,uuid),
 api.qry_source_final_results_v2(uuid,text,text,integer,uuid),api.qry_final_result_download_v2(uuid,text)
 from public,anon,authenticated,service_role;
grant execute on function api.cmd_final_result_release_approve_v2(uuid,text,uuid,uuid,uuid,timestamptz,text),
 api.cmd_final_result_release_activate_v2(uuid,text,uuid,text,uuid,text,text),api.qry_final_result_query_v2(uuid,text,uuid),
 api.qry_source_final_results_v2(uuid,text,text,integer,uuid),api.qry_final_result_download_v2(uuid,text) to authenticated;
insert into private.api_capability_grants(routine_identity,capability_id,allow_anon,allow_authenticated,allow_service_role) values
 ('api.cmd_final_result_release_approve_v2(uuid, text, uuid, uuid, uuid, timestamp with time zone, text)','EDGE-REL-01',false,true,false),
 ('api.cmd_final_result_release_activate_v2(uuid, text, uuid, text, uuid, text, text)','EDGE-REL-01',false,true,false),
 ('api.qry_final_result_query_v2(uuid, text, uuid)','DB-CORE-READ-01',false,true,false),
 ('api.qry_source_final_results_v2(uuid, text, text, integer, uuid)','DB-CORE-READ-01',false,true,false),
 ('api.qry_final_result_download_v2(uuid, text)','DB-CORE-READ-01',false,true,false);
notify pgrst,'reload schema';
commit;
