-- Database #723: reduce query-free Portal catalog work using existing projections.
-- No new projection, writer, public API, index or timeout is introduced.
-- The navigation writer/manifest and facet writer already bind the narrow facts
-- to the same exact public versions and source timestamps as the catalog cards.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
grant portal_public_executor to postgres;
grant create on schema private to portal_public_executor;
set local role portal_public_executor;

-- Check existing data before changing readers. Foreign keys prevent orphaned
-- children, but cannot prove that every public parent has its derived children.
-- This runs once at cutover; immutable, atomic writers maintain the invariant.
do $portal_coverage$
begin
  if exists (
    select 1 from private.portal_catalog_search_current_v2 c
    left join private.portal_catalog_facet_rows_v1 f
      on (f.dataset_kind,f.id,f.version)=(c.dataset_kind,c.id,c.version)
    left join private.portal_navigation_versions_v1 v
      on (v.dataset_kind,v.id,v.version)=(c.dataset_kind,c.id,c.version)
    where c.state_code in (100,200) and (
      f.id is null or v.id is null or f.facet_contract_version<>1
      or f.state_code is distinct from c.state_code
      or f.modified_at is distinct from c.modified_at
    )
  ) or exists (
    select 1 from private.portal_catalog_facet_rows_v1 f
    where not exists (
      select 1 from private.portal_catalog_search_current_v2 c
      where (c.dataset_kind,c.id,c.version)=(f.dataset_kind,f.id,f.version)
    )
  ) then
    raise exception using errcode='55000',
      message='Portal narrow catalog projections are incomplete or inconsistent';
  end if;
end;
$portal_coverage$;

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


CREATE OR REPLACE FUNCTION "private"."catalog_portal_search_v3_impl"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_sort" "text", "p_cursor_rank" "text", "p_cursor_id" "uuid", "p_cursor_version" "text", "p_limit" integer, "p_query_fingerprint" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER PARALLEL RESTRICTED
    SET "search_path" TO ''
    SET "statement_timeout" TO '8s'
    SET "plan_cache_mode" TO 'force_custom_plan'
    AS $_$
declare
  v_items jsonb;
  v_next_cursor_payload jsonb;
  v_exact_id uuid;
  v_like_pattern text;
