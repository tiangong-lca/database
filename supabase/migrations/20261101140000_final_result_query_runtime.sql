begin;
set local lock_timeout='5s';

-- Admission changes use a fresh immutable revision, including a return to a
-- previous target/binary. Pending readiness must never revive after a revert.
create table private.final_result_query_runtime_revisions (
  id uuid primary key,
  previous_revision_id uuid references private.final_result_query_runtime_revisions(id),
  target_hash text not null check(target_hash ~ '^[0-9a-f]{64}$'),
  reader_sha256 text not null check(reader_sha256 ~ '^[0-9a-f]{64}$'),
  enabled boolean not null,
  reason text not null check(length(reason) between 1 and 2000 and length(btrim(reason))>0),
  created_at timestamptz not null default clock_timestamp()
);
create table private.final_result_query_runtime_head (
  singleton boolean primary key default true check(singleton),
  revision_id uuid not null references private.final_result_query_runtime_revisions(id)
);
alter table private.final_result_query_runtime_revisions enable row level security;
alter table private.final_result_query_runtime_head enable row level security;
revoke all on private.final_result_query_runtime_revisions,private.final_result_query_runtime_head from public,anon,authenticated,service_role;
create trigger final_result_query_runtime_revisions_immutable before update or delete on private.final_result_query_runtime_revisions
  for each row execute function private.result_query_immutable_guard();
create index final_result_release_members_artifact_idx on private.final_result_release_members(release_run_id,artifact_id,result_id,result_version);

create function api.svc_result_query_runtime_configure_v2(p_revision_id uuid,p_expected_revision_id uuid,
  p_target_hash text,p_reader_sha256 text,p_enabled boolean,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_head uuid; v_old private.final_result_query_runtime_revisions%rowtype;
begin
  if p_revision_id is null or coalesce(p_target_hash,'') !~ '^[0-9a-f]{64}$'
    or coalesce(p_reader_sha256,'') !~ '^[0-9a-f]{64}$' or p_enabled is null
    or coalesce(length(p_reason),0) not between 1 and 2000 or length(btrim(p_reason))=0 then
    raise exception using errcode='22023',message='Invalid final Result runtime admission';
  end if;
  perform pg_advisory_xact_lock(882,1);
  select revision_id into v_head from private.final_result_query_runtime_head where singleton for update;
  select * into v_old from private.final_result_query_runtime_revisions where id=p_revision_id;
  if found then
    if v_old.previous_revision_id is distinct from p_expected_revision_id or v_old.target_hash<>p_target_hash
      or v_old.reader_sha256<>p_reader_sha256 or v_old.enabled<>p_enabled or v_old.reason<>p_reason then
      raise exception using errcode='23505',message='Final Result runtime revision identity conflict';
    end if;
    return jsonb_build_object('ok',true,'data',jsonb_build_object('runtimeRevision',v_old.id,'isCurrent',v_head=v_old.id,
      'targetHash',v_old.target_hash,'readerSha256',v_old.reader_sha256,'enabled',v_old.enabled,'publicationAuthorized',false));
  end if;
  if v_head is distinct from p_expected_revision_id then
    return private.lca_release_error('runtime_revision_conflict',409,'Runtime admission changed; read the exact current revision');
  end if;
  insert into private.final_result_query_runtime_revisions(id,previous_revision_id,target_hash,reader_sha256,enabled,reason)
    values(p_revision_id,v_head,p_target_hash,p_reader_sha256,p_enabled,p_reason);
  insert into private.final_result_query_runtime_head(singleton,revision_id) values(true,p_revision_id)
    on conflict(singleton) do update set revision_id=excluded.revision_id;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('runtimeRevision',p_revision_id,'isCurrent',true,
    'targetHash',p_target_hash,'readerSha256',p_reader_sha256,'enabled',p_enabled,'publicationAuthorized',false));
end;
$$;
create function api.svc_result_query_runtime_read_v2()
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('ok',true,'data',(select jsonb_build_object('runtimeRevision',r.id,'targetHash',r.target_hash,
    'readerSha256',r.reader_sha256,'enabled',r.enabled,'publicationAuthorized',false)
    from private.final_result_query_runtime_head h join private.final_result_query_runtime_revisions r on r.id=h.revision_id where h.singleton));
$$;

