begin;
set local lock_timeout = '5s';

-- Explicit additive format: v1 keeps its Bundle, scope and version constraints.
-- V2 references final Candidate storage; it must not fabricate a calculation.
alter table private.lca_release_runs
  add column publication_format text not null default 'legacy-four-zip.v1',
  alter column calculation_bundle_hash drop not null,
  alter column calculation_bundle_ref drop not null,
  drop constraint lca_release_runs_release_version_chk,
  drop constraint lca_release_runs_scope_chk,
  add constraint lca_release_runs_format_chk check(publication_format in ('legacy-four-zip.v1','final-result-pair.v2')),
  add constraint lca_release_runs_bundle_format_chk check(
    (publication_format='legacy-four-zip.v1' and calculation_bundle_hash is not null and calculation_bundle_ref is not null)
    or (publication_format='final-result-pair.v2' and calculation_bundle_hash is null and calculation_bundle_ref is null)),
  add constraint lca_release_runs_release_version_chk check(
    (publication_format='legacy-four-zip.v1' and release_version ~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$')
    or (publication_format='final-result-pair.v2' and length(release_version)<=64 and release_version ~ '^[0-9]{4}\.[0-9]{2}\.[0-9]+$')),
  add constraint lca_release_runs_scope_chk check(
    (publication_format='legacy-four-zip.v1' and scope_mode='global_eligible')
    or (publication_format='final-result-pair.v2' and scope_mode='selected_final_results'));

create table private.final_result_release_plans (
  release_run_id uuid primary key references private.lca_release_runs(id),
  candidate_hash text not null references private.final_result_candidates(candidate_hash),
  target_hash text not null,
  selection_count integer not null check(selection_count between 1 and 2000000),
  expected_current_publication_id uuid references private.lca_release_publications(id),
  rollback_of_publication_id uuid references private.lca_release_publications(id),
  plan_text text not null check(octet_length(plan_text) between 1 and 16384),
  foreign key(candidate_hash,target_hash) references private.final_result_candidate_storage(candidate_hash,target_hash)
);
create table private.final_result_release_members (
  release_run_id uuid not null references private.final_result_release_plans(release_run_id),
  result_id uuid not null,
  result_version text not null check(result_version ~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$'),
  artifact_id uuid not null,
  row_ordinal integer not null,
  primary key(release_run_id,result_id,result_version),
  foreign key(artifact_id,row_ordinal) references private.final_result_query_rows(artifact_id,row_ordinal)
);
create table private.final_result_release_selection_seals (
  release_run_id uuid primary key references private.final_result_release_plans(release_run_id),
  selection_hash text not null check(selection_hash ~ '^[0-9a-f]{64}$'),
  sealed_by uuid not null,
  sealed_at timestamptz not null default now()
);
alter table private.final_result_release_plans enable row level security;
alter table private.final_result_release_members enable row level security;
alter table private.final_result_release_selection_seals enable row level security;
revoke all on private.final_result_release_plans,private.final_result_release_members,
  private.final_result_release_selection_seals from public,anon,authenticated,service_role;
create trigger final_result_release_plans_immutable before update or delete on private.final_result_release_plans
  for each row execute function private.result_query_immutable_guard();
create trigger final_result_release_members_immutable before update or delete on private.final_result_release_members
  for each row execute function private.result_query_immutable_guard();
create trigger final_result_release_selection_seals_immutable before update or delete on private.final_result_release_selection_seals
  for each row execute function private.result_query_immutable_guard();

CREATE OR REPLACE FUNCTION "private"."lca_release_guard_run_update"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'private', 'api', 'public', 'util', 'extensions', 'pg_temp'
    AS $$
begin
  if old.publication_format is distinct from new.publication_format
     or old.id is distinct from new.id
     or old.release_version is distinct from new.release_version
     or old.scope_mode is distinct from new.scope_mode
     or old.selection_manifest_hash is distinct from new.selection_manifest_hash
     or old.input_manifest_hash is distinct from new.input_manifest_hash
     or old.calculation_bundle_hash is distinct from new.calculation_bundle_hash
     or old.calculation_bundle_ref is distinct from new.calculation_bundle_ref
     or old.profile_lock_hash is distinct from new.profile_lock_hash
     or old.publish_plan_hash is distinct from new.publish_plan_hash
     or old.publish_plan is distinct from new.publish_plan
     or old.artifact_set_hash is distinct from new.artifact_set_hash
     or old.idempotency_key is distinct from new.idempotency_key
     or old.request_hash is distinct from new.request_hash
     or old.created_by is distinct from new.created_by
     or old.created_at is distinct from new.created_at then
    raise exception 'lca_release_run_immutable_content'
      using errcode = '23514';
  end if;

  if old.release_manifest_hash is not null
     and (
       old.release_manifest_hash is distinct from new.release_manifest_hash
       or old.release_manifest is distinct from new.release_manifest
       or old.artifacts_finalized_at is distinct from new.artifacts_finalized_at
     ) then
    raise exception 'lca_release_manifest_immutable'
      using errcode = '23514';
  end if;

  if old.status is distinct from new.status
     and not (
       (old.status = 'prepared' and new.status in ('ready_for_approval', 'failed', 'abandoned'))
       or (old.status = 'ready_for_approval' and new.status in ('approved', 'failed', 'abandoned'))
       or (old.status = 'approved' and new.status in ('published', 'failed', 'abandoned'))
       or (old.status = 'published' and new.status in ('readback_verified', 'unpublished'))
       or (old.status = 'readback_verified' and new.status = 'unpublished')
     ) then
    raise exception 'lca_release_state_transition_invalid:%->%', old.status, new.status
      using errcode = '23514';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

ALTER FUNCTION "private"."lca_release_guard_run_update"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."lca_release_guard_run_update"() FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."lca_release_guard_run_update"() TO "api_internal_executor";

create function api.cmd_final_result_release_prepare_v2(p_plan_text text,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path='' as $$
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
$$;

create function api.cmd_final_result_release_members_v2(p_release_run_id uuid,p_publish_plan_hash text,p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_auth jsonb:=api.assert_lca_release_manager(); v_run private.lca_release_runs%rowtype;
  v_plan private.final_result_release_plans%rowtype; v_row jsonb; v_query private.final_result_query_rows%rowtype;
  v_old private.final_result_release_members%rowtype; v_count bigint;
begin
  if not coalesce((v_auth->>'ok')::boolean,false) then return v_auth; end if;
  if jsonb_typeof(p_rows) is distinct from 'array' or pg_column_size(p_rows)>1048576 or octet_length(p_rows::text)>1048576 then
    raise exception using errcode='22023',message='Invalid final Result release membership batch';
  end if;
  if jsonb_array_length(p_rows) not between 1 and 500 then raise exception using errcode='22023',message='Invalid final Result release membership batch'; end if;
  select * into v_run from private.lca_release_runs where id=p_release_run_id for update;
  if not found or v_run.publication_format<>'final-result-pair.v2' or v_run.publish_plan_hash is distinct from p_publish_plan_hash then
    return private.lca_release_error('final_result_release_not_found',404,'Exact final Result release plan is required');
  end if;
  select * into strict v_plan from private.final_result_release_plans where release_run_id=v_run.id;
  for v_row in select value from jsonb_array_elements(p_rows) loop
    if jsonb_typeof(v_row) is distinct from 'object' then raise exception using errcode='22023',message='Invalid final Result selection identity'; end if;
    if (select count(*) from jsonb_object_keys(v_row))<>2
      or coalesce(v_row->>'uuid','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      or coalesce(v_row->>'version','') !~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$' then
      raise exception using errcode='22023',message='Invalid final Result selection identity';
    end if;
    select q.* into v_query from private.final_result_query_rows q
      join private.final_result_candidate_artifacts a on a.artifact_id=q.artifact_id
      where a.candidate_hash=v_plan.candidate_hash and q.result_id=(v_row->>'uuid')::uuid and q.result_version=v_row->>'version';
    if not found then raise exception using errcode='22023',message='Selected Result is absent from the exact Candidate'; end if;
    select * into v_old from private.final_result_release_members where release_run_id=v_run.id and result_id=v_query.result_id and result_version=v_query.result_version;
    if found then
      if v_old.artifact_id<>v_query.artifact_id or v_old.row_ordinal<>v_query.row_ordinal then
        raise exception using errcode='23505',message='Final Result selection binding conflict';
      end if;
    else
      if v_run.status<>'prepared' or exists(select 1 from private.final_result_release_selection_seals where release_run_id=v_run.id) then
        raise exception using errcode='55000',message='Sealed final Result release selection is immutable';
      end if;
      insert into private.final_result_release_members values(v_run.id,v_query.result_id,v_query.result_version,v_query.artifact_id,v_query.row_ordinal);
    end if;
  end loop;
  select count(*) into v_count from private.final_result_release_members where release_run_id=v_run.id;
  if v_count>v_plan.selection_count then raise exception using errcode='22023',message='Final Result selection exceeds the frozen count'; end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('releaseRunId',v_run.id,'registeredResultCount',v_count,'publicationAuthorized',false));
end;
$$;

create function api.cmd_final_result_release_seal_v2(p_release_run_id uuid,p_publish_plan_hash text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_auth jsonb:=api.assert_lca_release_manager(); v_run private.lca_release_runs%rowtype;
  v_plan private.final_result_release_plans%rowtype; v_hash text; v_count bigint;
begin
  if not coalesce((v_auth->>'ok')::boolean,false) then return v_auth; end if;
  select * into v_run from private.lca_release_runs where id=p_release_run_id for update;
  if not found or v_run.publication_format<>'final-result-pair.v2' or v_run.publish_plan_hash is distinct from p_publish_plan_hash then
    return private.lca_release_error('final_result_release_not_found',404,'Exact final Result release plan is required');
  end if;
  select * into strict v_plan from private.final_result_release_plans where release_run_id=v_run.id;
  select count(*) into v_count from private.final_result_release_members where release_run_id=v_run.id;
  if v_count<>v_plan.selection_count then raise exception using errcode='22023',message='Final Result selection is incomplete'; end if;
  with selected as (
    select (row_number() over(order by result_id,result_version collate "C")-1)/500 as block,
      result_id::text||'@'||result_version as key
    from private.final_result_release_members where release_run_id=v_run.id
  ), blocks as (
    select block,encode(extensions.digest(convert_to(string_agg(key||E'\n','' order by key collate "C"),'UTF8'),'sha256'),'hex') hash
    from selected group by block
  ) select encode(extensions.digest(convert_to('tiangong.final-result-selection.v1'||E'\n'||string_agg(hash||E'\n','' order by block),'UTF8'),'sha256'),'hex') into v_hash from blocks;
  if v_hash<>v_run.selection_manifest_hash then raise exception using errcode='22023',message='Final Result selection hash mismatch'; end if;
  if not exists(select 1 from private.final_result_release_selection_seals where release_run_id=v_run.id) then
    if v_run.status<>'prepared' then raise exception using errcode='55000',message='Final Result release cannot change its selection'; end if;
    insert into private.final_result_release_selection_seals(release_run_id,selection_hash,sealed_by) values(v_run.id,v_hash,auth.uid());
    insert into private.command_audit_log(command,actor_user_id,target_table,target_id,target_version,payload)
      values('cmd_final_result_release_seal_v2',auth.uid(),'lca_release_runs',v_run.id,v_run.release_version,jsonb_build_object('publishPlanHash',v_run.publish_plan_hash,'selectionHash',v_hash,'resultCount',v_count));
  end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('releaseRunId',v_run.id,'selectionHash',v_hash,'resultCount',v_count,'sealed',true,'publicationAuthorized',false));
end;
$$;

create function api.qry_final_result_release_v2(p_release_run_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_auth jsonb:=api.assert_lca_release_manager(); v_data jsonb;
begin
  if not coalesce((v_auth->>'ok')::boolean,false) then return v_auth; end if;
  select jsonb_build_object('releaseRunId',r.id,'releaseVersion',r.release_version,'status',r.status,'publishPlanHash',r.publish_plan_hash,
    'candidateHash',p.candidate_hash,'targetHash',p.target_hash,'selectionHash',r.selection_manifest_hash,'selectionCount',p.selection_count,
    'registeredResultCount',(select count(*) from private.final_result_release_members where release_run_id=r.id),
    'selectionSealed',exists(select 1 from private.final_result_release_selection_seals where release_run_id=r.id),
    'expectedCurrentPublicationId',p.expected_current_publication_id,'rollbackOfPublicationId',p.rollback_of_publication_id,
    'publicationAuthorized',false) into v_data
  from private.lca_release_runs r join private.final_result_release_plans p on p.release_run_id=r.id
  where r.id=p_release_run_id and r.publication_format='final-result-pair.v2';
  return jsonb_build_object('ok',true,'data',v_data);
end;
$$;
revoke all on function api.cmd_final_result_release_prepare_v2(text,text),api.cmd_final_result_release_members_v2(uuid,text,jsonb),
  api.cmd_final_result_release_seal_v2(uuid,text),api.qry_final_result_release_v2(uuid) from public,anon,authenticated,service_role;
grant execute on function api.cmd_final_result_release_prepare_v2(text,text),api.cmd_final_result_release_members_v2(uuid,text,jsonb),
  api.cmd_final_result_release_seal_v2(uuid,text),api.qry_final_result_release_v2(uuid) to authenticated;
insert into private.api_capability_grants(routine_identity,capability_id,allow_anon,allow_authenticated,allow_service_role) values
  ('api.cmd_final_result_release_prepare_v2(text, text)','EDGE-REL-01',false,true,false),
  ('api.cmd_final_result_release_members_v2(uuid, text, jsonb)','EDGE-REL-01',false,true,false),
  ('api.cmd_final_result_release_seal_v2(uuid, text)','EDGE-REL-01',false,true,false),
  ('api.qry_final_result_release_v2(uuid)','EDGE-REL-01',false,true,false);
notify pgrst,'reload schema';
commit;