begin
  if p_query ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    v_exact_id := p_query::uuid;
  end if;
  if p_query <> '' then
    v_like_pattern := '%' || pg_catalog.replace(
      pg_catalog.replace(
        pg_catalog.replace(
          p_query,
          pg_catalog.chr(92),
          pg_catalog.chr(92) || pg_catalog.chr(92)
        ),
        '%',
        pg_catalog.chr(92) || '%'
      ),
      '_',
      pg_catalog.chr(92) || '_'
    ) || '%';
  end if;
  -- Browse filtering and paging use synchronized narrow facts. Relevance/date
  -- ordering reads full cards only for the page. Name ordering still detoasts
  -- each matched card once for its name key, without materializing full cards.
  if p_query = ''
     and p_sort in ('relevance', 'modified_desc', 'name_asc') then
    with portal_matches as materialized (
      select matched.id,matched.version,facet.modified_at,
        case when p_sort='name_asc' then case p_kind
          when 'process' then (select p.card #>> '{names,0,value}'
            from private.portal_catalog_search_rows_v2 p
            where p.dataset_kind='process' and p.id=matched.id and p.version=matched.version)
          else (select p.card #>> '{names,0,value}'
            from private.portal_catalog_search_rows_v1 p
            where p.dataset_kind='flow' and p.id=matched.id and p.version=matched.version)
        end end as name_value
      from private.portal_navigation_matched_versions_v1(p_kind,p_query,p_filters) matched
      join private.portal_catalog_facet_rows_v1 facet
        on (facet.dataset_kind,facet.id,facet.version)=(matched.dataset_kind,matched.id,matched.version)
      where facet.facet_contract_version=1 and facet.state_code in (100,200)
    ), portal_prefilter as materialized (
      select id,version,modified_at,
        case when p_sort='name_asc' then case
          when nullif(name_value,'') is not null and length(name_value)<=500
            and octet_length(name_value)<=2000 and name_value !~ '[[:cntrl:]]'
            then name_value else '~unnamed:' || id::text
        end end as name_key
      from portal_matches
    ), portal_after_cursor as materialized (
      select portal_prefilter.*
      from portal_prefilter
      where p_cursor_rank is null
        or case p_sort
          when 'relevance' then
            0::numeric < p_cursor_rank::numeric
            or (
              0::numeric = p_cursor_rank::numeric
              and (
                portal_prefilter.id > p_cursor_id
                or (
                  portal_prefilter.id = p_cursor_id
                  and portal_prefilter.version < p_cursor_version
                )
              )
            )
          when 'modified_desc' then
            portal_prefilter.modified_at < p_cursor_rank::timestamptz
            or (
              portal_prefilter.modified_at = p_cursor_rank::timestamptz
              and (
                portal_prefilter.id > p_cursor_id
                or (
                  portal_prefilter.id = p_cursor_id
                  and portal_prefilter.version < p_cursor_version
                )
              )
            )
          else
            pg_catalog.lower(portal_prefilter.name_key)
              > pg_catalog.lower(p_cursor_rank)
            or (
              pg_catalog.lower(portal_prefilter.name_key)
                = pg_catalog.lower(p_cursor_rank)
              and (
                portal_prefilter.id > p_cursor_id
                or (
                  portal_prefilter.id = p_cursor_id
                  and portal_prefilter.version < p_cursor_version
                )
              )
            )
        end
    ), portal_ordered as materialized (
      select portal_after_cursor.*,
        pg_catalog.row_number() over (
          order by
            case when p_sort = 'modified_desc'
              then portal_after_cursor.modified_at end desc,
            case when p_sort = 'name_asc'
              then pg_catalog.lower(portal_after_cursor.name_key) end asc,
            portal_after_cursor.id asc,
            portal_after_cursor.version desc
        ) as page_rank
      from portal_after_cursor
      order by
        case when p_sort = 'modified_desc'
          then portal_after_cursor.modified_at end desc,
        case when p_sort = 'name_asc'
          then pg_catalog.lower(portal_after_cursor.name_key) end asc,
        portal_after_cursor.id asc,
        portal_after_cursor.version desc
      limit p_limit + 1
    ), portal_decorated as materialized (
      select portal_ordered.*,
        case p_kind
          when 'process' then (select p.card from private.portal_catalog_search_rows_v2 p
            where p.dataset_kind='process' and p.id=portal_ordered.id and p.version=portal_ordered.version)
          else (select p.card from private.portal_catalog_search_rows_v1 p
            where p.dataset_kind='flow' and p.id=portal_ordered.id and p.version=portal_ordered.version)
        end as card
      from portal_ordered
    )
    select
      coalesce(pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'key', pg_catalog.jsonb_build_object(
            'kind', p_kind,
            'id', portal_decorated.id::text,
            'version', portal_decorated.version
          ),
          'accessLevel', portal_decorated.card -> 'accessLevel',
          'capabilities', portal_decorated.card -> 'capabilities',
          'names', portal_decorated.card -> 'names',
          'summary', portal_decorated.card -> 'summary',
          'geography', portal_decorated.card -> 'geography',
          'referenceYear', portal_decorated.card -> 'referenceYear',
          'modifiedAt', pg_catalog.to_char(
            portal_decorated.modified_at at time zone 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
          ),
          'match', pg_catalog.jsonb_build_object(
            -- Keep the retained filtered-empty-query match metadata byte-identical.
            'kind', case when p_filters <> '{}'::jsonb
                and coalesce(portal_decorated.card ->> 'casNumber','') = ''
              then 'identifier' else 'lexical' end,
            'score', 0::numeric,
            'reasonCodes', case when p_filters <> '{}'::jsonb
                and coalesce(portal_decorated.card ->> 'casNumber','') = ''
              then pg_catalog.jsonb_build_array('cas') else '[]'::jsonb end
          )
        ) order by portal_decorated.page_rank
      ) filter (where portal_decorated.page_rank <= p_limit), '[]'::jsonb),
      case when max(portal_decorated.page_rank) > p_limit then
        (pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'v', 1,
          'fp', p_query_fingerprint,
          'rankKey', case p_sort
            when 'relevance' then '0'
            when 'modified_desc' then pg_catalog.to_char(
              portal_decorated.modified_at at time zone 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            )
            else pg_catalog.lower(portal_decorated.name_key)
          end,
          'kind', p_kind,
          'id', portal_decorated.id::text,
          'version', portal_decorated.version
        ) order by portal_decorated.page_rank)
          filter (where portal_decorated.page_rank = p_limit)) -> 0
      else null end
    into v_items, v_next_cursor_payload
    from portal_decorated;

    return pg_catalog.jsonb_build_object(
      'items', v_items,
      'nextCursorPayload', v_next_cursor_payload
    );
  end if;


  with portal_prefilter as materialized (
    select p_kind as dataset_kind,
      candidate.*
    from private.catalog_portal_candidate_rows_v3(
      p_kind,
      p_query,
      v_exact_id,
      v_like_pattern
    ) as candidate
    where private.portal_navigation_version_matches_v3(
      p_kind, p_filters, candidate.id, candidate.version
    )
  ), portal_facts as materialized (
    select portal_prefilter.*,
      private.catalog_portal_card_facts_v1(
        portal_prefilter.card,
        p_filters,
        p_query
      ) as facts
    from portal_prefilter
  ), portal_scored as materialized (
    select portal_facts.*,
      case
        when nullif(portal_facts.facts ->> 'nameKey', '') is not null
          and pg_catalog.length(portal_facts.facts ->> 'nameKey') <= 500
          and pg_catalog.octet_length(portal_facts.facts ->> 'nameKey') <= 2000
          and portal_facts.facts ->> 'nameKey' !~ '[[:cntrl:]]'
          then portal_facts.facts ->> 'nameKey'
        else '~unnamed:' || portal_facts.id::text
      end as name_key,
      case
        when p_query = '' then 0::numeric
        when pg_catalog.lower(portal_facts.id::text) = p_query then 1::numeric
        when pg_catalog.lower(coalesce(portal_facts.facts ->> 'casNumber', '')) = p_query
          then 0.98::numeric
        when (portal_facts.facts ->> 'nameExact')::boolean then 0.95::numeric
        when (portal_facts.facts ->> 'classificationExact')::boolean
          then 0.92::numeric
        when p_query <> '' then 0.70::numeric
        else 0::numeric
      end as score,
      case
        when pg_catalog.lower(portal_facts.id::text) = p_query
          then pg_catalog.jsonb_build_array('exact_id')
        when pg_catalog.lower(coalesce(portal_facts.facts ->> 'casNumber', '')) = p_query
          then pg_catalog.jsonb_build_array('cas')
        when (portal_facts.facts ->> 'nameExact')::boolean
          or (portal_facts.facts ->> 'nameContains')::boolean
          then pg_catalog.jsonb_build_array('name')
        when (portal_facts.facts ->> 'classificationExact')::boolean
          or (portal_facts.facts ->> 'classificationContains')::boolean
          then pg_catalog.jsonb_build_array('classification')
        when p_query <> '' then pg_catalog.jsonb_build_array('full_text')
        else '[]'::jsonb
      end as reason_codes
    from portal_facts
  ), portal_filtered as materialized (
    select portal_scored.*,
      case p_sort
        when 'relevance' then portal_scored.score::text
        when 'modified_desc' then pg_catalog.to_char(
          portal_scored.modified_at at time zone 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
        )
        else pg_catalog.lower(portal_scored.name_key)
      end as rank_key
    from portal_scored
    where (p_query = '' or portal_scored.score > 0)
      and (
        not (p_filters ? 'accessLevel')
        or portal_scored.facts ->> 'accessLevel' = p_filters ->> 'accessLevel'
      )
      and (
        not (p_filters ? 'geography')
        or pg_catalog.lower(pg_catalog.btrim(coalesce(
          portal_scored.facts ->> 'geographyCode',
          ''
        ))) = p_filters ->> 'geography'
      )
      and (
        not (p_filters ? 'classification')
        or (portal_scored.facts ->> 'classificationFilterMatch')::boolean
      )
      and (
        not (p_filters ? 'referenceYearFrom')
        or (portal_scored.facts ->> 'referenceYear')::integer
          >= (p_filters ->> 'referenceYearFrom')::integer
      )
      and (
        not (p_filters ? 'referenceYearTo')
        or (portal_scored.facts ->> 'referenceYear')::integer
          <= (p_filters ->> 'referenceYearTo')::integer
      )
      and (
        not (p_filters ? 'processSubtype')
        or pg_catalog.lower(pg_catalog.btrim(coalesce(
          portal_scored.facts ->> 'processSubtype',
          ''
        ))) = p_filters ->> 'processSubtype'
      )
      and (
        not (p_filters ? 'source')
        or pg_catalog.lower(pg_catalog.btrim(coalesce(
          portal_scored.facts ->> 'source',
          ''
        ))) = p_filters ->> 'source'
      )
  ), portal_after_cursor as materialized (
    select portal_filtered.*
    from portal_filtered
    where p_cursor_rank is null
      or case p_sort
        when 'relevance' then
          portal_filtered.score < p_cursor_rank::numeric
          or (
            portal_filtered.score = p_cursor_rank::numeric
            and (
              portal_filtered.id > p_cursor_id
              or (
                portal_filtered.id = p_cursor_id
                and portal_filtered.version < p_cursor_version
              )
            )
          )
        when 'modified_desc' then
          portal_filtered.modified_at < p_cursor_rank::timestamptz
          or (
            portal_filtered.modified_at = p_cursor_rank::timestamptz
            and (
              portal_filtered.id > p_cursor_id
              or (
                portal_filtered.id = p_cursor_id
                and portal_filtered.version < p_cursor_version
              )
            )
          )
        else
          pg_catalog.lower(portal_filtered.name_key) > pg_catalog.lower(p_cursor_rank)
          or (
            pg_catalog.lower(portal_filtered.name_key) = pg_catalog.lower(p_cursor_rank)
            and (
              portal_filtered.id > p_cursor_id
              or (
                portal_filtered.id = p_cursor_id
                and portal_filtered.version < p_cursor_version
              )
            )
          )
      end
  ), portal_ordered as materialized (
    select portal_after_cursor.*,
      pg_catalog.row_number() over (
        order by
          case when p_sort = 'relevance' then portal_after_cursor.score end desc,
          case when p_sort = 'modified_desc' then portal_after_cursor.modified_at end desc,
          case when p_sort = 'name_asc'
            then pg_catalog.lower(portal_after_cursor.name_key) end asc,
          portal_after_cursor.id asc,
          portal_after_cursor.version desc
      ) as page_rank
    from portal_after_cursor
    order by
      case when p_sort = 'relevance' then portal_after_cursor.score end desc,
      case when p_sort = 'modified_desc' then portal_after_cursor.modified_at end desc,
      case when p_sort = 'name_asc'
        then pg_catalog.lower(portal_after_cursor.name_key) end asc,
      portal_after_cursor.id asc,
      portal_after_cursor.version desc
    limit p_limit + 1
  ), portal_hydrated as materialized (
    select portal_ordered.*
    from portal_ordered
  )
  select
    coalesce(pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'key', pg_catalog.jsonb_build_object(
          'kind', p_kind,
          'id', portal_hydrated.id::text,
          'version', portal_hydrated.version
        ),
        'accessLevel', portal_hydrated.card -> 'accessLevel',
        'capabilities', portal_hydrated.card -> 'capabilities',
        'names', portal_hydrated.card -> 'names',
        'summary', portal_hydrated.card -> 'summary',
        'geography', portal_hydrated.card -> 'geography',
        'referenceYear', portal_hydrated.card -> 'referenceYear',
        'modifiedAt', pg_catalog.to_char(
          portal_hydrated.modified_at at time zone 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
        ),
        'match', pg_catalog.jsonb_build_object(
          'kind', case when portal_hydrated.reason_codes
            ?| array['exact_id', 'cas', 'classification']
            then 'identifier' else 'lexical' end,
          'score', portal_hydrated.score,
          'reasonCodes', portal_hydrated.reason_codes
        )
      ) order by portal_hydrated.page_rank
    ) filter (where portal_hydrated.page_rank <= p_limit), '[]'::jsonb),
    case when max(portal_hydrated.page_rank) > p_limit then
      (pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'v', 1,
        'fp', p_query_fingerprint,
        'rankKey', portal_hydrated.rank_key,
        'kind', p_kind,
        'id', portal_hydrated.id::text,
        'version', portal_hydrated.version
      ) order by portal_hydrated.page_rank)
        filter (where portal_hydrated.page_rank = p_limit)) -> 0
    else null end
  into v_items, v_next_cursor_payload
  from portal_hydrated;

  return pg_catalog.jsonb_build_object(
    'items', v_items,
    'nextCursorPayload', v_next_cursor_payload
  );
