-- Database #949: preserve all filter keys while bounding selective scope work.
begin;
select private.portal_display_assert_contract_v1();

CREATE OR REPLACE FUNCTION private.display_navigation_scoped_filter_keys_v1(p_kind text,p_filters jsonb)
RETURNS TABLE(dataset_kind text,id uuid,version text)
LANGUAGE plpgsql STABLE SECURITY DEFINER PARALLEL RESTRICTED
SET search_path TO ''
SET row_security TO 'on'
SET plan_cache_mode TO 'force_custom_plan'
AS $filter_keys$
begin
  if p_kind is null or p_kind not in ('all','process','flow') then
    raise exception using errcode='22023',message='invalid portal request';
  end if;
  -- The closed owner bridge filters synchronized native facts first, then
  -- intersects EVERY exact version with the authoritative current scope view.
  -- Membership rows refer to the same exact key; their visibility is checked
  -- by that final intersection. No card, raw source or authorization cache.
  -- 2048 selects indexed probes versus a bulk intersection, never a row cap.
  -- Preserve the exact text check; unbounded bpchar equality additionally lets
  -- the existing character(9) settings index qualify the version component.
  -- Keep the requested kind explicit so bulk scope work excludes other kinds.
  return query
  with matches as materialized (
select v.dataset_kind,v.id,v.version
    from private.display_navigation_versions_v1 v
    where (p_kind='all' or v.dataset_kind=p_kind) and
      (not (p_filters ? 'accessLevel') or v.access_level=p_filters->>'accessLevel')
      and (not (p_filters ? 'geography') or v.geography_code=p_filters->>'geography')
      and (not (p_filters ? 'classification') or v.classification_codes @> array[p_filters->>'classification'])
      and (not (p_filters ? 'referenceYearFrom') or v.reference_year >= (p_filters->>'referenceYearFrom')::integer)
      and (not (p_filters ? 'referenceYearTo') or v.reference_year <= (p_filters->>'referenceYearTo')::integer)
      and (not (p_filters ? 'processSubtype') or v.process_subtype=p_filters->>'processSubtype')
      and (not (p_filters ? 'source') or v.source=p_filters->>'source')
      and (
        not (p_filters ? 'classificationNodeId')
        or (v.dataset_kind,v.id,v.version) in (
          select m.dataset_kind,m.id,m.version
          from private.display_navigation_membership_v1 m
          where m.dimension='classification'
            and m.node_id=p_filters->>'classificationNodeId'
            and (p_kind='all' or m.dataset_kind=p_kind)
            and (coalesce(p_filters->>'classificationScope','subtree')<>'direct' or m.direct)
        )
      ) and (
        not (p_filters ? 'geographyNodeId')
        or (v.dataset_kind,v.id,v.version) in (
          select m.dataset_kind,m.id,m.version
          from private.display_navigation_membership_v1 m
          where m.dimension='geography'
            and m.node_id=p_filters->>'geographyNodeId'
            and (p_kind='all' or m.dataset_kind=p_kind)
            and (coalesce(p_filters->>'geographyScope','subtree')<>'direct' or m.direct)
        )
      )

  ), match_count as materialized (select count(*) as n from matches)
  select matched.dataset_kind,matched.id,matched.version
  from matches matched
  where (select n from match_count)<=2048
    and exists (
      select 1 from private.display_request_visible_settings_v1 scope
      where (p_kind='all' or scope.dataset_kind=p_kind)
        and scope.dataset_kind=matched.dataset_kind and scope.dataset_id=matched.id
        and scope.dataset_version=matched.version::pg_catalog.bpchar
        and scope.dataset_version::text=matched.version
      offset 0
    )
  union all
  select matched.dataset_kind,matched.id,matched.version
  from matches matched
  where (select n from match_count)>2048
    and exists (
      select 1 from private.display_request_visible_settings_v1 scope
      where (p_kind='all' or scope.dataset_kind=p_kind)
        and scope.dataset_kind=matched.dataset_kind and scope.dataset_id=matched.id
        and scope.dataset_version=matched.version::pg_catalog.bpchar
        and scope.dataset_version::text=matched.version
    );
