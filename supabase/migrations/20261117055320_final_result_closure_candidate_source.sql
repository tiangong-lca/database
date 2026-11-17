-- Database #977: Final Result publications do not supply calculation inputs.
-- Preserve deployed function identities, policies, timeouts and historical evidence.
begin;

do $migration$
declare
  v_definition text;
  v_old text;
  v_new text;
begin
  v_definition := pg_get_functiondef(
    'private.lcia_scope_closure_normalize_request(jsonb)'::regprocedure
  );
  v_old := $old$  select release_run_id
  into v_release_id
  from private.lca_release_publications
  where is_current = true and status = 'current'
  order by published_at desc
  limit 1;$old$;
  v_new := $new$  -- Final Result membership is an output selection. Only a legacy
  -- publication supplies the release-bound calculation input universe.
  select publication.release_run_id
  into v_release_id
  from private.lca_release_publications publication
  join private.lca_release_runs release on release.id = publication.release_run_id
  where publication.is_current = true and publication.status = 'current'
    and release.publication_format = 'legacy-four-zip.v1'
  order by publication.published_at desc
  limit 1;$new$;
  if (length(v_definition) - length(replace(v_definition, v_old, ''))) <> length(v_old) then
    raise exception 'scope_closure_normalize_source_definition_drift';
  end if;
  execute replace(v_definition, v_old, v_new);

  v_definition := pg_get_functiondef(
    'api.cmd_lcia_scope_closure_check_request_v2(jsonb,text,jsonb)'::regprocedure
  );
  v_old := $old$  v_scope := private.lcia_scope_closure_normalize_request(p_requested_scope);$old$;
  v_new := $new$  -- Admission can normalize more than once, then freeze the source.
  -- Hold the publication selector stable through all reads, including the
  -- no-current-publication case. Concurrent checks share this lock.
  lock table private.lca_release_publications in share mode;
  v_scope := private.lcia_scope_closure_normalize_request(p_requested_scope);$new$;
  if (length(v_definition) - length(replace(v_definition, v_old, ''))) <> length(v_old) then
    raise exception 'scope_closure_snapshot_source_definition_drift';
  end if;
  execute replace(v_definition, v_old, v_new);
end;
$migration$;

commit;
