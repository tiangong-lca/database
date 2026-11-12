begin;

-- Ordinary readers need only the active public release identity, not the
-- manager control-plane projection or the Candidate's dataset closure.
create function api.qry_current_final_result_publication()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
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

revoke all on function api.qry_current_final_result_publication() from public, anon, authenticated, service_role;
grant execute on function api.qry_current_final_result_publication() to authenticated;
insert into private.api_capability_grants(routine_identity, capability_id, allow_anon, allow_authenticated, allow_service_role)
values ('api.qry_current_final_result_publication()', 'DB-CORE-READ-01', false, true, false);

notify pgrst, 'reload schema';
commit;
