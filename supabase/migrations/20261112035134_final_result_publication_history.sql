begin;

create or replace function api.qry_final_result_download(p_publication_id uuid default null, p_format text default null)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_publication_id uuid;
  v_candidate text;
  v_target text;
  v_file jsonb;
begin
  if auth.uid() is null then
    return private.lca_release_error('auth_required', 401, 'Authentication required');
  end if;
  if p_format is null or p_format not in ('tidas', 'ilcd') then
    raise exception using errcode = '22023', message = 'Supported archive format is required';
  end if;

  select p.id, plan.candidate_hash, plan.target_hash, file.value
    into v_publication_id, v_candidate, v_target, v_file
  from private.lca_release_publications p
  join private.final_result_publication_bindings binding on binding.publication_id = p.id
  join private.final_result_release_plans plan on plan.release_run_id = p.release_run_id
  join private.final_result_release_selection_seals seal on seal.release_run_id = plan.release_run_id
  join private.final_result_candidates candidate on candidate.candidate_hash = plan.candidate_hash
    and candidate.result_count = plan.selection_count
  join private.final_result_candidate_storage storage on storage.candidate_hash = plan.candidate_hash
    and storage.target_hash = plan.target_hash
  cross join lateral jsonb_array_elements(storage.receipt->'files') file
  where ((p_publication_id is null and p.is_current and p.status = 'current')
      or (p_publication_id is not null and p.id = p_publication_id and p.status in ('current','superseded')))
    and p.publication_series_key = 'global' and p.publication_channel = 'public' and p.visibility_scope = 'public'
    and file.value->>'name' = 'result.' || p_format || '.7z';

  if not found then
    return private.lca_release_error('result_package_not_available', 404, 'No complete prebuilt archive is available for this publication');
  end if;
  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'publicationId', v_publication_id, 'candidateHash', v_candidate,
    'targetHash', v_target, 'file', v_file));
end;
$$;


-- Stable time/id cursor; summaries never scan the dataset closure.
create index final_result_publication_history_idx
  on private.lca_release_publications (published_at desc, id desc)
  where not is_current;
create function api.qry_final_result_publication_history(
  p_limit integer default 20, p_before_published_at timestamptz default null, p_before_id uuid default null
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_items jsonb; v_next jsonb;
begin
  if auth.uid() is null then
    return private.lca_release_error('auth_required',401,'Authentication required');
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 50
    or ((p_before_id is null) <> (p_before_published_at is null))
    or (p_before_published_at is not null and not isfinite(p_before_published_at)) then
    raise exception using errcode='22023',message='Invalid publication history page';
  end if;
  with entries as materialized (
    select p.id,p.release_version,p.published_at,p.status
    from private.lca_release_publications p
    join private.lca_release_runs r on r.id=p.release_run_id
    join private.final_result_publication_bindings b on b.publication_id=p.id
    where not p.is_current and p.status in ('superseded','unpublished')
      and p.publication_series_key='global' and p.publication_channel='public' and p.visibility_scope='public'
      and r.publication_format='final-result-pair.v2'
      and (p_before_id is null or (p.published_at,p.id)<(p_before_published_at,p_before_id))
    order by p.published_at desc,p.id desc limit p_limit+1
  ), page as (select * from entries order by published_at desc,id desc limit p_limit)
  select coalesce((select jsonb_agg(jsonb_build_object(
    'publicationId',id,'releaseVersion',release_version,'publishedAt',published_at,'status',status,
    'formats',case when status='unpublished' then '[]'::jsonb else
      (select coalesce(jsonb_agg(fmt order by fmt),'[]'::jsonb) from unnest(array['tidas','ilcd']) fmt
       where api.qry_final_result_download(id,fmt)->>'ok'='true') end
  ) order by published_at desc,id desc) from page),'[]'::jsonb),
  case when (select count(*) from entries)>p_limit then
    (select jsonb_build_object('publishedAt',published_at,'publicationId',id) from page order by published_at,id limit 1)
  else null end into v_items,v_next;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('publications',v_items,'nextCursor',v_next));