end;
$filter_keys$;
ALTER FUNCTION private.display_navigation_scoped_filter_keys_v1(text,jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.display_navigation_scoped_filter_keys_v1(text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.display_navigation_scoped_filter_keys_v1(text,jsonb) TO portal_display_executor;

CREATE OR REPLACE FUNCTION "private"."display_navigation_matched_versions_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb") RETURNS TABLE("dataset_kind" "text", "id" "uuid", "version" "text")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER PARALLEL RESTRICTED
    SET "search_path" TO ''
    SET "row_security" TO 'on'
    SET "plan_cache_mode" TO 'force_custom_plan'
    AS $_$
declare
  v_exact uuid;
  v_pattern text;
begin
  if p_query='' then
    -- The shared query-free filter set is also used by filtered lexical Search.
    -- Its closed bridge avoids hashing the whole scope for a selective filter.
    return query select * from private.display_navigation_scoped_filter_keys_v1(p_kind,p_filters);
  else
    if p_query ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then v_exact:=p_query::uuid; end if;
    v_pattern := '%' || replace(replace(replace(p_query,chr(92),chr(92)||chr(92)),'%',chr(92)||'%'),'_',chr(92)||'_') || '%';
    -- Native CAS text equality stays indexable under the unchanged forced RLS.
    -- Its guarded fact is synchronized by the existing navigation writer.
    -- Preserve Process lexical candidates and every original navigation filter.
    -- display-flow-cas-native-v1
    if private.display_catalog_summary_valid_cas_v1(p_query) then
      -- These are ordinary catalog SELECTs in this STABLE call's data snapshot,
      -- not a current-cache to_regclass readiness test. A call begun before B
      -- cannot see B's index catalog rows or backfilled facts, even when a late
      -- inner call resolves this new function body. Keep its original reader.
      if not exists (
        select 1
        from pg_catalog.pg_class idx
        join pg_catalog.pg_namespace ns on ns.oid=idx.relnamespace
        join pg_catalog.pg_index i on i.indexrelid=idx.oid
        where ns.nspname='private'
          and idx.relname='d807_portal_navigation_versions_flow_cas_v1_idx'
          and i.indrelid='private.display_navigation_versions_v1'::regclass
          and i.indisvalid and i.indisready and i.indislive
      ) then
    return query select v.dataset_kind,v.id,v.version
    from private.display_catalog_facet_candidate_rows_v2(p_kind,p_query,v_exact,v_pattern) c
    join private.display_navigation_versions_v1 v
      on (v.dataset_kind,v.id,v.version)=(c.dataset_kind,c.id,c.version)
    where
      (not (p_filters ? 'accessLevel') or v.access_level=p_filters->>'accessLevel')
      and (not (p_filters ? 'geography') or v.geography_code=p_filters->>'geography')
      and (not (p_filters ? 'classification') or v.classification_codes @> array[p_filters->>'classification'])
      and (not (p_filters ? 'referenceYearFrom') or v.reference_year >= (p_filters->>'referenceYearFrom')::integer)
      and (not (p_filters ? 'referenceYearTo') or v.reference_year <= (p_filters->>'referenceYearTo')::integer)
      and (not (p_filters ? 'processSubtype') or v.process_subtype=p_filters->>'processSubtype')
      and (not (p_filters ? 'source') or v.source=p_filters->>'source')
      and (
        not (p_filters ? 'classificationNodeId')
        or (v.dataset_kind,v.id,v.version) in (
          select m.dataset_kind,m.id,m.version
          from private.display_navigation_membership_v1 m
          where m.dimension='classification'
            and m.node_id=p_filters->>'classificationNodeId'
            and (p_kind='all' or m.dataset_kind=p_kind)
            and (coalesce(p_filters->>'classificationScope','subtree')<>'direct' or m.direct)
        )
      ) and (
        not (p_filters ? 'geographyNodeId')
        or (v.dataset_kind,v.id,v.version) in (
          select m.dataset_kind,m.id,m.version
          from private.display_navigation_membership_v1 m
          where m.dimension='geography'
            and m.node_id=p_filters->>'geographyNodeId'
            and (p_kind='all' or m.dataset_kind=p_kind)
            and (coalesce(p_filters->>'geographyScope','subtree')<>'direct' or m.direct)
        )
      )
;
      return;
      end if;
    return query
    with cas_keys as materialized (
      select c.dataset_kind,c.id,c.version
      from private.display_catalog_facet_candidate_rows_v2(
        'process',p_query,v_exact,v_pattern
      ) c
      where p_kind in ('all','process')
      union all
      select n.dataset_kind,n.id,n.version
      from private.display_navigation_versions_v1 n
      where p_kind in ('all','flow') and n.dataset_kind='flow'
        and n.cas_number=p_query
    )
    select v.dataset_kind,v.id,v.version
    from cas_keys c
    join private.display_navigation_versions_v1 v
      on (v.dataset_kind,v.id,v.version)=(c.dataset_kind,c.id,c.version)
    where
      (not (p_filters ? 'accessLevel') or v.access_level=p_filters->>'accessLevel')
      and (not (p_filters ? 'geography') or v.geography_code=p_filters->>'geography')
      and (not (p_filters ? 'classification') or v.classification_codes @> array[p_filters->>'classification'])
      and (not (p_filters ? 'referenceYearFrom') or v.reference_year >= (p_filters->>'referenceYearFrom')::integer)
      and (not (p_filters ? 'referenceYearTo') or v.reference_year <= (p_filters->>'referenceYearTo')::integer)
      and (not (p_filters ? 'processSubtype') or v.process_subtype=p_filters->>'processSubtype')
      and (not (p_filters ? 'source') or v.source=p_filters->>'source')
      and (
        not (p_filters ? 'classificationNodeId')
        or (v.dataset_kind,v.id,v.version) in (
          select m.dataset_kind,m.id,m.version
          from private.display_navigation_membership_v1 m
          where m.dimension='classification'
            and m.node_id=p_filters->>'classificationNodeId'
            and (p_kind='all' or m.dataset_kind=p_kind)
            and (coalesce(p_filters->>'classificationScope','subtree')<>'direct' or m.direct)
        )
      ) and (
        not (p_filters ? 'geographyNodeId')
        or (v.dataset_kind,v.id,v.version) in (
          select m.dataset_kind,m.id,m.version
          from private.display_navigation_membership_v1 m
          where m.dimension='geography'
            and m.node_id=p_filters->>'geographyNodeId'
            and (p_kind='all' or m.dataset_kind=p_kind)
            and (coalesce(p_filters->>'geographyScope','subtree')<>'direct' or m.direct)
        )
      )
;
      return;
    end if;

    -- Pattern helpers and UUID lookup already read the authoritative current
    -- projection under the same RLS. Their UNION has one row per exact key.
    -- With empty filters the guarded complete navigation projection adds no
    -- predicate, so the planner may remove this unique-key LEFT JOIN.
    return query
    with lexical_keys as materialized (
      select 'process'::text dataset_kind,p.id,p.version
      from private.display_catalog_process_pattern_versions_v1(v_pattern) p
      where p_kind in ('all','process')
      union
      select 'flow'::text,p.id,p.version
      from private.display_catalog_flow_pattern_versions_v1(v_pattern) p
      where p_kind in ('all','flow')
      union
      select p.dataset_kind,p.id,p.version
      from private.display_catalog_search_current_v2 p
      where (p_kind='all' or p.dataset_kind=p_kind) and p.id=v_exact
    )
    select c.dataset_kind,c.id,c.version
    from lexical_keys c left join private.display_navigation_versions_v1 v
      on (v.dataset_kind,v.id,v.version)=(c.dataset_kind,c.id,c.version)
    where (p_filters='{}'::jsonb or v.id is not null) and
      (not (p_filters ? 'accessLevel') or v.access_level=p_filters->>'accessLevel')
      and (not (p_filters ? 'geography') or v.geography_code=p_filters->>'geography')
      and (not (p_filters ? 'classification') or v.classification_codes @> array[p_filters->>'classification'])
      and (not (p_filters ? 'referenceYearFrom') or v.reference_year >= (p_filters->>'referenceYearFrom')::integer)
      and (not (p_filters ? 'referenceYearTo') or v.reference_year <= (p_filters->>'referenceYearTo')::integer)
      and (not (p_filters ? 'processSubtype') or v.process_subtype=p_filters->>'processSubtype')
      and (not (p_filters ? 'source') or v.source=p_filters->>'source')
      and (
        not (p_filters ? 'classificationNodeId')
        or (v.dataset_kind,v.id,v.version) in (
          select m.dataset_kind,m.id,m.version
          from private.display_navigation_membership_v1 m
          where m.dimension='classification'
            and m.node_id=p_filters->>'classificationNodeId'
            and (p_kind='all' or m.dataset_kind=p_kind)
            and (coalesce(p_filters->>'classificationScope','subtree')<>'direct' or m.direct)
        )
      ) and (
        not (p_filters ? 'geographyNodeId')
        or (v.dataset_kind,v.id,v.version) in (
          select m.dataset_kind,m.id,m.version
          from private.display_navigation_membership_v1 m
          where m.dimension='geography'
            and m.node_id=p_filters->>'geographyNodeId'
            and (p_kind='all' or m.dataset_kind=p_kind)
            and (coalesce(p_filters->>'geographyScope','subtree')<>'direct' or m.direct)
        )
      )
;
  end if;
end;
$_$;

ALTER FUNCTION "private"."display_navigation_matched_versions_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb") OWNER TO "portal_display_executor";

REVOKE ALL ON FUNCTION "private"."display_navigation_matched_versions_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."display_navigation_matched_versions_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb") TO "postgres";

update private.portal_display_contract_manifest set identity=private.portal_display_contract_identity_v1() where singleton;
select private.portal_display_assert_contract_v1();
commit;
