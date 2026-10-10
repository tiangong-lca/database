-- Database #807: preserve exact settings checks without per-row definer calls.
-- Only private read contracts change. No backfill, activation or timeout increase.
begin;
set local statement_timeout='60s';
set local lock_timeout='5s';
select private.portal_display_assert_contract_v1();

-- The owner bridge exposes only already-visible exact keys to the constrained
-- display executor. Application roles retain no settings or view access.
-- A barrier protects scope predicates; native equality still admits key indexes.
create view private.display_request_visible_settings_v1 with (security_barrier=true) as
select s.dataset_kind,s.dataset_id,s.dataset_version
from private.dataset_display_settings s
where s.is_visible and
 (current_setting('portal.display_global',true)='true' or
 s.brand=any(string_to_array(current_setting('portal.display_brands',true),',')))
and (nullif(current_setting('portal.display_filter_brand',true),'') is null or
 s.brand=current_setting('portal.display_filter_brand',true));
alter view private.display_request_visible_settings_v1 owner to postgres;
revoke all on private.display_request_visible_settings_v1 from public,anon,authenticated,service_role,api_internal_executor,portal_public_executor;
grant select on private.display_request_visible_settings_v1 to portal_display_executor;
do $$declare rel text;begin
 foreach rel in array array['display_catalog_search_rows_v1','display_catalog_search_rows_v2','display_catalog_facet_rows_v1','display_catalog_character_rows_v1','display_catalog_character_rows_v2','display_navigation_versions_v1','display_navigation_membership_v1','display_sitemap_rows_v1'] loop
 execute format('alter policy display_scope on private.%I using (exists(select 1 from private.display_request_visible_settings_v1 s where s.dataset_kind=%I.dataset_kind and s.dataset_id=%I.id and s.dataset_version=%I.version))',rel,rel,rel,rel);
 end loop;
end$$;

-- Include view options in the independent read contract, so removing the
-- security barrier or changing invoker semantics is detected before reads.
create or replace function private.portal_display_contract_identity_v1() returns text
language sql stable security definer set search_path='' as $$
 select md5(jsonb_build_object(
 'routines',(select jsonb_agg(jsonb_build_array(p.oid::regprocedure::text,pg_get_functiondef(p.oid),p.proowner::regrole::text,p.proacl::text) order by p.oid::regprocedure::text)
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where (n.nspname='private' and (p.proname like 'display_%' or p.proname like 'portal_display_%')) or (n.nspname='api' and p.proname like 'portal_%')),
 'relations',(select jsonb_agg(jsonb_build_array(c.relname,c.relrowsecurity,c.relforcerowsecurity,c.reloptions,c.relowner::regrole::text,c.relacl::text,case when c.relkind='v' then pg_get_viewdef(c.oid) else null end,
 (select jsonb_agg(jsonb_build_array(a.attname,format_type(a.atttypid,a.atttypmod),a.attnotnull,a.attacl::text) order by a.attnum) from pg_attribute a where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped),
 (select jsonb_agg(pg_get_constraintdef(x.oid) order by x.conname) from pg_constraint x where x.conrelid=c.oid),
 (select jsonb_agg(jsonb_build_array(pg_get_indexdef(i.indexrelid),i.indisvalid,i.indisready) order by i.indexrelid::regclass::text) from pg_index i where i.indrelid=c.oid),
 (select jsonb_agg(jsonb_build_array(p.polname,p.polcmd,p.polpermissive,p.polroles::text,pg_get_expr(p.polqual,p.polrelid),pg_get_expr(p.polwithcheck,p.polrelid)) order by p.polname) from pg_policy p where p.polrelid=c.oid)) order by c.relname)
 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='private' and c.relkind in ('r','v') and (c.relname like 'display_%' or c.relname='portal_display_derivation_contract')),
 'writers',(select jsonb_agg(jsonb_build_array(t.tgrelid::regclass::text,pg_get_triggerdef(t.oid),t.tgenabled) order by t.tgrelid::regclass::text,t.tgname) from pg_trigger t where t.tgname like 'portal_display_%' or t.tgrelid in (select c.oid from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='private' and c.relname like 'display_%'))
 )::text)
$$;