end;
$$;
revoke all on function api.qry_final_result_publication_history(integer,timestamptz,uuid) from public,anon,authenticated,service_role;
grant execute on function api.qry_final_result_publication_history(integer,timestamptz,uuid) to authenticated;
insert into private.api_capability_grants(routine_identity,capability_id,allow_anon,allow_authenticated,allow_service_role)
values ('api.qry_final_result_publication_history(integer, timestamp with time zone, uuid)','DB-CORE-READ-01',false,true,false);

CREATE OR REPLACE FUNCTION api.cmd_lca_release_unpublish(p_publication_id uuid, p_reason text, p_audit jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'api', 'private', 'public', 'util', 'extensions', 'pg_temp'
AS $function$
declare
  v_actor uuid := auth.uid();
  v_publication private.lca_release_publications%rowtype;
  v_now timestamptz := clock_timestamp();
begin
  if v_actor is null then
    return private.lca_release_error('auth_required', 401, 'Authentication required');
  end if;
  if not private.lca_release_is_manager() then
    return private.lca_release_error('not_data_product_manager', 403, 'Data product manager role is required');
  end if;
  if nullif(trim(coalesce(p_reason, '')), '') is null then
    return private.lca_release_error('reason_required', 400, 'Unpublish requires an audit reason');
  end if;

  select * into v_publication
  from private.lca_release_publications
  where id = p_publication_id
  for update;

  if v_publication.id is null then
    return private.lca_release_error('publication_not_found', 404, 'Publication not found');
  end if;
  if v_publication.status = 'unpublished' then
    return jsonb_build_object(
      'ok', true,
      'reused', true,
      'data', jsonb_build_object('publicationId', v_publication.id, 'status', 'unpublished')
    );
  end if;
  if not ((v_publication.is_current and v_publication.status = 'current') or
    (v_publication.status = 'superseded' and exists(select 1 from private.final_result_publication_bindings where publication_id=v_publication.id))) then
    return private.lca_release_error('publication_not_current', 409, 'Publication cannot be withdrawn');
  end if;

  update private.lca_release_publications
  set status = 'unpublished', is_current = false, unpublished_by = v_actor,
      unpublished_at = v_now, reason = p_reason, updated_at = v_now
  where id = v_publication.id;

  update private.lca_release_runs
  set status = 'unpublished', updated_at = v_now
  where id = v_publication.release_run_id;

  insert into private.command_audit_log (
    command, actor_user_id, target_table, target_id, target_version, payload
  ) values (
    'cmd_lca_release_unpublish', v_actor, 'lca_release_publications',
    v_publication.id, v_publication.release_version,
    coalesce(p_audit, '{}'::jsonb) || jsonb_build_object('reason', p_reason)
  );

  return jsonb_build_object(
    'ok', true,
    'reused', false,
    'data', jsonb_build_object('publicationId', v_publication.id, 'status', 'unpublished')
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.lca_release_guard_publication_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'private', 'api', 'public', 'util', 'extensions', 'pg_temp'
AS $function$
begin
  if old.id is distinct from new.id
     or old.release_run_id is distinct from new.release_run_id
     or old.release_version is distinct from new.release_version
     or old.publication_series_key is distinct from new.publication_series_key
     or old.publication_channel is distinct from new.publication_channel
     or old.visibility_scope is distinct from new.visibility_scope
     or old.approval_id is distinct from new.approval_id
     or old.approval_hash is distinct from new.approval_hash
     or old.publish_plan_hash is distinct from new.publish_plan_hash
     or old.release_manifest_hash is distinct from new.release_manifest_hash
     or old.artifact_set_hash is distinct from new.artifact_set_hash
     or old.approved_by is distinct from new.approved_by
     or old.executed_by is distinct from new.executed_by
     or old.credential_fingerprint is distinct from new.credential_fingerprint
     or old.idempotency_key is distinct from new.idempotency_key
     or old.published_at is distinct from new.published_at
     or old.created_at is distinct from new.created_at
     or (not old.is_current and new.is_current)
     or (old.status <> 'current' and old.status is distinct from new.status
       and not (old.status='superseded' and new.status='unpublished' and exists
         (select 1 from private.final_result_publication_bindings where publication_id=old.id)))
     or (old.status = 'current' and new.status not in ('current', 'superseded', 'unpublished')) then
    raise exception 'lca_release_publication_immutable'
      using errcode = '23514';
  end if;
  new.updated_at := now();
  return new;
end;
$function$;


notify pgrst, 'reload schema';
commit;
