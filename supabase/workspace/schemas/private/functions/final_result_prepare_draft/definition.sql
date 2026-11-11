CREATE OR REPLACE FUNCTION "private"."final_result_prepare_draft"("p_plan_text" "text", "p_idempotency_key" "text", "p_replace_run_id" "uuid", "p_replace_plan_hash" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare v_auth jsonb:=api.assert_lca_release_manager(); v_plan jsonb; v_hash text; v_id uuid; v_expected uuid; v_rollback uuid;
  v_current uuid; v_candidate private.final_result_candidates%rowtype; v_old private.lca_release_runs%rowtype;
  v_count integer; v_version_run private.lca_release_runs%rowtype; v_constraint text;
begin
  if not coalesce((v_auth->>'ok')::boolean,false) then return v_auth; end if;
  if p_plan_text is null or octet_length(p_plan_text) not between 1 and 16384
    or not (p_plan_text is json object with unique keys) or coalesce(length(p_idempotency_key),0) not between 1 and 128
    or p_idempotency_key<>btrim(p_idempotency_key) then
    raise exception using errcode='22023',message='Invalid final Result publish plan';
  end if;
  v_plan:=p_plan_text::jsonb;
  if (select count(*) from jsonb_object_keys(v_plan))<>10
    or v_plan->>'schemaVersion' is distinct from 'tiangong.final-result-publish-plan.v2'
    or coalesce(v_plan->>'releaseRunId','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    or coalesce(v_plan->>'releaseVersion','') !~ '^[0-9]{4}\.[0-9]{2}\.[0-9]+$'
    or jsonb_typeof(v_plan->'releaseVersion') is distinct from 'string'
    or length(v_plan->>'releaseVersion')>64
    or coalesce(v_plan->>'candidateSha256','') !~ '^[0-9a-f]{64}$'
    or jsonb_typeof(v_plan->'candidateSha256') is distinct from 'string'
    or coalesce(v_plan->>'targetHash','') !~ '^[0-9a-f]{64}$'
    or jsonb_typeof(v_plan->'targetHash') is distinct from 'string'
    or coalesce(v_plan->>'selectionHash','') !~ '^[0-9a-f]{64}$'
    or jsonb_typeof(v_plan->'selectionHash') is distinct from 'string'
    or jsonb_typeof(v_plan->'reason') is distinct from 'string'
    or coalesce(length(btrim(v_plan->>'reason')),0) not between 1 and 2000
    or not (v_plan ? 'expectedCurrentPublicationId') or not (v_plan ? 'rollbackOfPublicationId') then
    raise exception using errcode='22023',message='Invalid final Result publish plan';
  end if;
  if (v_plan->'expectedCurrentPublicationId'<>'null'::jsonb and coalesce(v_plan->>'expectedCurrentPublicationId','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
    or (v_plan->'rollbackOfPublicationId'<>'null'::jsonb and coalesce(v_plan->>'rollbackOfPublicationId','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then
    raise exception using errcode='22023',message='Invalid final Result publication precondition';
  end if;
  v_count:=private.final_result_query_uint(v_plan->'selectionCount',2000000);
  if v_count=0 then raise exception using errcode='22023',message='Empty final Result publication selection'; end if;
  v_id:=(v_plan->>'releaseRunId')::uuid;
  v_expected:=(v_plan->>'expectedCurrentPublicationId')::uuid; v_rollback:=(v_plan->>'rollbackOfPublicationId')::uuid;
  v_hash:=encode(extensions.digest(convert_to(p_plan_text,'UTF8'),'sha256'),'hex');
  if (p_replace_run_id is null)<>(p_replace_plan_hash is null) or (p_replace_run_id is not null and (p_replace_run_id=v_id or p_replace_plan_hash !~ '^[0-9a-f]{64}$')) then
    return private.lca_release_error('final_result_draft_replacement_conflict',409,'Exact predecessor run and plan are required');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('final-result-version:'||(v_plan->>'releaseVersion'),882));
  -- The actor/idempotency lock also arbitrates two different run UUIDs for one key.
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':'||p_idempotency_key,881));
  select * into v_old from private.lca_release_runs where id=v_id or (created_by=auth.uid() and idempotency_key=p_idempotency_key)
    order by (id=v_id) desc limit 1 for update;
  if found then
    if v_old.id<>v_id or v_old.created_by<>auth.uid() or v_old.publication_format<>'final-result-pair.v2'
      or v_old.publish_plan_hash<>v_hash or v_old.idempotency_key<>p_idempotency_key then
      raise exception using errcode='23505',message='Final Result release preparation identity conflict';
    end if;
    if (p_replace_run_id is null and exists(select 1 from private.lca_release_runs where replaced_by_run_id=v_id))
      or (p_replace_run_id is not null and not exists(select 1 from private.lca_release_runs where id=p_replace_run_id and publish_plan_hash=p_replace_plan_hash and replaced_by_run_id=v_id)) then
      return private.lca_release_error('final_result_draft_replacement_conflict',409,'Retry must retain the exact predecessor');
    end if;
    return jsonb_build_object('ok',true,'data',jsonb_build_object('releaseRunId',v_id,'publishPlanHash',v_hash,'status',v_old.status,'publicationAuthorized',false));
  end if;
  select * into v_version_run from private.lca_release_runs where release_version=v_plan->>'releaseVersion' and replaced_by_run_id is null for update;
  if p_replace_run_id is null and found then
    return private.final_result_version_error('final_result_release_version_conflict',v_plan->>'releaseVersion');
  elsif p_replace_run_id is not null then
    if not found or v_version_run.id<>p_replace_run_id or v_version_run.publish_plan_hash<>p_replace_plan_hash then
      return private.final_result_version_error('final_result_draft_replacement_conflict',v_plan->>'releaseVersion');
    end if;
    if v_version_run.publication_format<>'final-result-pair.v2' or v_version_run.status not in ('prepared','ready_for_approval','failed')
      or exists(select 1 from private.lca_release_approvals where release_run_id=v_version_run.id)
      or exists(select 1 from private.lca_release_publications where release_run_id=v_version_run.id) then
      return private.final_result_version_error('final_result_draft_not_replaceable',v_plan->>'releaseVersion');
    end if;
  end if;
  select * into v_candidate from private.final_result_candidates c where c.candidate_hash=v_plan->>'candidateSha256'
    and exists(select 1 from private.final_result_candidate_storage s where s.candidate_hash=c.candidate_hash and s.target_hash=v_plan->>'targetHash');
  if not found or v_count>v_candidate.result_count then
    raise exception using errcode='22023',message='Final Result Candidate storage or selection count is invalid';
  end if;
  select id into v_current from private.lca_release_publications where publication_series_key='global'
    and publication_channel='public' and visibility_scope='public' and is_current and status='current';
  if v_current is distinct from v_expected then
    return private.lca_release_error('expected_current_conflict',409,'Current publication changed; prepare a new exact plan');
  end if;
  if v_rollback is not null and not exists(select 1 from private.lca_release_publications p
    join private.final_result_release_plans old on old.release_run_id=p.release_run_id
    where p.id=v_rollback and old.candidate_hash=v_candidate.candidate_hash and not p.is_current
      and p.status in ('superseded','unpublished')) then
    raise exception using errcode='22023',message='Rollback must reference terminal history with the exact retained Candidate';
  end if;
  perform 1 from private.roles where user_id=auth.uid() and team_id='00000000-0000-0000-0000-000000000000' and role='data_product_manager' for share;
  if not found then return private.lca_release_error('not_data_product_manager',403,'Current manager grant is required'); end if;
  if p_replace_run_id is not null then
    update private.lca_release_runs set status='abandoned',replaced_by_run_id=v_id where id=p_replace_run_id;
  end if;
  insert into private.lca_release_runs(id,release_version,publication_format,scope_mode,selection_manifest_hash,input_manifest_hash,
    calculation_bundle_hash,calculation_bundle_ref,profile_lock_hash,publish_plan_hash,publish_plan,artifact_set_hash,
    release_manifest_hash,release_manifest,artifacts_finalized_at,status,idempotency_key,request_hash,created_by)
    values(v_id,v_plan->>'releaseVersion','final-result-pair.v2','selected_final_results',v_plan->>'selectionHash',v_candidate.input_hash,
      null,null,encode(extensions.digest(convert_to('result-process-full-closure.v1','UTF8'),'sha256'),'hex'),v_hash,v_plan,
      v_candidate.manifest->>'packageSetHash',v_candidate.candidate_hash,v_candidate.manifest,clock_timestamp(),'prepared',p_idempotency_key,v_hash,auth.uid());
  insert into private.final_result_release_plans values(v_id,v_candidate.candidate_hash,v_plan->>'targetHash',v_count,v_expected,v_rollback,p_plan_text);
  insert into private.command_audit_log(command,actor_user_id,target_table,target_id,target_version,payload)
    values('cmd_final_result_release_prepare_v2',auth.uid(),'lca_release_runs',v_id,v_plan->>'releaseVersion',
      jsonb_build_object('publishPlanHash',v_hash,'candidateHash',v_candidate.candidate_hash,'targetHash',v_plan->>'targetHash','rollbackOfPublicationId',v_rollback));
  if p_replace_run_id is not null then
    insert into private.command_audit_log(command,actor_user_id,target_table,target_id,target_version,payload)
      values('cmd_final_result_release_replace_v2',auth.uid(),'lca_release_runs',v_id,v_plan->>'releaseVersion',
        jsonb_build_object('previousReleaseRunId',p_replace_run_id,'previousPublishPlanHash',p_replace_plan_hash,'publishPlanHash',v_hash,'reason',v_plan->>'reason'));
  end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('releaseRunId',v_id,'publishPlanHash',v_hash,'status','prepared','publicationAuthorized',false));
exception
  when unique_violation then
    get stacked diagnostics v_constraint=constraint_name;
    if v_constraint='lca_release_runs_version_uidx' then
      return private.final_result_version_error('final_result_release_version_conflict',v_plan->>'releaseVersion');
    end if;
    raise;
end;
$_$;

ALTER FUNCTION "private"."final_result_prepare_draft"("p_plan_text" "text", "p_idempotency_key" "text", "p_replace_run_id" "uuid", "p_replace_plan_hash" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."final_result_prepare_draft"("p_plan_text" "text", "p_idempotency_key" "text", "p_replace_run_id" "uuid", "p_replace_plan_hash" "text") FROM PUBLIC;
