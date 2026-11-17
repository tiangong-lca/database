CREATE OR REPLACE FUNCTION "private"."lcia_scope_closure_normalize_request"("p_requested_scope" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'private', 'api', 'public', 'util', 'extensions', 'pg_temp'
    AS $$
declare
  v_mode text := lower(trim(coalesce(p_requested_scope->>'coverageMode', '')));
  v_processes jsonb;
  v_methods jsonb;
  v_policy jsonb;
  v_freshness text;
  v_release_id uuid;
  v_count integer;
  v_requested integer;
  v_duplicate integer;
  v_predicate text;
begin
  if jsonb_typeof(coalesce(p_requested_scope, 'null'::jsonb)) <> 'object'
     or v_mode not in ('subset', 'global_eligible') then
    raise exception using errcode = '22023', message = 'invalid_closure_scope';
  end if;
  if jsonb_typeof(coalesce(p_requested_scope->'processes', '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_requested_scope->'lciaMethods', '[]'::jsonb)) <> 'array' then
    raise exception using errcode = '22023', message = 'invalid_closure_scope_identity_list';
  end if;

  -- Final Result membership is an output selection. Only a legacy
  -- publication supplies the release-bound calculation input universe.
  select publication.release_run_id
  into v_release_id
  from private.lca_release_publications publication
  join private.lca_release_runs release on release.id = publication.release_run_id
  where publication.is_current = true and publication.status = 'current'
    and release.publication_format = 'legacy-four-zip.v1'
  order by publication.published_at desc
  limit 1;

  if v_release_id is not null then
    v_predicate := 'current-public-release-manifest:v2';
    if v_mode = 'global_eligible' then
      if jsonb_array_length(coalesce(p_requested_scope->'processes', '[]'::jsonb)) <> 0 then
        raise exception using errcode = '22023', message = 'global_eligible_scope_must_not_supply_processes';
      end if;
      select coalesce(jsonb_agg(
        jsonb_build_object('id', dataset_uuid, 'version', dataset_version)
        order by dataset_uuid, dataset_version
      ), '[]'::jsonb)
      into v_processes
      from private.lca_release_dataset_versions
      where release_run_id = v_release_id
        and dataset_type = 'process'
        and dataset_role = 'unit_process';
      if jsonb_array_length(v_processes) = 0 then
        raise exception using errcode = '22023', message = 'current_release_has_no_eligible_processes';
      end if;
    else
      with requested as (
        select (item.value->>'id')::uuid as id,
          btrim(item.value->>'version') as version
        from jsonb_array_elements(p_requested_scope->'processes') item(value)
      ),
      resolved as (
        select r.id, r.version
        from requested r
        join private.lca_release_dataset_versions d
          on d.release_run_id = v_release_id
         and d.dataset_type = 'process'
         and d.dataset_role = 'unit_process'
         and d.dataset_uuid = r.id
         and d.dataset_version = r.version
      )
      select count(*), (select count(*) from requested),
        (select count(*) - count(distinct (id, version)) from requested),
        coalesce(jsonb_agg(
          jsonb_build_object('id', id, 'version', version) order by id, version
        ), '[]'::jsonb)
      into v_count, v_requested, v_duplicate, v_processes
      from resolved;
      if coalesce(v_requested, 0) = 0 or v_count <> v_requested or v_duplicate <> 0 then
        raise exception using errcode = '22023', message = 'process_not_in_current_public_release';
      end if;
    end if;

    with requested as (
      select (item.value->>'id')::uuid as id,
        btrim(item.value->>'version') as version
      from jsonb_array_elements(p_requested_scope->'lciaMethods') item(value)
    ),
    resolved as (
      select r.id, r.version
      from requested r
      join private.lca_release_dataset_versions d
        on d.release_run_id = v_release_id
       and d.dataset_type = 'lciamethod'
       and d.dataset_uuid = r.id
       and d.dataset_version = r.version
    )
    select count(*), (select count(*) from requested),
      (select count(*) - count(distinct (id, version)) from requested),
      coalesce(jsonb_agg(
        jsonb_build_object('id', id, 'version', version) order by id, version
      ), '[]'::jsonb)
    into v_count, v_requested, v_duplicate, v_methods
    from resolved;
    if coalesce(v_requested, 0) = 0 or v_count <> v_requested or v_duplicate <> 0 then
      raise exception using errcode = '22023', message = 'lcia_method_not_in_current_public_release';
    end if;
  else
    v_predicate := 'candidate-public-state-code-100:v2';
    if v_mode = 'global_eligible' then
      if jsonb_array_length(coalesce(p_requested_scope->'processes', '[]'::jsonb)) <> 0 then
        raise exception using errcode = '22023', message = 'global_eligible_scope_must_not_supply_processes';
      end if;
      with ranked as (
        select p.id, btrim(p.version::text) as version,
          row_number() over (
            partition by p.id
            order by btrim(p.version::text) desc, p.modified_at desc nulls last
          ) as rank
        from public.processes p
        where p.state_code = 100
          and p.json_ordered is not null
      )
      select coalesce(jsonb_agg(
        jsonb_build_object('id', id, 'version', version) order by id, version
      ), '[]'::jsonb)
      into v_processes
      from ranked
      where rank = 1;
      if jsonb_array_length(v_processes) = 0 then
        raise exception using errcode = '22023', message = 'candidate_scope_has_no_eligible_processes';
      end if;
    else
      with requested as (
        select (item.value->>'id')::uuid as id,
          btrim(item.value->>'version') as version
        from jsonb_array_elements(p_requested_scope->'processes') item(value)
      ),
      resolved as (
        select r.id, r.version
        from requested r
        join public.processes p
          on p.id = r.id
         and btrim(p.version::text) = r.version
         and p.state_code = 100
         and p.json_ordered is not null
      )
      select count(*), (select count(*) from requested),
        (select count(*) - count(distinct (id, version)) from requested),
        coalesce(jsonb_agg(
          jsonb_build_object('id', id, 'version', version) order by id, version
        ), '[]'::jsonb)
      into v_count, v_requested, v_duplicate, v_processes
      from resolved;
      if coalesce(v_requested, 0) = 0 or v_count <> v_requested or v_duplicate <> 0 then
        raise exception using errcode = '22023', message = 'invalid_or_ineligible_process_selection';
      end if;
    end if;

    with requested as (
      select (item.value->>'id')::uuid as id,
        btrim(item.value->>'version') as version
      from jsonb_array_elements(p_requested_scope->'lciaMethods') item(value)
    ),
    eligible_methods as (
      select reviewed.method_id as id,
        reviewed.method_version as version
      from public.lciamethods m
      join private.lcia_scope_closure_reviewed_lcia_methods reviewed
        on reviewed.artifact_locator_id = m.id
       and reviewed.method_version = btrim(m.version::text)
      where coalesce(m.json, m.json_ordered::jsonb) is not null
    ),
    resolved as (
      select r.id, r.version
      from requested r
      join eligible_methods m using (id, version)
    )
    select count(*), (select count(*) from requested),
      (select count(*) - count(distinct (id, version)) from requested),
      coalesce(jsonb_agg(
        jsonb_build_object('id', id, 'version', version) order by id, version
      ), '[]'::jsonb)
    into v_count, v_requested, v_duplicate, v_methods
    from resolved;
    if coalesce(v_requested, 0) = 0 or v_count <> v_requested or v_duplicate <> 0 then
      raise exception using errcode = '22023', message = 'invalid_lcia_method_selection';
    end if;
  end if;

  v_freshness := coalesce(
    nullif(trim(p_requested_scope->>'certificateFreshnessPolicy'), ''),
    'frozen-artifact-reusable-v1'
  );
  if v_freshness not in (
    'frozen-artifact-reusable-v1',
    'current-membership-required-v1'
  ) then
    raise exception using errcode = '22023', message = 'invalid_certificate_freshness_policy';
  end if;

  v_policy := coalesce(p_requested_scope->'linkPolicy', '{}'::jsonb);
  if jsonb_typeof(v_policy) <> 'object'
     or coalesce(v_policy->>'linkSemanticsVersion', 'signed-flow-balance-v1') <> 'signed-flow-balance-v1'
     or coalesce(v_policy->>'flowIdentityPolicy', 'exact-flow-version-reference-unit-v2') <> 'exact-flow-version-reference-unit-v2'
     or coalesce(v_policy->>'allocationSemanticsVersion', 'tidas-reference-allocation-v5') <> 'tidas-reference-allocation-v5'
     or coalesce(v_policy->>'technosphereBoundaryPolicy', 'cutoff') not in ('closed', 'open', 'cutoff')
     or coalesce(v_policy->>'providerUniversePolicy', 'scope_only') not in ('scope_only', 'eligible_transitive_expansion-v1') then
    raise exception using errcode = '22023', message = 'invalid_closure_link_policy';
  end if;

  return jsonb_build_object(
    'schemaVersion', 'lcia.scope-manifest.v1',
    'coverageMode', v_mode,
    'eligibilityPredicateVersion', v_predicate,
    'processes', v_processes,
    'lciaMethods', v_methods,
    'versionResolutionPolicy', 'reference-version-resolution-v1',
    'legacyOmittedVersionPolicy', 'reject',
    'certificateFreshnessPolicy', v_freshness,
    'linkPolicy', jsonb_build_object(
      'linkSemanticsVersion', 'signed-flow-balance-v1',
      'flowIdentityPolicy', 'exact-flow-version-reference-unit-v2',
      'allocationSemanticsVersion', 'tidas-reference-allocation-v5',
      'technosphereBoundaryPolicy', 'cutoff',
      'providerUniversePolicy',
        coalesce(v_policy->>'providerUniversePolicy', 'scope_only')
    ),
    'processManifestHash',
      private.lcia_scope_closure_sha256(jsonb_build_object('processes', v_processes))
  );
exception
  when invalid_text_representation then
    raise exception using errcode = '22023', message = 'invalid_scope_identity';
end;
$$;

ALTER FUNCTION "private"."lcia_scope_closure_normalize_request"("p_requested_scope" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."lcia_scope_closure_normalize_request"("p_requested_scope" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."lcia_scope_closure_normalize_request"("p_requested_scope" "jsonb") TO "service_role";

GRANT ALL ON FUNCTION "private"."lcia_scope_closure_normalize_request"("p_requested_scope" "jsonb") TO "api_internal_executor";
