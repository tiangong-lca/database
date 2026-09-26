-- Database #733: legacy V2 narrow readers; existing public DTOs, cursors and budgets remain.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
-- Transfer this existing reader through its current owner. Temporary DDL
-- membership/schema rights are restored before commit, preserving prestate.
do $portal_v2_acl_begin$
declare r text; before_grant jsonb;
begin
  foreach r in array array['api_internal_executor','portal_public_executor'] loop
    select pg_catalog.jsonb_build_object('admin',m.admin_option,'inherit',m.inherit_option,'set',m.set_option)
      into before_grant from pg_catalog.pg_auth_members m
      where m.roleid=r::regrole and m.member='postgres'::regrole and m.grantor=current_user::regrole;
    perform pg_catalog.set_config('portal_v2_cutover.'||r||'_postgres_grant',coalesce(before_grant,'null'::jsonb)::text,true);
    execute pg_catalog.format('grant %I to postgres',r);
  end loop;
  perform pg_catalog.set_config('portal_v2_cutover.role_added',
    (not pg_catalog.pg_has_role('api_internal_executor','portal_public_executor','MEMBER'))::text,true);
  perform pg_catalog.set_config('portal_v2_cutover.create_added',
    (not pg_catalog.has_schema_privilege('portal_public_executor','private','CREATE'))::text,true);
  if pg_catalog.current_setting('portal_v2_cutover.role_added')::boolean then
    grant portal_public_executor to api_internal_executor;
  end if;
  if pg_catalog.current_setting('portal_v2_cutover.create_added')::boolean then
    grant create on schema private to portal_public_executor;
  end if;
end;
$portal_v2_acl_begin$;
set local role api_internal_executor;
alter function private.catalog_portal_search_v2_impl(text,text,jsonb,text,text,uuid,text,integer,text)
  owner to portal_public_executor;
reset role;
set local role portal_public_executor;
do $portal_coverage$
declare invalid_projection boolean;
begin
  -- Compare both directions in one full join. An EXISTS anti-join can favor
  -- low startup cost and rescan this unindexed CTE once per child at 4 MB
  -- work_mem, even though proving a healthy catalog requires the whole set.
  with parents as materialized (
    select dataset_kind,id,version,state_code,modified_at
    from private.portal_catalog_search_current_v2 where state_code in (100,200)
  ) select coalesce(bool_or(
      c.id is null or f.id is null or v.id is null or f.facet_contract_version<>1
      or f.state_code is distinct from c.state_code
      or f.modified_at is distinct from c.modified_at
    ),false) into invalid_projection
  from parents c
  full join private.portal_catalog_facet_rows_v1 f
    on (f.dataset_kind,f.id,f.version)=(c.dataset_kind,c.id,c.version)
  left join private.portal_navigation_versions_v1 v
    on (v.dataset_kind,v.id,v.version)=(c.dataset_kind,c.id,c.version);
  if invalid_projection then
    raise exception using errcode='55000',
      message='Portal narrow catalog projections are incomplete or inconsistent';
  end if;
end;
$portal_coverage$;