-- Manager-only staging context. Ordinary current-publication resolution is a
-- different contract and cannot be used to bootstrap unpublished readiness.
create function private.final_result_release_probe_context(p_release_run_id uuid,p_publish_plan_hash text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_auth jsonb:=api.assert_lca_release_manager(); v_run private.lca_release_runs%rowtype;
  v_plan private.final_result_release_plans%rowtype; v_runtime private.final_result_query_runtime_revisions%rowtype;
  v_current uuid; v_permission text;
begin
  if not coalesce((v_auth->>'ok')::boolean,false) then return v_auth; end if;
  select * into v_run from private.lca_release_runs where id=p_release_run_id;
  if not found or v_run.publication_format<>'final-result-pair.v2' or v_run.publish_plan_hash is distinct from p_publish_plan_hash
    or v_run.status not in ('prepared','ready_for_approval','approved') then
    return private.lca_release_error('final_result_probe_not_available',404,'Exact unpublished final Result plan is required');
  end if;
  select * into strict v_plan from private.final_result_release_plans where release_run_id=v_run.id;
  if not exists(select 1 from private.final_result_release_selection_seals where release_run_id=v_run.id and selection_hash=v_run.selection_manifest_hash) then
    return private.lca_release_error('final_result_selection_unsealed',409,'Complete selected membership must be sealed first');
  end if;
  select r.* into v_runtime from private.final_result_query_runtime_head h
    join private.final_result_query_runtime_revisions r on r.id=h.revision_id where h.singleton;
  if not found or not v_runtime.enabled or v_runtime.target_hash<>v_plan.target_hash then
    return private.lca_release_error('final_result_runtime_unavailable',409,'An enabled exact storage target and reader revision are required');
  end if;
  select id into v_current from private.lca_release_publications where publication_series_key='global'
    and publication_channel='public' and visibility_scope='public' and is_current and status='current';
  if v_current is distinct from v_plan.expected_current_publication_id then
    return private.lca_release_error('expected_current_conflict',409,'Current publication changed; prepare a new exact plan');
  end if;
  select encode(extensions.digest(convert_to('tiangong.final-result-manager-precondition.v1'||E'\n'||r.user_id::text||E'\n'||
    coalesce(extract(epoch from r.created_at)::text,'')||E'\n'||coalesce(extract(epoch from r.modified_at)::text,'')||E'\n','UTF8'),'sha256'),'hex')
    into v_permission from private.roles r where r.user_id=auth.uid()
      and r.team_id='00000000-0000-0000-0000-000000000000' and r.role='data_product_manager';
  if v_permission is null then return private.lca_release_error('not_data_product_manager',403,'Live manager role is required'); end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('releaseRunId',v_run.id,'publishPlanHash',v_run.publish_plan_hash,
    'candidateHash',v_plan.candidate_hash,'targetHash',v_plan.target_hash,'selectionHash',v_run.selection_manifest_hash,
    'selectionCount',v_plan.selection_count,'runtimeRevision',v_runtime.id,'readerSha256',v_runtime.reader_sha256,
    'actorId',auth.uid(),'permissionHash',v_permission,
    'scope',jsonb_build_object('kind','readiness','releaseRunId',v_run.id,'selectionHash',v_run.selection_manifest_hash),
    'publicationAuthorized',false));
end;
$$;
revoke all on function private.final_result_release_probe_context(uuid,text) from public,anon,authenticated,service_role;

