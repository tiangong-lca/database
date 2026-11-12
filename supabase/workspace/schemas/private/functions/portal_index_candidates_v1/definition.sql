CREATE OR REPLACE FUNCTION "private"."portal_index_candidates_v1"("p_event" "private"."portal_index_outbox", "p_allowed_brands" "text"[]) RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  with scoped as materialized (
    select s.version
    from private.display_sitemap_rows_v1 as s
    join private.dataset_display_settings as d
      on (d.dataset_kind, d.dataset_id, d.dataset_version::text)
        = (s.dataset_kind, s.id, s.version)
    where (s.dataset_kind, s.id) = (p_event.dataset_kind, p_event.dataset_id)
      and s.contract_version = 1 and d.is_visible and d.brand = any(p_allowed_brands)
  ), decision as (
    select max(version) as latest, coalesce(bool_or(version = p_event.dataset_version), false) as exact,
      p_event.before_brand is not null and p_event.after_brand is null as removed
    from scoped
  ), upsert as (
    select case
      when exact and p_event.after_brand is not null then p_event.dataset_version
      when not exact and removed and p_event.removed_latest and latest < p_event.dataset_version then latest
    end as version
    from decision
  )
  select jsonb_build_object(
    'upserts', case when p_event.provider <> 'baidu_withdrawal' and upsert.version is not null
      then jsonb_build_array(jsonb_build_object(
      'kind', p_event.dataset_kind, 'id', p_event.dataset_id, 'version', upsert.version
    )) else '[]'::jsonb end,
    'withdrawals', case when not exact and removed and (
      p_event.provider <> 'baidu_withdrawal' or not exists (
        select 1 from private.portal_index_outbox as newer
        where newer.provider = 'baidu_withdrawal'
          and (newer.dataset_kind, newer.dataset_id, newer.dataset_version)
            = (p_event.dataset_kind, p_event.dataset_id, p_event.dataset_version)
          and newer.event_id > p_event.event_id
      ))
      then jsonb_build_array(jsonb_build_object(
        'kind', p_event.dataset_kind, 'id', p_event.dataset_id, 'version', p_event.dataset_version
      )) else '[]'::jsonb end
  )
  from decision cross join upsert;
$$;

ALTER FUNCTION "private"."portal_index_candidates_v1"("p_event" "private"."portal_index_outbox", "p_allowed_brands" "text"[]) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."portal_index_candidates_v1"("p_event" "private"."portal_index_outbox", "p_allowed_brands" "text"[]) FROM PUBLIC;
