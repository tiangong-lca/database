-- Database #818: display selection, not authored license metadata, permits Portal reads.
-- Source rows/settings and the frozen legacy Portal generation are unchanged.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '15min';
select private.portal_display_assert_contract_v1();

-- Fence source/settings writers before replacing semantics and cached cards.
-- Readers see either the complete previous generation or the complete new one.
lock table public.processes, public.flows, private.dataset_display_settings
  in share row exclusive mode;
lock table private.display_catalog_search_rows_v1,
  private.display_catalog_search_rows_v2 in share row exclusive mode;

create or replace function private.display_capabilities_v1(
  p_kind text, p_state_code integer, p_json jsonb
) returns jsonb
language sql stable parallel safe set search_path = ''
as $$
  -- Internal DTO builder, not an admission check. Callers enforce exact settings,
  -- root brand scope and reference integrity; LCIA decorators enforce publication.
  -- License, exclusive access and access restrictions are descriptive metadata.
  select jsonb_build_object(
    'metadataVisible', true,
    'exchangesVisible', true,
    'lciaVisible', false,
    'publicArtifactVisible', false,
    'citationVisible', true,
    'policyVersion', 'portal-display-capability-policy.v2',
    'reasonCodes', jsonb_build_array('display_settings_enabled')
  )
$$;

create or replace function private.display_support_capabilities_v1(
  p_kind text, p_state_code integer
) returns jsonb
language sql immutable parallel safe set search_path = ''
as $$
  select jsonb_build_object(
    'exchangesVisible', p_kind in ('flow', 'flowproperty', 'unitgroup'),
    'policyVersion', 'portal-display-capability-policy.v2',
    'reasonCodes', jsonb_build_array('display_settings_enabled')
  )
$$;

CREATE OR REPLACE FUNCTION "private"."display_api_list_process_exchanges_v1"("p_process_id" "uuid", "p_process_version" "text", "p_exchange_kind" "text" DEFAULT 'all'::"text", "p_cursor" "text" DEFAULT NULL::"text", "p_limit" integer DEFAULT 20) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '8s'
    AS $_$
declare
  v_kind text;
  v_process_json jsonb;
  v_process_state integer;
  v_functional_unit jsonb;
  v_cursor jsonb;
  v_cursor_internal integer;
  v_cursor_internal_text text;
  v_cursor_kind text;
  v_rows jsonb;
  v_next_cursor text;
