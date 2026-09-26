CREATE OR REPLACE FUNCTION "private"."portal_navigation_matched_versions_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb") RETURNS TABLE("dataset_kind" "text", "id" "uuid", "version" "text")
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
    -- Empty/query-free navigation never detoasts public cards or raw source JSON.
    return query select v.dataset_kind,v.id,v.version
    from private.portal_navigation_versions_v1 v
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
          from private.portal_navigation_membership_v1 m
          where m.dimension='classification'
            and m.node_id=p_filters->>'classificationNodeId'
            and (p_kind='all' or m.dataset_kind=p_kind)
            and (coalesce(p_filters->>'classificationScope','subtree')<>'direct' or m.direct)
        )
      ) and (
        not (p_filters ? 'geographyNodeId')
        or (v.dataset_kind,v.id,v.version) in (
          select m.dataset_kind,m.id,m.version
          from private.portal_navigation_membership_v1 m
          where m.dimension='geography'
            and m.node_id=p_filters->>'geographyNodeId'
            and (p_kind='all' or m.dataset_kind=p_kind)
            and (coalesce(p_filters->>'geographyScope','subtree')<>'direct' or m.direct)
        )
      )
;
  else
    if p_query ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then v_exact:=p_query::uuid; end if;
    v_pattern := '%' || replace(replace(replace(p_query,chr(92),chr(92)||chr(92)),'%',chr(92)||'%'),'_',chr(92)||'_') || '%';
    -- Reuse the exact UUID/CAS/literal/one-character candidate contract of V2.
    return query select v.dataset_kind,v.id,v.version
    from private.catalog_portal_facet_candidate_rows_v2(p_kind,p_query,v_exact,v_pattern) c
    join private.portal_navigation_versions_v1 v
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
          from private.portal_navigation_membership_v1 m
          where m.dimension='classification'
            and m.node_id=p_filters->>'classificationNodeId'
            and (p_kind='all' or m.dataset_kind=p_kind)
            and (coalesce(p_filters->>'classificationScope','subtree')<>'direct' or m.direct)
        )
      ) and (
        not (p_filters ? 'geographyNodeId')
        or (v.dataset_kind,v.id,v.version) in (
          select m.dataset_kind,m.id,m.version
          from private.portal_navigation_membership_v1 m
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

ALTER FUNCTION "private"."portal_navigation_matched_versions_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb") OWNER TO "portal_public_executor";

REVOKE ALL ON FUNCTION "private"."portal_navigation_matched_versions_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb") FROM PUBLIC;
