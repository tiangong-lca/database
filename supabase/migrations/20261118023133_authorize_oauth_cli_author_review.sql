begin;

-- Verify the exact existing authenticated signatures before remapping them.
do $routes$
begin
  update private.api_capability_grants as manifest
  set capability_id = 'CLI-REVIEW-AUTHOR-01'
  where (
    (pg_catalog.to_regprocedure(manifest.routine_identity) =
      'api.cmd_review_submit(text,uuid,text,jsonb)'::regprocedure
      and manifest.capability_id = 'NX-CMD-01')
    or (pg_catalog.to_regprocedure(manifest.routine_identity) =
      'api.qry_review_get_items(uuid[],uuid,text,integer[])'::regprocedure
      and manifest.capability_id = 'NX-REV-01')
  )
  and manifest.allow_authenticated
  and not manifest.allow_anon
  and not manifest.allow_service_role;

  if (
    select array_agg(manifest.routine_identity::regprocedure::oid order by manifest.routine_identity::regprocedure::oid)
    from private.api_capability_grants as manifest
    where manifest.capability_id = 'CLI-REVIEW-AUTHOR-01'
  ) is distinct from (
    select array_agg(route order by route)
    from unnest(array[
      'api.cmd_review_submit(text,uuid,text,jsonb)'::regprocedure::oid,
      'api.qry_review_get_items(uuid[],uuid,text,integer[])'::regprocedure::oid
    ]) as routes(route)
  ) then
    raise exception 'Issue #984 author review capability must map exactly the two authenticated routes';
  end if;
end;
$routes$;

create or replace function api.oauth_client_pre_request()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_claims jsonb := coalesce(
    nullif(pg_catalog.current_setting('request.jwt.claims', true), '')::jsonb,
    '{}'::jsonb
  );
  v_client_id text := nullif(pg_catalog.btrim(coalesce(v_claims ->> 'client_id', '')), '');
  v_headers jsonb := coalesce(
    nullif(pg_catalog.current_setting('request.headers', true), '')::jsonb,
    '{}'::jsonb
  );
  v_method text := upper(coalesce(
    nullif(pg_catalog.current_setting('request.method', true), ''),
    'GET'
  ));
  v_path text := coalesce(
    nullif(pg_catalog.current_setting('request.path', true), ''),
    '/'
  );
  v_profile text;
  v_route_name text;
  v_command text;
  v_capability_id text;
  v_capability_count integer;
  v_legacy_review_capability text;
begin
  if v_client_id is null then
    return;
  end if;

  if v_path like '/rpc/%' then
    v_route_name := split_part(v_path, '/', 3);

    select
      min(manifest.capability_id),
      count(distinct manifest.capability_id)::integer
    into v_capability_id, v_capability_count
    from private.api_capability_grants as manifest
    join pg_catalog.pg_proc as routine
      on routine.oid = pg_catalog.to_regprocedure(manifest.routine_identity)
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = routine.pronamespace
    where namespace.nspname = 'api'
      and routine.proname = v_route_name
      and manifest.allow_authenticated;

    -- Preserve admission for clients explicitly granted the previous capability
    -- on either exact route. The author grant cannot stand in for either group.
    if v_capability_id = 'CLI-REVIEW-AUTHOR-01' then
      v_legacy_review_capability := case v_route_name
        when 'cmd_review_submit' then 'NX-CMD-01'
        when 'qry_review_get_items' then 'NX-REV-01'
      end;
    end if;
  else
    v_profile := coalesce(
      case
        when v_method in ('GET', 'HEAD') then v_headers ->> 'accept-profile'
        else v_headers ->> 'content-profile'
      end,
      v_headers ->> 'accept-profile',
      'public'
    );
    v_route_name := ltrim(v_path, '/');
    v_command := case v_method
      when 'GET' then 'select'
      when 'HEAD' then 'select'
      when 'POST' then 'insert'
      when 'PUT' then 'update'
      when 'PATCH' then 'update'
      when 'DELETE' then 'delete'
      else null
    end;

    select relation_grant.capability_id, 1
    into v_capability_id, v_capability_count
    from private.oauth_relation_capability_grants as relation_grant
    where relation_grant.relation_schema = v_profile
      and relation_grant.relation_name = v_route_name
      and relation_grant.command = v_command;
  end if;

  if coalesce(v_capability_count, 0) <> 1
     or not (
       private.oauth_client_has_capability(v_capability_id)
       or private.oauth_client_has_capability(v_legacy_review_capability)
     ) then
    raise insufficient_privilege using
      message = 'OAuth client is not authorized for this API route';
  end if;
end;
$function$;