CREATE OR REPLACE FUNCTION "private"."catalog_portal_search_v2_impl"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_sort" "text", "p_cursor_rank" "text", "p_cursor_id" "uuid", "p_cursor_version" "text", "p_limit" integer, "p_query_fingerprint" "text") RETURNS "jsonb"
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
    with matched_keys as materialized (
      select id,version from private.portal_navigation_matched_versions_v1(p_kind,p_query,p_filters)
    ), portal_matches as materialized (
      select f.id,f.version,f.modified_at,null::text as name_value
      from private.portal_catalog_facet_rows_v1 f
      where p_sort<>'name_asc' and f.dataset_kind=p_kind
        and f.state_code in (100,200) and f.facet_contract_version=1
        and (p_filters='{}'::jsonb or (f.id,f.version) in (select id,version from matched_keys))
      union all
      select p.id,p.version,p.modified_at,p.card #>> '{names,0,value}' as name_value
      from private.portal_catalog_search_current_v2 p
      where p_sort='name_asc' and p.dataset_kind=p_kind and p.state_code in (100,200)
        and (p_filters='{}'::jsonb or (p.id,p.version) in (select id,version from matched_keys))
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


  with pattern_matches as materialized (
    select pattern.id,pattern.version
    from private.catalog_portal_process_pattern_versions_v1(v_like_pattern) pattern
    where p_kind='process'
    union all
    select pattern.id,pattern.version
    from private.catalog_portal_flow_pattern_versions_v1(v_like_pattern) pattern
    where p_kind='flow' and not private.portal_catalog_summary_valid_cas_v1(p_query)
  ), portal_facts as materialized (
    -- Inline the exact immutable card-facts expression to avoid one SPI call
    -- per candidate; only narrow facts cross the materialization boundary.
    -- The authoritative legacy pattern/CAS candidate universe is unchanged.
    select p.id,p.version,p.state_code,p.modified_at,
      pg_catalog.jsonb_build_object(
        'nameKey',case when p_sort='name_asc' then card_attrs.names #> '{0,value}' else null::jsonb end,
        'nameExact',exists(select 1 from pg_catalog.jsonb_array_elements(coalesce(card_attrs.names,p.card->'names','[]'::jsonb)) n(item)
          where pg_catalog.lower(pg_catalog.btrim(n.item->>'value'))=p_query),
        'classificationExact',exists(select 1 from pg_catalog.jsonb_array_elements(coalesce(card_attrs.classifications,p.card->'classifications','[]'::jsonb)) c(item)
          where pg_catalog.lower(pg_catalog.btrim(c.item->>'code'))=p_query),
        'casNumber',card_attrs."casNumber"
      ) as facts
    from private.portal_catalog_search_current_v2 p
    cross join lateral pg_catalog.jsonb_to_record(p.card)
      as card_attrs(names jsonb,classifications jsonb,"casNumber" jsonb)
    where p.dataset_kind=p_kind and p.state_code in (100,200)
      and case when p_kind='flow' and private.portal_catalog_summary_valid_cas_v1(p_query) then
        pg_catalog.jsonb_typeof(p.card->'casNumber')='string'
        and p.card->>'casNumber' ~ '^[0-9]{2,7}-[0-9]{2}-[0-9]$'
        and pg_catalog.length(p.card->>'casNumber') between 7 and 12
        and p.card->>'casNumber'=p_query
      else p.id=v_exact_id or (p.id,p.version) in (select id,version from pattern_matches) end
      and (p_filters='{}'::jsonb or (p.id,p.version) in (select id,version from private.portal_navigation_matched_versions_v1(p_kind,'',p_filters)))
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
      end as score
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
    select portal_ordered.*,case p_kind
      when 'process' then (select p.card from private.portal_catalog_search_rows_v2 p
        where p.dataset_kind='process' and p.id=portal_ordered.id and p.version=portal_ordered.version
          and p.state_code=portal_ordered.state_code and p.modified_at=portal_ordered.modified_at
          and p.state_code in (100,200))
      else (select p.card from private.portal_catalog_search_rows_v1 p
        where p.dataset_kind='flow' and p.id=portal_ordered.id and p.version=portal_ordered.version
          and p.state_code=portal_ordered.state_code and p.modified_at=portal_ordered.modified_at
          and p.state_code in (100,200)) end as card
    from portal_ordered
  ), portal_page_facts as materialized (
    select portal_hydrated.*,private.catalog_portal_card_facts_v1(portal_hydrated.card,p_filters,p_query) as page_facts
    from portal_hydrated
  ), portal_decorated as materialized (
    select portal_page_facts.*,
      case
        when pg_catalog.lower(portal_page_facts.id::text) = p_query
          then pg_catalog.jsonb_build_array('exact_id')
        when pg_catalog.lower(coalesce(portal_page_facts.page_facts ->> 'casNumber', '')) = p_query
          then pg_catalog.jsonb_build_array('cas')
        when (portal_page_facts.page_facts ->> 'nameExact')::boolean
          or (portal_page_facts.page_facts ->> 'nameContains')::boolean
          then pg_catalog.jsonb_build_array('name')
        when (portal_page_facts.page_facts ->> 'classificationExact')::boolean
          or (portal_page_facts.page_facts ->> 'classificationContains')::boolean
          then pg_catalog.jsonb_build_array('classification')
        when p_query <> '' then pg_catalog.jsonb_build_array('full_text')
        else '[]'::jsonb
      end as reason_codes
    from portal_page_facts
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
          'kind', case when portal_decorated.reason_codes
            ?| array['exact_id', 'cas', 'classification']
            then 'identifier' else 'lexical' end,
          'score', portal_decorated.score,
          'reasonCodes', portal_decorated.reason_codes
        )
      ) order by portal_decorated.page_rank
    ) filter (where portal_decorated.page_rank <= p_limit), '[]'::jsonb),
    case when max(portal_decorated.page_rank) > p_limit then
      (pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'v', 1,
        'fp', p_query_fingerprint,
        'rankKey', portal_decorated.rank_key,
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
end;
$_$;

ALTER FUNCTION "private"."catalog_portal_search_v2_impl"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_sort" "text", "p_cursor_rank" "text", "p_cursor_id" "uuid", "p_cursor_version" "text", "p_limit" integer, "p_query_fingerprint" "text") OWNER TO "portal_public_executor";

REVOKE ALL ON FUNCTION "private"."catalog_portal_search_v2_impl"("p_kind" "text", "p_query" "text", "p_filters" "jsonb", "p_sort" "text", "p_cursor_rank" "text", "p_cursor_id" "uuid", "p_cursor_version" "text", "p_limit" integer, "p_query_fingerprint" "text") FROM PUBLIC;

GRANT EXECUTE ON FUNCTION private.catalog_portal_search_v2_impl(text,text,jsonb,text,text,uuid,text,integer,text) TO api_internal_executor;

CREATE OR REPLACE FUNCTION "private"."catalog_portal_facets_v2_impl"("p_kind" "text", "p_query" "text", "p_exact_id" "uuid", "p_like_pattern" "text", "p_filters" "jsonb", "p_query_fingerprint" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER PARALLEL RESTRICTED
    SET "search_path" TO ''
    SET "statement_timeout" TO '8s'
    SET "plan_cache_mode" TO 'force_custom_plan'
    SET "row_security" TO 'on'
    AS $$
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

$$;

ALTER FUNCTION "private"."catalog_portal_facets_v2_impl"("p_kind" "text", "p_query" "text", "p_exact_id" "uuid", "p_like_pattern" "text", "p_filters" "jsonb", "p_query_fingerprint" "text") OWNER TO "portal_public_executor";

REVOKE ALL ON FUNCTION "private"."catalog_portal_facets_v2_impl"("p_kind" "text", "p_query" "text", "p_exact_id" "uuid", "p_like_pattern" "text", "p_filters" "jsonb", "p_query_fingerprint" "text") FROM PUBLIC;

reset role;
do $portal_v2_acl_end$
declare r text; before_grant jsonb;
begin
  if pg_catalog.current_setting('portal_v2_cutover.create_added')::boolean then
    revoke create on schema private from portal_public_executor;
  end if;
  if pg_catalog.current_setting('portal_v2_cutover.role_added')::boolean then
    revoke portal_public_executor from api_internal_executor;
  end if;
  foreach r in array array['portal_public_executor','api_internal_executor'] loop
    before_grant:=pg_catalog.current_setting('portal_v2_cutover.'||r||'_postgres_grant')::jsonb;
    if before_grant='null'::jsonb then
      execute pg_catalog.format('revoke %I from postgres',r);
    else
      execute pg_catalog.format('grant %I to postgres with admin %s, inherit %s, set %s',
        r,before_grant->>'admin',before_grant->>'inherit',before_grant->>'set');
    end if;
  end loop;
end;
$portal_v2_acl_end$;
commit;