create function api.qry_final_result_release_probe_page_v2(p_release_run_id uuid,p_publish_plan_hash text,
  p_runtime_revision uuid default null,p_after_artifact_id uuid default null,p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_context jsonb:=private.final_result_release_probe_context(p_release_run_id,p_publish_plan_hash);
  v_ids uuid[]; v_id uuid; v_first text; v_last text; v_count bigint; v_ref jsonb; v_items jsonb:='[]'; v_probes jsonb;
begin
  if not coalesce((v_context->>'ok')::boolean,false) then return v_context; end if;
  if p_limit is null or p_limit not between 1 and 100 or (p_after_artifact_id is not null and p_runtime_revision is null) then
    raise exception using errcode='22023',message='Invalid bounded final Result probe page';
  end if;
  if p_runtime_revision is not null and p_runtime_revision::text is distinct from v_context#>>'{data,runtimeRevision}' then
    return private.lca_release_error('runtime_revision_conflict',409,'Runtime changed during verification; restart with the current revision');
  end if;
  select array_agg(artifact_id order by artifact_id) into v_ids from (
    select distinct artifact_id from private.final_result_release_members where release_run_id=p_release_run_id
      and (p_after_artifact_id is null or artifact_id>p_after_artifact_id) order by artifact_id limit p_limit+1
  ) ids;
  foreach v_id in array coalesce(v_ids[1:p_limit],array[]::uuid[]) loop
    select min((result_id::text||'@'||result_version) collate "C"),max((result_id::text||'@'||result_version) collate "C"),count(*)
      into v_first,v_last,v_count from private.final_result_release_members where release_run_id=p_release_run_id and artifact_id=v_id;
    select artifact_ref into strict v_ref from private.final_result_query_artifacts where id=v_id;
    v_probes:=jsonb_build_array(jsonb_build_object('uuid',split_part(v_first,'@',1),'version',split_part(v_first,'@',2)));
    if v_first<>v_last then v_probes:=v_probes||jsonb_build_array(jsonb_build_object('uuid',split_part(v_last,'@',1),'version',split_part(v_last,'@',2))); end if;
    v_items:=v_items||jsonb_build_array(jsonb_build_object('artifact',v_ref,'selectedResultCount',v_count,'probes',v_probes));
  end loop;
  return jsonb_build_object('ok',true,'data',(v_context->'data')||jsonb_build_object('artifacts',v_items,
    'nextArtifactCursor',case when cardinality(v_ids)>p_limit then v_ids[p_limit] else null end));
end;
$$;
create function api.qry_final_result_release_probe_v2(p_release_run_id uuid,p_publish_plan_hash text,p_runtime_revision uuid,
  p_result_id uuid,p_result_version text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_context jsonb:=private.final_result_release_probe_context(p_release_run_id,p_publish_plan_hash); v_data jsonb;
begin
  if not coalesce((v_context->>'ok')::boolean,false) then return v_context; end if;
  if p_runtime_revision::text is distinct from v_context#>>'{data,runtimeRevision}' then
    return private.lca_release_error('runtime_revision_conflict',409,'Exact admitted runtime revision is required');
  end if;
  if p_result_id is null or coalesce(p_result_version,'') !~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$' then
    raise exception using errcode='22023',message='Exact final Result probe identity is required';
  end if;
  select jsonb_build_object('artifact',a.artifact_ref,'result',jsonb_build_object('uuid',m.result_id,'version',m.result_version),
    'contentHash',q.content_hash,'lciAvailable',true,'lciaAvailable',a.impact_count>0) into v_data
    from private.final_result_release_members m join private.final_result_query_artifacts a on a.id=m.artifact_id
    join private.final_result_query_rows q on q.artifact_id=m.artifact_id and q.row_ordinal=m.row_ordinal
      and q.result_id=m.result_id and q.result_version=m.result_version
    join private.final_result_identities i on i.result_id=q.result_id and i.result_version=q.result_version
      and i.registration_id=q.registration_id and i.content_hash=q.content_hash and i.registration_kind='registered'
    where m.release_run_id=p_release_run_id and m.result_id=p_result_id and m.result_version=p_result_version;
  if v_data is null then return private.lca_release_error('final_result_probe_not_available',404,'Result is absent from the sealed publication selection'); end if;
  return jsonb_build_object('ok',true,'data',(v_context->'data')||v_data);
end;
$$;
revoke all on function api.svc_result_query_runtime_configure_v2(uuid,uuid,text,text,boolean,text),api.svc_result_query_runtime_read_v2(),
  api.qry_final_result_release_probe_page_v2(uuid,text,uuid,uuid,integer),api.qry_final_result_release_probe_v2(uuid,text,uuid,uuid,text)
  from public,anon,authenticated,service_role;
grant execute on function api.svc_result_query_runtime_configure_v2(uuid,uuid,text,text,boolean,text),api.svc_result_query_runtime_read_v2() to service_role;
grant execute on function api.qry_final_result_release_probe_page_v2(uuid,text,uuid,uuid,integer),api.qry_final_result_release_probe_v2(uuid,text,uuid,uuid,text) to authenticated;
insert into private.api_capability_grants(routine_identity,capability_id,allow_anon,allow_authenticated,allow_service_role) values
  ('api.svc_result_query_runtime_configure_v2(uuid, uuid, text, text, boolean, text)','EDGE-DATA-PRODUCT-01',false,false,true),
  ('api.svc_result_query_runtime_read_v2()','EDGE-DATA-PRODUCT-01',false,false,true),
  ('api.qry_final_result_release_probe_page_v2(uuid, text, uuid, uuid, integer)','EDGE-REL-01',false,true,false),
  ('api.qry_final_result_release_probe_v2(uuid, text, uuid, uuid, text)','EDGE-REL-01',false,true,false);
notify pgrst,'reload schema';
commit;
