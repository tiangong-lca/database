-- Bound display sitemap pages to their synchronized narrow projection.
begin;
set local statement_timeout='60s';
set local lock_timeout='5s';
select private.portal_display_assert_contract_v1();

CREATE OR REPLACE FUNCTION "private"."display_api_sitemap_entries_v1"("p_kind" "text", "p_cursor" "text" DEFAULT NULL::"text", "p_limit" integer DEFAULT 1000) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '8s'
    AS $_$
declare
  v_filter_kind text;
  v_cursor jsonb;
  v_cursor_kind text;
  v_cursor_id uuid;
  v_items jsonb;
  v_next_cursor text;
begin
  if pg_catalog.octet_length(coalesce(p_kind, '')) > 32 then
    raise exception using errcode = '22023', message = 'invalid portal request';
  end if;
  v_filter_kind := lower(btrim(coalesce(p_kind, '')));
  if v_filter_kind not in ('process', 'flow', 'all')
     or p_limit is null
     or p_limit not between 1 and 1000 then
    raise exception using errcode = '22023', message = 'invalid portal request';
  end if;
  if p_cursor is not null then
    v_cursor := private.display_cursor_decode_v1(p_cursor);
    if v_cursor is null
       or (select count(*) from jsonb_object_keys(v_cursor)) <> 5
       or v_cursor ->> 'v' <> '1'
       or v_cursor ->> 'filterKind' <> v_filter_kind
       or v_cursor ->> 'kind' not in ('process', 'flow')
       or (v_filter_kind <> 'all' and v_cursor ->> 'kind' <> v_filter_kind)
       or coalesce(v_cursor ->> 'id', '') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or coalesce(v_cursor ->> 'version', '') !~ '^\d{2}\.\d{2}\.\d{3}$' then
      raise exception using errcode = '22023', message = 'invalid portal request';
    end if;
    v_cursor_kind := v_cursor ->> 'kind';
    v_cursor_id := (v_cursor ->> 'id')::uuid;
  end if;

  perform private.display_assert_catalog_projection_contract_v1();
  perform private.display_assert_catalog_facet_contract_v1();
  perform private.display_assert_sitemap_projection_v1();

  -- Forced RLS applies exact visibility and brand scope before choosing latest.
  -- Sitemap pages need only these keys; do not materialize source JSON here.
  with latest as materialized (
    select distinct on (projection.dataset_kind, projection.id)
      projection.dataset_kind as kind,
      projection.id,
      projection.version,
      projection.modified_at
    from private.display_sitemap_rows_v1 as projection
    where (v_filter_kind = 'all' or projection.dataset_kind = v_filter_kind)
      and projection.contract_version = 1
    order by projection.dataset_kind, projection.id, projection.version desc
  ), ordered as materialized (
    select latest.*,
      row_number() over (order by latest.kind, latest.id) as page_rank
    from latest
    where v_cursor is null or (latest.kind, latest.id) > (v_cursor_kind, v_cursor_id)
    order by latest.kind, latest.id
    limit p_limit + 1
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'key', jsonb_build_object(
        'kind', ordered.kind,
        'id', ordered.id::text,
        'version', ordered.version
      ),
      'modifiedAt', private.display_timestamp_v1(ordered.modified_at)
    ) order by ordered.page_rank) filter (where ordered.page_rank <= p_limit), '[]'::jsonb),
    case when max(ordered.page_rank) > p_limit then private.display_cursor_encode_v1(
      (jsonb_agg(jsonb_build_object(
        'v', 1,
        'filterKind', v_filter_kind,
        'kind', ordered.kind,
        'id', ordered.id::text,
        'version', ordered.version
      ) order by ordered.page_rank) filter (where ordered.page_rank = p_limit)) -> 0
    ) else null end
  into v_items, v_next_cursor
  from ordered;

  return jsonb_build_object(
    'schemaVersion', 'portal.public-sitemap-page.v1',
    'items', v_items,
    'nextCursor', v_next_cursor
  );
exception
  when sqlstate '22023' then
    raise exception using errcode = '22023', message = 'invalid portal request';
  when query_canceled then
    raise exception using errcode = 'P0001', message = 'portal catalog unavailable';
  when others then
    raise exception using errcode = 'P0001', message = 'portal catalog unavailable';
end
$_$;

ALTER FUNCTION "private"."display_api_sitemap_entries_v1"("p_kind" "text", "p_cursor" "text", "p_limit" integer) OWNER TO "portal_display_executor";

REVOKE ALL ON FUNCTION "private"."display_api_sitemap_entries_v1"("p_kind" "text", "p_cursor" "text", "p_limit" integer) FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."display_api_sitemap_entries_v1"("p_kind" "text", "p_cursor" "text", "p_limit" integer) TO "portal_public_executor";

update private.portal_display_contract_manifest set identity=private.portal_display_contract_identity_v1() where singleton;
select private.portal_display_assert_contract_v1();
notify pgrst,'reload schema';
commit;