-- Preserve the public signature for existing CLI installations. The new
-- capability takes the author projection inside the RPC, before PostgREST
-- filters/counts/pages the result. Existing participant authorization and
-- projections still require the original review-read grant or first-party auth.
create or replace function api.qry_review_get_items(
  p_review_ids uuid[] default null,
  p_data_id uuid default null,
  p_data_version text default null,
  p_state_codes integer[] default null
)
returns table (
  id uuid,
  data_id uuid,
  data_version text,
  state_code integer,
  reviewer_id jsonb,
  "json" jsonb,
  deadline timestamptz,
  created_at timestamptz,
  modified_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $function$
  with actor as materialized (
    select
      auth.uid() as id,
      private.oauth_client_has_capability('NX-REV-01') as participant_access,
      private.oauth_client_has_capability('CLI-REVIEW-AUTHOR-01') as author_access
  )
  select
    r.id,
    r.data_id,
    r.data_version::text,
    r.state_code,
    case when a.participant_access then coalesce(r.reviewer_id, '[]'::jsonb) else '[]'::jsonb end,
    case when a.participant_access then coalesce(r.json, '{}'::jsonb) else
      jsonb_strip_nulls(jsonb_build_object(
        'review_kind', r.review_kind,
        'data', jsonb_build_object(
          'id', r.data_id,
          'version', r.data_version::text,
          'table', coalesce(r.target_table, r.json->'data'->>'table'),
          'name', r.json->'data'->'name'
        ),
        'user', jsonb_build_object('id', a.id),
        'comment', case when r.state_code = -1 then
          jsonb_build_object('message', private.review_rejection_reason_v1(r.json))
        end
      ))
    end,
    case when a.participant_access then r.deadline end,
    r.created_at,
    r.modified_at
  from private.reviews as r
  cross join actor as a
  where a.id is not null
    and (p_review_ids is null or r.id = any (p_review_ids))
    and (
      p_data_id is null
      or r.data_id = p_data_id
      or coalesce(r.json -> 'data' ->> 'id', '') = p_data_id::text
    )
    and (
      p_data_version is null
      or r.data_version = p_data_version
      or coalesce(r.json -> 'data' ->> 'version', '') = p_data_version
    )
    and (p_state_codes is null or r.state_code = any (p_state_codes))
    and (
      a.participant_access
      or (
        a.author_access
        and r.json->'user'->>'id' = a.id::text
        and (r.target_owner_id is null or r.target_owner_id = a.id)
        and (
          r.review_kind = 'root'
          or r.review_kind is null -- Historical author records predate the root/reference split.
          or (
            r.review_kind = 'reference'
            and exists (
              -- A reference can be created by another root submitter. Count it
              -- as the owner's submission only when that owner submitted it.
              select 1
              from private.command_audit_log as submission
              where submission.command = 'cmd_review_submit'
                and submission.actor_user_id = a.id
                and submission.target_table = r.target_table
                and submission.target_id = r.data_id
                and submission.target_version = r.data_version::text
                and submission.payload->>'review_id' = r.id::text
            )
          )
        )
      )
    )
    and api.policy_review_can_read(r.id, a.id)
  order by r.modified_at desc, r.id desc;
$function$;

-- Environment-specific Auth client IDs are runtime state. Select only the
-- unique existing official CLI class, as in #677, and keep Preview/local
-- installations without a registered client valid.
do $grant$
declare
  v_before constant text[] := array[
    'CLI-ALIAS-02', 'CLI-RPC-01', 'DB-CORE-READ-01', 'DB-CORE-WRITE-01',
    'EDGE-BUNDLE-01', 'NX-CORE-02'
  ];
  v_after constant text[] := array[
    'CLI-ALIAS-02', 'CLI-REVIEW-AUTHOR-01', 'CLI-RPC-01', 'DB-CORE-READ-01',
    'DB-CORE-WRITE-01', 'EDGE-BUNDLE-01', 'NX-CORE-02'
  ];
  v_matches text[];
  v_client_id text;
  v_audit_before bigint;
  v_result jsonb;
begin
  lock table private.oauth_client_registry in share row exclusive mode;

  select array_agg(client.client_id)
  into v_matches
  from private.oauth_client_registry as client
  where client.client_kind = 'cli' and client.enabled
    and (
      select array_agg(grant_row.capability_id order by grant_row.capability_id)
      from private.oauth_client_capability_grants as grant_row
      where grant_row.client_id = client.client_id and grant_row.allowed
    ) = v_before;

  if v_matches is null then
    return;
  end if;
  if cardinality(v_matches) <> 1 then
    raise exception 'Issue #984 expected at most one enabled official CLI capability class';
  end if;

  v_client_id := v_matches[1];
  select coalesce(max(id), 0) into v_audit_before
  from private.oauth_client_registry_audit
  where client_id = v_client_id;

  v_result := api.svc_oauth_client_configure(v_client_id, 'cli', true, v_after);

  if (v_result #> '{data,capabilities}') is distinct from to_jsonb(v_after)
     or (
       select array_agg(grant_row.capability_id order by grant_row.capability_id)
       from private.oauth_client_capability_grants as grant_row
       where grant_row.client_id = v_client_id and grant_row.allowed
     ) is distinct from v_after
     or (
       select count(*)
       from private.oauth_client_registry_audit as audit
       where audit.client_id = v_client_id
         and audit.id > v_audit_before
         and audit.action = 'replace'
         and audit.before_state -> 'capabilities' = to_jsonb(v_before)
         and audit.after_state -> 'capabilities' = to_jsonb(v_after)
     ) <> 1 then
    raise exception 'Issue #984 CLI capability repair did not record the exact grant and audit';
  end if;
end;
$grant$;

commit;
