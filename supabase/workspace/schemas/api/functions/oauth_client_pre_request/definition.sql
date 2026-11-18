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