begin
  if pg_catalog.octet_length(coalesce(p_exchange_kind, '')) > 32 then
    raise exception using errcode = '22023', message = 'invalid portal request';
  end if;
  v_kind := lower(btrim(coalesce(p_exchange_kind, 'all')));
  if p_process_id is null
     or p_process_version is null
     or p_process_version !~ '^\d{2}\.\d{2}\.\d{3}$'
     or v_kind not in ('all', 'technosphere', 'elementary', 'waste')
     or p_limit is null
     or p_limit not between 1 and 50 then
    raise exception using errcode = '22023', message = 'invalid portal request';
  end if;
  select row.json, row.state_code
  into v_process_json, v_process_state
  from public.processes as row
  where row.id = p_process_id
    and row.version::text = p_process_version
    and private.portal_display_request_visible_v1('process',row.id,row.version::text)
    and jsonb_typeof(row.json) = 'object'
    and jsonb_typeof(row.json -> 'processDataSet') = 'object'
  limit 1;
  if v_process_json is null then
    return null;
  end if;
  v_functional_unit := private.display_process_functional_unit_v1(v_process_state, v_process_json);

  if p_cursor is not null then
    v_cursor := private.display_cursor_decode_v1(p_cursor);
    if v_cursor is null
       or (select count(*) from jsonb_object_keys(v_cursor)) <> 6
       or v_cursor ->> 'v' <> '1'
       or v_cursor ->> 'processId' <> p_process_id::text
       or v_cursor ->> 'processVersion' <> p_process_version
       or v_cursor ->> 'filterKind' <> v_kind
       or coalesce(v_cursor ->> 'internalId', '') !~ '^(0|[1-9][0-9]{0,5})$'
       or v_cursor ->> 'kind' not in ('technosphere', 'elementary', 'waste') then
      raise exception using errcode = '22023', message = 'invalid portal request';
    end if;
    v_cursor_internal_text := v_cursor ->> 'internalId';
    v_cursor_internal := v_cursor_internal_text::integer;
    v_cursor_kind := v_cursor ->> 'kind';
  end if;

  with raw_exchanges as materialized (
    select exchange.item,
      exchange.item ->> '@dataSetInternalID' as internal_id,
      count(*) over (partition by exchange.item ->> '@dataSetInternalID') as identity_count
    from private.display_json_items_v1(v_process_json #> '{processDataSet,exchanges,exchange}') as exchange(item)
  ), supported as materialized (
    select support -> 'row' as row_data
    from raw_exchanges
    cross join lateral private.display_exchange_support_v1(v_process_state, v_process_json, raw_exchanges.item) as support
    where raw_exchanges.identity_count = 1
      and nullif(v_functional_unit ->> 'amount', '') is not null
      and nullif(v_functional_unit ->> 'unit', '') is not null
      and support is not null
  ), filtered as materialized (
    select supported.row_data,
      (supported.row_data ->> 'internalId')::integer as internal_number,
      supported.row_data ->> 'internalId' as internal_text,
      supported.row_data ->> 'kind' as row_kind
    from supported
    where v_kind = 'all' or supported.row_data ->> 'kind' = v_kind
  ), ordered as materialized (
    select filtered.*,
      row_number() over (order by filtered.internal_number, filtered.internal_text, filtered.row_kind) as page_rank
    from filtered
    where v_cursor is null
      or (filtered.internal_number, filtered.internal_text, filtered.row_kind) >
         (v_cursor_internal, v_cursor_internal_text, v_cursor_kind)
    order by filtered.internal_number, filtered.internal_text, filtered.row_kind
    limit p_limit + 1
  )
  select
    coalesce(jsonb_agg(ordered.row_data order by ordered.page_rank)
      filter (where ordered.page_rank <= p_limit), '[]'::jsonb),
    case when max(ordered.page_rank) > p_limit then private.display_cursor_encode_v1(
      (jsonb_agg(jsonb_build_object(
        'v', 1,
        'processId', p_process_id::text,
        'processVersion', p_process_version,
        'filterKind', v_kind,
        'internalId', ordered.internal_text,
        'kind', ordered.row_kind
      ) order by ordered.page_rank) filter (where ordered.page_rank = p_limit)) -> 0
    ) else null end
  into v_rows, v_next_cursor
  from ordered;

  return jsonb_build_object(
    'schemaVersion', 'portal.public-exchange-page.v1',
    'process', jsonb_build_object('id', p_process_id::text, 'version', p_process_version),
    'processContext', jsonb_build_object(
      'functionalUnit', v_functional_unit,
      'capabilityPolicyVersion', 'portal-display-capability-policy.v2'
    ),
    'rows', v_rows,
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


-- Policy-only rewrite: names/documents/classification/unit/source facts do not change.
-- Fence both parents above, suspend only their exact redundant row derivations,
-- patch the two affected narrow facts set-wise, then restore the same triggers.
-- No reader can observe this intermediate state: all DDL/data is one transaction.
alter table private.display_catalog_search_rows_v1 disable trigger portal_catalog_character_sync_v1;
alter table private.display_catalog_search_rows_v1 disable trigger portal_catalog_facet_sync_v1;
alter table private.display_catalog_search_rows_v1 disable trigger portal_navigation_flow_sync_v1;
alter table private.display_catalog_search_rows_v2 disable trigger portal_catalog_character_sync_v2;
alter table private.display_catalog_search_rows_v2 disable trigger portal_navigation_process_sync_v1;

update private.display_catalog_search_rows_v1
set card = card || jsonb_build_object('accessLevel', 'open',
  'capabilities', private.display_capabilities_v1(dataset_kind, state_code, null))
where card->>'accessLevel' is distinct from 'open'
   or card->'capabilities' is distinct from
      private.display_capabilities_v1(dataset_kind, state_code, null);
update private.display_catalog_search_rows_v2
set card = card || jsonb_build_object('accessLevel', 'open',
  'capabilities', private.display_capabilities_v1(dataset_kind, state_code, null))
where card->>'accessLevel' is distinct from 'open'
   or card->'capabilities' is distinct from
      private.display_capabilities_v1(dataset_kind, state_code, null);

update private.display_catalog_facet_rows_v1 set facet_access_level='open'
where facet_access_level is distinct from 'open';
update private.display_navigation_versions_v1 set access_level='open'
where access_level is distinct from 'open';

alter table private.display_catalog_search_rows_v1 enable trigger portal_catalog_character_sync_v1;
alter table private.display_catalog_search_rows_v1 enable trigger portal_catalog_facet_sync_v1;
alter table private.display_catalog_search_rows_v1 enable trigger portal_navigation_flow_sync_v1;
alter table private.display_catalog_search_rows_v2 enable trigger portal_catalog_character_sync_v2;
alter table private.display_catalog_search_rows_v2 enable trigger portal_navigation_process_sync_v1;

-- Publish the new derivation identity only with fully reconciled policy facts.
update private.portal_display_derivation_contract set identity = case contract_version
  when 1 then 'portal-display-projection.v2'
  when 2 then 'portal-display-composite-projection.v2' end
where contract_version in (1, 2);
do $$
begin
  if exists(select 1 from private.display_catalog_search_rows_v1
    where card->>'accessLevel' is distinct from 'open' or card->'capabilities'
      is distinct from private.display_capabilities_v1(dataset_kind,state_code,null))
  or exists(select 1 from private.display_catalog_search_rows_v2
    where card->>'accessLevel' is distinct from 'open' or card->'capabilities'
      is distinct from private.display_capabilities_v1(dataset_kind,state_code,null))
  or exists(select 1 from private.display_catalog_facet_rows_v1
    where facet_access_level is distinct from 'open')
  or exists(select 1 from private.display_navigation_versions_v1
    where access_level is distinct from 'open') then
    raise exception 'Portal display policy reconciliation failed' using errcode='55000';
  end if;
end $$;
update private.portal_display_contract_manifest
set identity = private.portal_display_contract_identity_v1() where singleton;
select private.portal_display_assert_contract_v1();
notify pgrst, 'reload schema';
commit;