-- Latest contains at most one exact version per kind/id. Sort these narrow keys
-- before hydrating a UUID example; an OFFSET fence preserves bounded LATERAL
-- lookup. Validate a CAS checksum once per unique group, after its row count.
CREATE OR REPLACE FUNCTION "private"."display_api_catalog_summary_v1"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER PARALLEL RESTRICTED
    SET "search_path" TO ''
    SET "statement_timeout" TO '2s'
    SET "work_mem" TO '32MB'
    SET "plan_cache_mode" TO 'force_custom_plan'
    SET "max_parallel_workers_per_gather" TO '0'
    SET "jit" TO 'off'
    SET "row_security" TO 'on'
    AS $_$

declare
  v_diagnostic_message text;
  v_diagnostic_state text;
  v_counts jsonb;
  v_latest_modified_at text;
  v_uuid_example jsonb;
  v_cas_example jsonb;
  v_classification_example jsonb;
  v_result jsonb;
begin
  perform private.display_assert_catalog_projection_contract_cn1();
  perform private.display_assert_catalog_facet_contract_v1();

  with latest as materialized (
    select distinct on (facet.dataset_kind, facet.id)
      facet.dataset_kind,
      facet.id,
      facet.version,
      facet.modified_at,
      facet.state_code
    from private.display_catalog_facet_rows_v1 as facet
    where facet.facet_contract_version = 1
    order by facet.dataset_kind,
      facet.id,
      facet.version desc,
      facet.modified_at desc,
      facet.state_code desc
  ), counts as (
    select pg_catalog.jsonb_build_object(
        'process', pg_catalog.count(*) filter (
          where latest.dataset_kind = 'process'
        ),
        'flow', pg_catalog.count(*) filter (
          where latest.dataset_kind = 'flow'
        ),
        'total', pg_catalog.count(*)
      ) as value,
      private.display_timestamp_v1(
        pg_catalog.max(latest.modified_at)
      ) as latest_modified_at
    from latest
  ), uuid_candidates as materialized (
    (
      select 0 as preference, 'process'::text as dataset_kind,
        selected.id, selected.version,
        private.display_catalog_summary_label_v1(candidate.card) as label
      from (
        select id, version from latest where dataset_kind = 'process'
        order by id
        offset 0
      ) as selected
      cross join lateral (
        select card from private.display_catalog_search_rows_v2 as row
        where row.dataset_kind = 'process'
          and row.id = selected.id and row.version = selected.version
        offset 0
      ) as candidate
      where pg_catalog.jsonb_array_length(
        private.display_catalog_summary_label_v1(candidate.card)
      ) > 0
      order by selected.id
      limit 1
    )
    union all
    (
      select 1 as preference, 'flow'::text as dataset_kind,
        selected.id, selected.version,
        private.display_catalog_summary_label_v1(candidate.card) as label
      from (
        select id, version from latest where dataset_kind = 'flow'
        order by id
        offset 0
      ) as selected
      cross join lateral (
        select card from private.display_catalog_search_rows_v1 as row
        where row.dataset_kind = 'flow'
          and row.id = selected.id and row.version = selected.version
        offset 0
      ) as candidate
      where pg_catalog.jsonb_array_length(
        private.display_catalog_summary_label_v1(candidate.card)
      ) > 0
      order by selected.id
      limit 1
    )
  ), uuid_example as (
    select pg_catalog.jsonb_build_object(
      'queryKind', 'uuid',
      'datasetKind', candidate.dataset_kind,
      'query', candidate.id::text,
      'label', candidate.label
    ) as value
    from uuid_candidates as candidate
    order by candidate.preference
    limit 1
  ), cas_unique_values as materialized (
    select candidate.card ->> 'casNumber' as cas_number,
      pg_catalog.min(candidate.id::text)::uuid as id
    from private.display_catalog_search_rows_v1 as candidate
    where candidate.dataset_kind = 'flow'
      and pg_catalog.jsonb_typeof(candidate.card -> 'casNumber') = 'string'
      and candidate.card ->> 'casNumber' ~
        '^[0-9]{2,7}-[0-9]{2}-[0-9]$'
      and pg_catalog.length(
        candidate.card ->> 'casNumber'
      ) between 7 and 12
    group by candidate.card ->> 'casNumber'
    having case when pg_catalog.count(*) = 1 then
      private.display_catalog_summary_valid_cas_v1(candidate.card ->> 'casNumber')
      else false end
    order by candidate.card ->> 'casNumber'
    limit 64
  ), cas_candidates as materialized (
    select candidate.dataset_kind,
      candidate.id,
      candidate.version,
      candidate.modified_at,
      candidate.state_code,
      unique_cas.cas_number,
      private.display_catalog_summary_label_v1(candidate.card) as label
    from cas_unique_values as unique_cas
    join private.display_catalog_search_rows_v1 as candidate
      on candidate.dataset_kind = 'flow'
     and candidate.id = unique_cas.id
     and candidate.card ->> 'casNumber' = unique_cas.cas_number
    where exists (
        select 1
        from latest
        where latest.dataset_kind = candidate.dataset_kind
          and latest.id = candidate.id
          and latest.version = candidate.version
      )
      and pg_catalog.jsonb_array_length(
      private.display_catalog_summary_label_v1(candidate.card)
    ) > 0
    order by unique_cas.cas_number,
      candidate.id,
      candidate.version desc,
      candidate.modified_at desc,
      candidate.state_code desc
    limit 1
  ), cas_example as (
    select pg_catalog.jsonb_build_object(
      'queryKind', 'cas',
      'datasetKind', 'flow',
      'query', candidate.cas_number,
      'label', candidate.label
    ) as value
    from cas_candidates as candidate
    order by candidate.id,
      candidate.version desc,
      candidate.modified_at desc,
      candidate.state_code desc
    limit 1
  ), classification_candidates as materialized (
    (
      select 0 as preference,
        candidate.dataset_kind,
        candidate.id,
        candidate.version,
        candidate.modified_at,
        candidate.state_code,
        classification.ordinality,
        pg_catalog.btrim(classification.value ->> 'code') as code,
        private.display_catalog_summary_label_v1(candidate.card) as label
      from private.display_catalog_search_rows_v2 as candidate
      cross join lateral pg_catalog.jsonb_array_elements(
        candidate.card -> 'classifications'
      ) with ordinality as classification(value, ordinality)
      where candidate.dataset_kind = 'process'
        and exists (
          select 1
          from latest
          where latest.dataset_kind = candidate.dataset_kind
            and latest.id = candidate.id
            and latest.version = candidate.version
        )
        and pg_catalog.jsonb_typeof(
          candidate.card -> 'classifications'
        ) = 'array'
        and pg_catalog.jsonb_array_length(
          candidate.card -> 'classifications'
        ) > 0
        and pg_catalog.jsonb_typeof(classification.value) = 'object'
        and pg_catalog.jsonb_typeof(classification.value -> 'code') = 'string'
        and pg_catalog.length(
          pg_catalog.btrim(classification.value ->> 'code')
        ) between 4 and 128
        and pg_catalog.octet_length(
          pg_catalog.btrim(classification.value ->> 'code')
        ) <= 512
        and pg_catalog.btrim(
          classification.value ->> 'code'
        ) !~ '[[:cntrl:]]'
        and pg_catalog.jsonb_array_length(
          private.display_catalog_summary_label_v1(candidate.card)
        ) > 0
      order by candidate.id,
        candidate.version desc,
        candidate.modified_at desc,
        candidate.state_code desc,
        classification.ordinality,
        pg_catalog.btrim(
          classification.value ->> 'code'
        ) collate pg_catalog."C"
      limit 1
    )
    union all
    (
      select 1 as preference,
        candidate.dataset_kind,
        candidate.id,
        candidate.version,
        candidate.modified_at,
        candidate.state_code,
        classification.ordinality,
        pg_catalog.btrim(classification.value ->> 'code') as code,
        private.display_catalog_summary_label_v1(candidate.card) as label
      from private.display_catalog_search_rows_v1 as candidate
      cross join lateral pg_catalog.jsonb_array_elements(
        candidate.card -> 'classifications'
      ) with ordinality as classification(value, ordinality)
      where candidate.dataset_kind = 'flow'
        and exists (
          select 1
          from latest
          where latest.dataset_kind = candidate.dataset_kind
            and latest.id = candidate.id
            and latest.version = candidate.version
        )
        and pg_catalog.jsonb_typeof(
          candidate.card -> 'classifications'
        ) = 'array'
        and pg_catalog.jsonb_array_length(
          candidate.card -> 'classifications'
        ) > 0
        and pg_catalog.jsonb_typeof(classification.value) = 'object'
        and pg_catalog.jsonb_typeof(classification.value -> 'code') = 'string'
        and pg_catalog.length(
          pg_catalog.btrim(classification.value ->> 'code')
        ) between 4 and 128
        and pg_catalog.octet_length(
          pg_catalog.btrim(classification.value ->> 'code')
        ) <= 512
        and pg_catalog.btrim(
          classification.value ->> 'code'
        ) !~ '[[:cntrl:]]'
        and pg_catalog.jsonb_array_length(
          private.display_catalog_summary_label_v1(candidate.card)
        ) > 0
      order by candidate.id,
        candidate.version desc,
        candidate.modified_at desc,
        candidate.state_code desc,
        classification.ordinality,
        pg_catalog.btrim(
          classification.value ->> 'code'
        ) collate pg_catalog."C"
      limit 1
    )
  ), classification_example as (
    select pg_catalog.jsonb_build_object(
      'queryKind', 'classification',
      'datasetKind', candidate.dataset_kind,
      'query', candidate.code,
      'label', candidate.label
    ) as value
    from classification_candidates as candidate
    order by candidate.preference
    limit 1
  )
  select counts.value,
    counts.latest_modified_at,
    uuid_example.value,
    cas_example.value,
    classification_example.value
  into v_counts,
    v_latest_modified_at,
    v_uuid_example,
    v_cas_example,
    v_classification_example
  from counts
  left join uuid_example on true
  left join cas_example on true
  left join classification_example on true;

  select pg_catalog.jsonb_build_object(
    'schemaVersion', 'portal.public-catalog-summary.v1',
    'counts', v_counts,
    'latestModifiedAt', v_latest_modified_at,
    'examples', coalesce(pg_catalog.jsonb_agg(
      example.value order by example.ordinality
    ) filter (where example.value is not null), '[]'::jsonb)
  )
  into v_result
  from (values
    (1, v_uuid_example),
    (2, v_cas_example),
    (3, v_classification_example)
  ) as example(ordinality, value);

  if pg_catalog.octet_length(v_result::text) > 16384 then
    raise exception using
      errcode = '54000',
      message = 'Portal catalog summary exceeded its response budget';
  end if;

  return v_result;
