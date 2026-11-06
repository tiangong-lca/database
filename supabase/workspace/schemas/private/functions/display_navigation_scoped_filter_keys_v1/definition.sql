CREATE OR REPLACE FUNCTION "private"."display_navigation_scoped_filter_keys_v1"("p_kind" "text", "p_filters" "jsonb") RETURNS TABLE("dataset_kind" "text", "id" "uuid", "version" "text")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER PARALLEL RESTRICTED
    SET "search_path" TO ''
    SET "row_security" TO 'on'
    SET "plan_cache_mode" TO 'force_custom_plan'
    AS $$
begin
  if p_kind is null or p_kind not in ('all','process','flow') then
    raise exception using errcode='22023',message='invalid portal request';
  end if;
  -- The closed owner bridge filters synchronized native facts first, then
  -- intersects EVERY exact version with the authoritative current scope view.
  -- Membership rows refer to the same exact key; their visibility is checked
  -- by that final intersection. No card, raw source or authorization cache.
  -- 2048 selects indexed probes versus a bulk intersection, never a row cap.
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
      where scope.dataset_kind=matched.dataset_kind
        and scope.dataset_id=matched.id and scope.dataset_version=matched.version
      offset 0
    )
  union all
  select matched.dataset_kind,matched.id,matched.version
  from matches matched
  where (select n from match_count)>2048
    and exists (
      select 1 from private.display_request_visible_settings_v1 scope
      where scope.dataset_kind=matched.dataset_kind
        and scope.dataset_id=matched.id and scope.dataset_version=matched.version
    );
end;
$$;

ALTER FUNCTION "private"."display_navigation_scoped_filter_keys_v1"("p_kind" "text", "p_filters" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."display_navigation_scoped_filter_keys_v1"("p_kind" "text", "p_filters" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."display_navigation_scoped_filter_keys_v1"("p_kind" "text", "p_filters" "jsonb") TO "portal_display_executor";