end;
$_$;

ALTER FUNCTION "private"."catalog_portal_search_v3_impl"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_sort" "text", "p_cursor_rank" "text", "p_cursor_id" "uuid", "p_cursor_version" "text", "p_limit" integer, "p_query_fingerprint" "text") OWNER TO "portal_public_executor";

REVOKE ALL ON FUNCTION "private"."catalog_portal_search_v3_impl"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_sort" "text", "p_cursor_rank" "text", "p_cursor_id" "uuid", "p_cursor_version" "text", "p_limit" integer, "p_query_fingerprint" "text") FROM PUBLIC;


CREATE OR REPLACE FUNCTION "private"."catalog_portal_facets_v3_impl"("p_kind" "text", "p_query" "text", "p_exact_id" "uuid", "p_like_pattern" "text", "p_filters" "jsonb", "p_query_fingerprint" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER PARALLEL RESTRICTED
    SET "search_path" TO ''
    SET "statement_timeout" TO '8s'
    SET "plan_cache_mode" TO 'force_custom_plan'
    SET "row_security" TO 'on'
    AS $$
begin
  if p_query='' then
    return (
with matched as materialized (
    select * from private.portal_navigation_matched_versions_v1(p_kind,p_query,p_filters)
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
  end if;

  -- Nonempty lexical candidate and matching semantics remain unchanged.
  return (
with matched as materialized (
    select candidate.*
    from private.catalog_portal_facet_candidate_rows_v3(
      p_kind,
      p_query,
      p_exact_id,
      p_like_pattern
    ) as candidate
    where private.portal_navigation_version_matches_v3(
        candidate.dataset_kind, p_filters, candidate.id, candidate.version
      )
      and (
        not (p_filters ? 'accessLevel')
        or candidate.card ->> 'accessLevel' = p_filters ->> 'accessLevel'
      )
      and (
        not (p_filters ? 'geography')
        or pg_catalog.lower(pg_catalog.btrim(coalesce(
          candidate.card #>> '{geography,code}',
          ''
        ))) = p_filters ->> 'geography'
      )
      and (
        not (p_filters ? 'classification')
        or exists (
          select 1
          from pg_catalog.jsonb_array_elements(
            candidate.card -> 'classifications'
          ) as classification(item)
          where pg_catalog.lower(pg_catalog.btrim(
            classification.item ->> 'code'
          )) = p_filters ->> 'classification'
        )
      )
      and (
        not (p_filters ? 'referenceYearFrom')
        or (candidate.card ->> 'referenceYear')::integer
          >= (p_filters ->> 'referenceYearFrom')::integer
      )
      and (
        not (p_filters ? 'referenceYearTo')
        or (candidate.card ->> 'referenceYear')::integer
          <= (p_filters ->> 'referenceYearTo')::integer
      )
      and (
        not (p_filters ? 'processSubtype')
        or pg_catalog.lower(pg_catalog.btrim(coalesce(
          candidate.card ->> 'processSubtype',
          ''
        ))) = p_filters ->> 'processSubtype'
      )
      and (
        not (p_filters ? 'source')
        or pg_catalog.lower(pg_catalog.btrim(coalesce(
          candidate.card ->> 'source',
          ''
        ))) = p_filters ->> 'source'
      )
  ), facet_values as materialized (
    select 'kind'::text as group_id,
      1 as group_order,
      matched.dataset_kind as value,
      matched.dataset_kind as label
    from matched
    union all
    select 'accessLevel',
      2,
      matched.card ->> 'accessLevel',
      matched.card ->> 'accessLevel'
    from matched
    union all
    select 'geography',
      3,
      pg_catalog.lower(pg_catalog.btrim(
        matched.card #>> '{geography,code}'
      )),
      matched.card #>> '{geography,code}'
    from matched
    union all
    select 'referenceYear',
      4,
      pg_catalog.btrim(matched.card ->> 'referenceYear'),
      pg_catalog.btrim(matched.card ->> 'referenceYear')
    from matched
    union all
    select 'processSubtype',
      5,
      pg_catalog.lower(pg_catalog.btrim(
        matched.card ->> 'processSubtype'
      )),
      matched.card ->> 'processSubtype'
    from matched
    where matched.dataset_kind = 'process'
    union all
    select 'source',
      6,
      pg_catalog.lower(pg_catalog.btrim(matched.card ->> 'source')),
      matched.card ->> 'source'
    from matched
  ), counts as materialized (
    select group_id,
      group_order,
      value,
      pg_catalog.min(value) as label,
      pg_catalog.count(*) as value_count
    from facet_values
    where nullif(pg_catalog.btrim(value), '') is not null
      and pg_catalog.length(value) <= 128
      and pg_catalog.octet_length(value) <= 512
    group by group_id, group_order, value
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
$$;

ALTER FUNCTION "private"."catalog_portal_facets_v3_impl"("p_kind" "text", "p_query" "text", "p_exact_id" "uuid", "p_like_pattern" "text", "p_filters" "jsonb", "p_query_fingerprint" "text") OWNER TO "portal_public_executor";

REVOKE ALL ON FUNCTION "private"."catalog_portal_facets_v3_impl"("p_kind" "text", "p_query" "text", "p_exact_id" "uuid", "p_like_pattern" "text", "p_filters" "jsonb", "p_query_fingerprint" "text") FROM PUBLIC;


CREATE OR REPLACE FUNCTION "private"."portal_navigation_impl_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor_node_id" "text", "p_limit" integer, "p_fingerprint" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER PARALLEL RESTRICTED
    SET "search_path" TO ''
    SET "row_security" TO 'on'
    SET "plan_cache_mode" TO 'force_custom_plan'
    SET "statement_timeout" TO '8s'
    SET "work_mem" TO '32MB'
    AS $$
declare
  v_parent jsonb;
  v_ancestors jsonb:='[]';
  v_nodes jsonb;
  v_totals jsonb;
  v_next text;
  v_result jsonb;
  v_after_code text;
  v_trimmed boolean:=false;
begin
  perform private.assert_portal_navigation_contract_v1();
  if p_parent_node_id is not null and not exists (
    select 1 from private.portal_navigation_node_v1 n
    where n.node_id=p_parent_node_id and n.dimension=p_dimension
      and (n.source_file is not null or n.node_id in ('class:isic','class:cpc','class:elementary','geo:unmapped')
        or exists(select 1 from private.portal_navigation_membership_v1 m where m.node_id=n.node_id))
  ) then raise exception using errcode='22023',message='invalid portal request'; end if;
  if p_cursor_node_id is not null then
    select n.code into v_after_code from private.portal_navigation_node_v1 n
    where n.node_id=p_cursor_node_id and n.dimension=p_dimension
      and n.parent_node_id is not distinct from p_parent_node_id;
    if not found then raise exception using errcode='22023',message='invalid portal request'; end if;
  end if;

  with matched as materialized (
    select * from private.portal_navigation_matched_versions_v1('all',p_query,p_filters)
  ), children as materialized (
    select n.* from private.portal_navigation_node_v1 n
    where n.dimension=p_dimension and n.parent_node_id is not distinct from p_parent_node_id
      and (n.source_file is not null or n.node_id in ('class:isic','class:cpc','class:elementary','geo:unmapped') or exists (
        select 1 from private.portal_navigation_membership_v1 m
        where m.node_id=n.node_id and (p_kind='all' or m.dataset_kind=p_kind)
          and ((p_query='' and p_filters='{}'::jsonb)
            or (m.dataset_kind,m.id,m.version) in (select dataset_kind,id,version from matched))))
      and (p_dimension<>'classification' or p_kind='all' or n.taxonomy not in ('isic','cpc','elementary')
        or (p_kind='process' and n.taxonomy='isic') or (p_kind='flow' and n.taxonomy in ('cpc','elementary')))
      and (p_cursor_node_id is null or (n.code collate "C",n.node_id collate "C")>(v_after_code collate "C",p_cursor_node_id collate "C"))
    order by n.code collate "C",n.node_id collate "C" limit p_limit+1
  ), targets as materialized (
    select * from children
    union all
    select n.* from private.portal_navigation_node_v1 n where n.node_id=p_parent_node_id
  ), counted as materialized (
    select m.node_id,count(*) as count,count(*) filter(where m.direct) as direct_count
    from private.portal_navigation_membership_v1 m
    where m.dimension=p_dimension and (p_kind='all' or m.dataset_kind=p_kind)
      and ((p_query='' and p_filters='{}'::jsonb)
        or (m.dataset_kind,m.id,m.version) in (select dataset_kind,id,version from matched))
      and m.node_id in(select n.node_id from targets n)
    group by m.node_id
  ), decorated as materialized (
    select n.node_id,n.code,jsonb_build_object(
      'nodeId',n.node_id,'parentNodeId',n.parent_node_id,'code',n.code,'taxonomy',n.taxonomy,
      'count',coalesce(c.count,0),'directCount',coalesce(c.direct_count,0),
      'hasChildren',exists(select 1 from private.portal_navigation_node_v1 child where child.parent_node_id=n.node_id
        and (child.source_file is not null or exists(select 1 from private.portal_navigation_membership_v1 m where m.node_id=child.node_id)))
    ) as value from targets n left join counted c on c.node_id=n.node_id
  ), paged as (
    select d.*,row_number() over(order by d.code collate "C",d.node_id collate "C") as rn
    from decorated d where d.node_id is distinct from p_parent_node_id
  ) select
    coalesce((select jsonb_agg(value order by rn) from paged where rn<=p_limit),'[]'::jsonb),
    (select case when count(*)>p_limit then (array_agg(node_id order by rn))[p_limit] else null end from paged),
    (select value from decorated where node_id=p_parent_node_id),
    (select jsonb_build_object('process',count(*) filter(where dataset_kind='process'),'flow',count(*) filter(where dataset_kind='flow')) from matched)
  into v_nodes,v_next,v_parent,v_totals;

  with recursive ancestors as (
    select n.node_id,n.parent_node_id,n.code,n.taxonomy,1 as depth
    from private.portal_navigation_node_v1 n
    where n.node_id=(select p.parent_node_id from private.portal_navigation_node_v1 p where p.node_id=p_parent_node_id)
    union all
    select n.node_id,n.parent_node_id,n.code,n.taxonomy,a.depth+1
    from ancestors a join private.portal_navigation_node_v1 n on n.node_id=a.parent_node_id
    where a.depth<32
  ) select coalesce(jsonb_agg(jsonb_build_object('nodeId',node_id,'parentNodeId',parent_node_id,'code',code,'taxonomy',taxonomy) order by depth desc),'[]'::jsonb)
    into v_ancestors from ancestors;

  loop
    v_result:=jsonb_build_object('schemaVersion','portal.public-navigation.v1','countBasis','public_versions',
      'dimension',p_dimension,'kind',p_kind,'totals',v_totals,'parent',v_parent,'ancestors',v_ancestors,'nodes',v_nodes,
      'nextCursor',case when v_next is null then null else private.portal_cursor_encode_v1(jsonb_build_object(
        'v',1,'fp',p_fingerprint,'dimension',p_dimension,'kind',p_kind,'parent',p_parent_node_id,'node',v_next)) end);
    exit when octet_length(v_result::text)<=65536;
    if jsonb_array_length(v_nodes)<=1 then
      raise exception using errcode='54000',message='Portal navigation response exceeds its byte budget';
    end if;
    v_nodes:=v_nodes-(jsonb_array_length(v_nodes)-1);
    v_next:=v_nodes->(jsonb_array_length(v_nodes)-1)->>'nodeId';
  end loop;
  return v_result;
end;
$$;

ALTER FUNCTION "private"."portal_navigation_impl_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor_node_id" "text", "p_limit" integer, "p_fingerprint" "text") OWNER TO "portal_public_executor";

REVOKE ALL ON FUNCTION "private"."portal_navigation_impl_v1"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_dimension" "text", "p_parent_node_id" "text", "p_cursor_node_id" "text", "p_limit" integer, "p_fingerprint" "text") FROM PUBLIC;

select private.assert_portal_navigation_projection_v1();
reset role;
revoke create on schema private from portal_public_executor;
revoke portal_public_executor from postgres;
commit;
