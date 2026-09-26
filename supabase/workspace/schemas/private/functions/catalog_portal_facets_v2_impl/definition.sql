CREATE OR REPLACE FUNCTION "private"."catalog_portal_facets_v2_impl"("p_kind" "text", "p_query" "text", "p_exact_id" "uuid", "p_like_pattern" "text", "p_filters" "jsonb", "p_query_fingerprint" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER PARALLEL RESTRICTED
    SET "search_path" TO ''
    SET "statement_timeout" TO '8s'
    SET "plan_cache_mode" TO 'force_custom_plan'
    SET "row_security" TO 'on'
    AS $_$
begin
    return (
with pattern_matches as materialized (
    select 'process'::text as dataset_kind,pattern.id,pattern.version
    from private.catalog_portal_process_pattern_versions_v1(p_like_pattern) pattern
    where p_kind in ('process','all') and p_query<>''
    union all
    select 'flow'::text,pattern.id,pattern.version
    from private.catalog_portal_flow_pattern_versions_v1(p_like_pattern) pattern
    where p_kind in ('flow','all') and p_query<>'' and not private.portal_catalog_summary_valid_cas_v1(p_query)
  ), candidate_keys as materialized (
    select dataset_kind,id,version from pattern_matches
    union
    select p.dataset_kind,p.id,p.version from private.portal_catalog_search_current_v2 p
    where (p_kind='all' or p.dataset_kind=p_kind) and p.state_code in (100,200)
      and p.id=p_exact_id
    union
    select 'flow'::text,p.id,p.version from private.portal_catalog_search_rows_v1 p
    where p_kind in ('flow','all') and p_query<>''
      and private.portal_catalog_summary_valid_cas_v1(p_query)
      and p.dataset_kind='flow' and p.state_code in (100,200)
      and pg_catalog.jsonb_typeof(p.card->'casNumber')='string'
      and p.card->>'casNumber' ~ '^[0-9]{2,7}-[0-9]{2}-[0-9]$'
      and pg_catalog.length(p.card->>'casNumber') between 7 and 12
      and p.card->>'casNumber'=p_query
  ), matched as materialized (
    select filtered.* from private.portal_navigation_matched_versions_v1(p_kind,'',p_filters) filtered
    where p_query='' or (filtered.dataset_kind,filtered.id,filtered.version)
      in (select dataset_kind,id,version from candidate_keys)
  ), visible_versions as materialized (
    select
      facet.dataset_kind,
      facet.id,
      facet.version,
      facet.facet_access_level,
      facet.facet_geography,
      facet.facet_reference_year,
      facet.facet_process_subtype,
      facet.facet_source
    from private.portal_catalog_facet_rows_v1 as facet
    where facet.facet_contract_version = 1 and facet.state_code in (100,200)
      and (p_kind = 'all' or facet.dataset_kind = p_kind)
      and (facet.dataset_kind,facet.id,facet.version) in (select dataset_kind,id,version from matched)
  ), facts as materialized (
    select visible_versions.dataset_kind,
      visible_versions.facet_access_level,
      visible_versions.facet_geography,
      visible_versions.facet_reference_year,
      case when visible_versions.dataset_kind = 'process' then
        visible_versions.facet_process_subtype
      else null::text end as facet_process_subtype,
      visible_versions.facet_source
    from visible_versions
  ), counts_raw as materialized (
    select case
        when grouping(facts.dataset_kind) = 0 then 'kind'
        when grouping(facts.facet_access_level) = 0 then 'accessLevel'
        when grouping(facts.facet_geography) = 0 then 'geography'
        when grouping(facts.facet_reference_year) = 0 then 'referenceYear'
        when grouping(facts.facet_process_subtype) = 0 then 'processSubtype'
        else 'source'
      end as group_id,
      case
        when grouping(facts.dataset_kind) = 0 then 1
        when grouping(facts.facet_access_level) = 0 then 2
        when grouping(facts.facet_geography) = 0 then 3
        when grouping(facts.facet_reference_year) = 0 then 4
        when grouping(facts.facet_process_subtype) = 0 then 5
        else 6
      end as group_order,
      case
        when grouping(facts.dataset_kind) = 0 then facts.dataset_kind
        when grouping(facts.facet_access_level) = 0 then
          facts.facet_access_level
        when grouping(facts.facet_geography) = 0 then facts.facet_geography
        when grouping(facts.facet_reference_year) = 0 then
          facts.facet_reference_year
        when grouping(facts.facet_process_subtype) = 0 then
          facts.facet_process_subtype
        else facts.facet_source
      end as value,
      pg_catalog.count(*) as value_count
    from facts
    group by grouping sets (
      (facts.dataset_kind),
      (facts.facet_access_level),
      (facts.facet_geography),
      (facts.facet_reference_year),
      (facts.facet_process_subtype),
      (facts.facet_source)
    )
  ), counts as materialized (
    select counts_raw.group_id,
      counts_raw.group_order,
      counts_raw.value,
      counts_raw.value as label,
      counts_raw.value_count
    from counts_raw
    where nullif(pg_catalog.btrim(counts_raw.value), '') is not null
      and pg_catalog.length(counts_raw.value) <= 128
      and pg_catalog.octet_length(counts_raw.value) <= 512
  ), ranked_counts as materialized (
    select counts.*,
      pg_catalog.row_number() over (
        partition by counts.group_id
        order by counts.value
      ) as value_rank
    from counts
  ), grouped as materialized (
    select ranked_counts.group_id,
      ranked_counts.group_order,
      pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'value', ranked_counts.value,
        'label', pg_catalog.jsonb_build_array(
          pg_catalog.jsonb_build_object(
            'language', 'und', 'value', ranked_counts.label
          )
        ),
        'count', ranked_counts.value_count
      ) order by ranked_counts.value)
        filter (where ranked_counts.value_rank <= 100) as values_json,
      pg_catalog.bool_or(ranked_counts.value_rank > 100) as has_more
    from ranked_counts
    group by ranked_counts.group_id, ranked_counts.group_order
  ), groups as (
    select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'id', grouped.group_id,
      'label', pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          'language', 'en',
          'value', case grouped.group_id
            when 'kind' then 'Object type'
            when 'accessLevel' then 'Access level'
            when 'geography' then 'Geography'
            when 'referenceYear' then 'Reference year'
            when 'processSubtype' then 'Process subtype'
            else 'Source'
          end
        ),
        pg_catalog.jsonb_build_object(
          'language', 'zh-CN',
          'value', case grouped.group_id
            when 'kind' then '对象类型'
            when 'accessLevel' then '访问级别'
            when 'geography' then '地区'
            when 'referenceYear' then '参考年'
            when 'processSubtype' then '过程类型'
            else '数据源'
          end
        )
      ),
      'values', grouped.values_json,
      'hasMore', grouped.has_more
    ) order by grouped.group_order), '[]'::jsonb) as value
    from grouped
  )
  select pg_catalog.jsonb_build_object(
    'schemaVersion', 'portal.public-facets.v2',
    'kind', p_kind,
    'queryFingerprint', p_query_fingerprint,
    'groups', groups.value
  )
  from groups
    );
end;

$_$;

ALTER FUNCTION "private"."catalog_portal_facets_v2_impl"("p_kind" "text", "p_query" "text", "p_exact_id" "uuid", "p_like_pattern" "text", "p_filters" "jsonb", "p_query_fingerprint" "text") OWNER TO "portal_public_executor";

REVOKE ALL ON FUNCTION "private"."catalog_portal_facets_v2_impl"("p_kind" "text", "p_query" "text", "p_exact_id" "uuid", "p_like_pattern" "text", "p_filters" "jsonb", "p_query_fingerprint" "text") FROM PUBLIC;
