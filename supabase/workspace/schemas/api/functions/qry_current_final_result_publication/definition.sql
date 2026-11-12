CREATE OR REPLACE FUNCTION "api"."qry_current_final_result_publication"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_publication jsonb;
begin
  if auth.uid() is null then
    return private.lca_release_error('auth_required', 401, 'Authentication required');
  end if;
  select jsonb_build_object(
    'publicationId', p.id,
    'releaseVersion', p.release_version,
    'format', r.publication_format
  ) into v_publication
  from private.lca_release_publications p
  join private.lca_release_runs r on r.id = p.release_run_id
  join private.final_result_publication_bindings binding on binding.publication_id = p.id
  where p.is_current and p.status = 'current'
    and p.publication_series_key = 'global'
    and p.publication_channel = 'public'
    and p.visibility_scope = 'public'
    and r.publication_format = 'final-result-pair.v2';

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('publication', v_publication));
end;
$$;

ALTER FUNCTION "api"."qry_current_final_result_publication"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."qry_current_final_result_publication"() FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."qry_current_final_result_publication"() TO "authenticated";