exception
  when query_canceled then
    get stacked diagnostics v_diagnostic_message = MESSAGE_TEXT;
    raise log using message = 'portal read failure diagnostic',
      detail = pg_catalog.jsonb_build_object(
        'schemaVersion', 'portal.read-failure.v1', 'rpc', 'portal_catalog_summary_v1',
        'category', 'cancellation', 'reason', case v_diagnostic_message
          when 'canceling statement due to statement timeout' then 'statement_timeout'
          when 'canceling statement due to user request' then 'cancel_request'
          else 'unknown'
        end
      )::text;
    raise exception using errcode = 'P0001', message = 'portal catalog unavailable';
  when others then
    get stacked diagnostics v_diagnostic_state = RETURNED_SQLSTATE;
    raise log using message = 'portal read failure diagnostic',
      detail = pg_catalog.jsonb_build_object(
        'schemaVersion', 'portal.read-failure.v1', 'rpc', 'portal_catalog_summary_v1',
        'category', 'internal', 'reason', case v_diagnostic_state
          when '54000' then 'response_budget'
          when '55000' then 'contract_drift'
          else 'other'
        end
      )::text;
    raise exception using errcode = 'P0001', message = 'portal catalog unavailable';
end;
$_$;

ALTER FUNCTION "private"."display_api_catalog_summary_v1"() OWNER TO "portal_display_executor";

REVOKE ALL ON FUNCTION "private"."display_api_catalog_summary_v1"() FROM PUBLIC;




grant execute on function private.display_api_catalog_summary_v1() to portal_display_executor;



update private.portal_display_contract_manifest
set identity=private.portal_display_contract_identity_v1() where singleton;
select private.portal_display_assert_contract_v1();
notify pgrst,'reload schema';
commit;
