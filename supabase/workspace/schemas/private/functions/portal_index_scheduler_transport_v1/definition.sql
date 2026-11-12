CREATE OR REPLACE FUNCTION "private"."portal_index_scheduler_transport_v1"() RETURNS TABLE("project_url" "text", "publishable_key" "text", "dispatch_secret" "text")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
begin
  select min(decrypted_secret) filter (where name = 'project_url'),
    min(decrypted_secret) filter (where name = 'portal_index_dispatch_publishable_key'),
    min(decrypted_secret) filter (where name = 'portal_index_dispatch_secret')
  into project_url, publishable_key, dispatch_secret
  from vault.decrypted_secrets
  where name in ('project_url', 'portal_index_dispatch_publishable_key', 'portal_index_dispatch_secret')
  having count(*) = 3 and count(distinct name) = 3;
  if project_url is null or project_url !~ '^https://[a-z0-9]{20}\.supabase\.co$'
    or publishable_key is null or publishable_key !~ '^sb_publishable_[A-Za-z0-9_-]{15,128}$'
    or dispatch_secret is null or dispatch_secret !~ '^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$' then
    raise object_not_in_prerequisite_state using message = 'Portal index scheduler transport is unconfigured';
  end if;
  return next;
end;
$_$;

ALTER FUNCTION "private"."portal_index_scheduler_transport_v1"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."portal_index_scheduler_transport_v1"() FROM PUBLIC;
