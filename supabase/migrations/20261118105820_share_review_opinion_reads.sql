begin;

-- Add result columns while retaining the single callable signature and existing ACL.
drop function api.qry_review_get_items(uuid[], uuid, text, integer[]);

CREATE OR REPLACE FUNCTION "api"."qry_review_get_items"("p_review_ids" "uuid"[] DEFAULT NULL::"uuid"[], "p_data_id" "uuid" DEFAULT NULL::"uuid", "p_data_version" "text" DEFAULT NULL::"text", "p_state_codes" integer[] DEFAULT NULL::integer[]) RETURNS TABLE("id" "uuid", "data_id" "uuid", "data_version" "text", "state_code" integer, "reviewer_id" "jsonb", "json" "jsonb", "deadline" timestamp with time zone, "created_at" timestamp with time zone, "modified_at" timestamp with time zone, "target_table" "text", "submitted_revision_checksum" "text", "opinion_scope" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
    r.modified_at,
    coalesce(r.target_table, r.json->'data'->>'table'),
    r.submitted_revision_checksum,
    case
      when a.participant_access and api.cmd_review_is_review_admin(a.id) then 'admin'
      when a.participant_access and api.cmd_review_is_review_member(a.id)
        and (r.reviewer_id ? a.id::text or exists (
          select 1 from private.comments as c where c.review_id = r.id and c.reviewer_id = a.id
        )) then 'reviewer'
      else 'returned'
    end
  from private.reviews as r
  cross join actor as a
  where a.id is not null
    and (p_review_ids is null or r.id = any (p_review_ids))
    and (
      p_data_id is null
      or r.data_id = p_data_id
      or (r.data_id is null and r.json->'data'->>'id' = p_data_id::text)
    )
    and (
      p_data_version is null
      or r.data_version = p_data_version
      or (r.data_version is null and r.json->'data'->>'version' = p_data_version)
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
$$;

ALTER FUNCTION "api"."qry_review_get_items"("p_review_ids" "uuid"[], "p_data_id" "uuid", "p_data_version" "text", "p_state_codes" integer[]) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."qry_review_get_items"("p_review_ids" "uuid"[], "p_data_id" "uuid", "p_data_version" "text", "p_state_codes" integer[]) FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."qry_review_get_items"("p_review_ids" "uuid"[], "p_data_id" "uuid", "p_data_version" "text", "p_state_codes" integer[]) TO "api_internal_executor";

GRANT ALL ON FUNCTION "api"."qry_review_get_items"("p_review_ids" "uuid"[], "p_data_id" "uuid", "p_data_version" "text", "p_state_codes" integer[]) TO "authenticated";

CREATE OR REPLACE FUNCTION "api"."qry_review_get_comment_items"("p_review_id" "uuid", "p_scope" "text" DEFAULT 'auto'::"text") RETURNS TABLE("review_id" "uuid", "reviewer_id" "uuid", "state_code" integer, "json" "jsonb", "created_at" timestamp with time zone, "modified_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'api', 'private', 'public', 'util', 'extensions', 'pg_temp'
    AS $$
  with visible as materialized (
    select r.*, lower(coalesce(p_scope, 'auto')) as requested_scope,
      private.oauth_client_has_capability('NX-REV-01') as participant_access
    from api.qry_review_get_items(array[p_review_id]) as r
  ), scoped as (
    select r.*, case
      when requested_scope = 'returned' then 'returned'
      when requested_scope = 'opinions' then opinion_scope
      -- Existing participant scopes retain their established projection.
      when participant_access and requested_scope in ('all', 'auto', 'mine', 'self') then 'legacy'
    end as view_scope
    from visible as r
  )
  select c.review_id,
    case when r.view_scope <> 'returned' then c.reviewer_id end,
    c.state_code,
    case when r.view_scope = 'returned' then
      jsonb_build_object('modellingAndValidation', coalesce((
        select jsonb_object_agg(field.key, field.value)
        from jsonb_each(case when jsonb_typeof(c.json::jsonb->'modellingAndValidation') = 'object'
          then c.json::jsonb->'modellingAndValidation' else '{}'::jsonb end) as field
        where field.key in ('validation', 'complianceDeclarations')
      ), '{}'::jsonb))
    else coalesce(c.json::jsonb, '{}'::jsonb) end,
    c.created_at, c.modified_at
  from scoped as r
  join private.comments as c on c.review_id = r.id
  where case r.view_scope
    when 'returned' then r.target_table = 'processes' and r.state_code = -1 and c.state_code = -1
      and (r.json->'user'->>'id' = auth.uid()::text or r.opinion_scope = 'admin'
           or (r.opinion_scope = 'reviewer' and c.reviewer_id = auth.uid()))
    when 'admin' then true
    when 'reviewer' then c.reviewer_id = auth.uid()
    when 'legacy' then (r.opinion_scope = 'admin' or r.json->'user'->>'id' = auth.uid()::text
                        or c.reviewer_id = auth.uid())
      and (r.requested_scope not in ('mine', 'self') or c.reviewer_id = auth.uid())
    else false
  end
  order by c.created_at, c.reviewer_id
$$;

ALTER FUNCTION "api"."qry_review_get_comment_items"("p_review_id" "uuid", "p_scope" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."qry_review_get_comment_items"("p_review_id" "uuid", "p_scope" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."qry_review_get_comment_items"("p_review_id" "uuid", "p_scope" "text") TO "api_internal_executor";

GRANT ALL ON FUNCTION "api"."qry_review_get_comment_items"("p_review_id" "uuid", "p_scope" "text") TO "authenticated";

CREATE OR REPLACE FUNCTION "api"."oauth_client_pre_request"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
    elsif v_route_name = 'qry_review_get_comment_items' and v_capability_id = 'NX-REV-01' then
      v_legacy_review_capability := 'CLI-REVIEW-AUTHOR-01';
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
$$;

ALTER FUNCTION "api"."oauth_client_pre_request"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."oauth_client_pre_request"() FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."oauth_client_pre_request"() TO "anon";

GRANT ALL ON FUNCTION "api"."oauth_client_pre_request"() TO "authenticated";

GRANT ALL ON FUNCTION "api"."oauth_client_pre_request"() TO "service_role";

notify pgrst, 'reload schema';

commit;
