CREATE OR REPLACE FUNCTION "api"."cmd_final_result_release_prepare_v2"("p_plan_text" "text", "p_idempotency_key" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare v_auth jsonb:=api.assert_lca_release_manager(); v_plan jsonb; v_hash text; v_id uuid; v_expected uuid; v_rollback uuid;
  v_current uuid; v_candidate private.final_result_candidates%rowtype; v_old private.lca_release_runs%rowtype;
  v_count integer;
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
  -- The actor/idempotency lock also arbitrates two different run UUIDs for one key.
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':'||p_idempotency_key,881));
  select * into v_old from private.lca_release_runs where id=v_id or (created_by=auth.uid() and idempotency_key=p_idempotency_key)
    order by (id=v_id) desc limit 1 for update;
  if found then
    if v_old.id<>v_id or v_old.created_by<>auth.uid() or v_old.publication_format<>'final-result-pair.v2'
      or v_old.publish_plan_hash<>v_hash or v_old.idempotency_key<>p_idempotency_key then
      raise exception using errcode='23505',message='Final Result release preparation identity conflict';
    end if;
    return jsonb_build_object('ok',true,'data',jsonb_build_object('releaseRunId',v_id,'publishPlanHash',v_hash,'status',v_old.status,'publicationAuthorized',false));
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
  return jsonb_build_object('ok',true,'data',jsonb_build_object('releaseRunId',v_id,'publishPlanHash',v_hash,'status','prepared','publicationAuthorized',false));
end;
$_$;

ALTER FUNCTION "api"."cmd_final_result_release_prepare_v2"("p_plan_text" "text", "p_idempotency_key" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."cmd_final_result_release_prepare_v2"("p_plan_text" "text", "p_idempotency_key" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."cmd_final_result_release_prepare_v2"("p_plan_text" "text", "p_idempotency_key" "text") TO "authenticated";
