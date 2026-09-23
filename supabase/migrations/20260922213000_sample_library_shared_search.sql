-- Database #690 / workspace #1464: make the Sample Library an independent
-- data source on the existing list/search/hybrid/reference query surface.

begin;

create or replace function private.sample_library_business_filter_v1(p_filter jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $fn$
  select coalesce(p_filter, '{}'::jsonb)
    - '__sampleLibraryOrigin'
    - '__sampleLibraryPublicationStatus';
$fn$;

alter function private.sample_library_business_filter_v1(jsonb) owner to postgres;
revoke all on function private.sample_library_business_filter_v1(jsonb)
  from public, anon, authenticated, service_role;
grant execute on function private.sample_library_business_filter_v1(jsonb)
  to api_internal_executor, anon, authenticated, service_role;

create or replace function api.sample_library_row_matches_v1(
  p_data_source text,
  p_state_code integer,
  p_user_id uuid,
  p_id uuid,
  p_version character,
  p_filter jsonb,
  p_is_process boolean default false
) returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select lower(coalesce(p_data_source, '')) = 'sl'
    and auth.uid() is not null
    and private.lca_release_is_manager()
    and p_state_code = 100
    and (
      coalesce(p_filter->>'__sampleLibraryOrigin', 'all') = 'all'
      or (p_filter->>'__sampleLibraryOrigin' = 'literature' and p_user_id is null)
      or (p_filter->>'__sampleLibraryOrigin' = 'enterprise' and p_user_id is not null)
    )
    and (
      not p_is_process
      or coalesce(p_filter->>'__sampleLibraryPublicationStatus', 'all') = 'all'
      or (
        p_filter->>'__sampleLibraryPublicationStatus' = 'published'
        and exists (
          select 1
          from private.sample_library_process_publications publication
          where publication.process_id = p_id
            and publication.process_version = p_version
        )
      )
      or (
        p_filter->>'__sampleLibraryPublicationStatus' = 'unpublished'
        and not exists (
          select 1
          from private.sample_library_process_publications publication
          where publication.process_id = p_id
            and publication.process_version = p_version
        )
      )
    );
$fn$;

alter function api.sample_library_row_matches_v1(text, integer, uuid, uuid, character, jsonb, boolean)
  owner to postgres;
revoke all on function api.sample_library_row_matches_v1(text, integer, uuid, uuid, character, jsonb, boolean)
  from public, anon, authenticated, service_role;
grant execute on function api.sample_library_row_matches_v1(text, integer, uuid, uuid, character, jsonb, boolean)
  to api_internal_executor, anon, authenticated, service_role;

create or replace function api.qry_sample_library_process_publications_v1(p_items jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_result jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'code', 'auth_required', 'status', 401,
      'message', 'Authentication required');
  end if;
  if not private.lca_release_is_manager() then
    return jsonb_build_object('ok', false, 'code', 'not_data_product_manager',
      'status', 403, 'message', 'Data product manager role is required');
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) > 100 then
    return jsonb_build_object('ok', false, 'code', 'invalid_items', 'status', 400,
      'message', 'items must be an array with at most 100 Process versions');
  end if;

  select jsonb_build_object(
    'ok', true,
    'data', coalesce(jsonb_agg(jsonb_build_object(
      'id', requested.id,
      'version', requested.version,
      'published', publication.process_id is not null,
      'publishedAt', publication.published_at
    ) order by requested.ordinality), '[]'::jsonb)
  )
  into v_result
  from (
    select
      (item.value->>'id')::uuid as id,
      (item.value->>'version')::character(9) as version,
      item.ordinality
    from jsonb_array_elements(p_items) with ordinality as item(value, ordinality)
    where jsonb_typeof(item.value) = 'object'
      and item.value->>'id' ~* '^[0-9a-f-]{36}$'
      and item.value->>'version' ~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$'
  ) requested
  left join private.sample_library_process_publications publication
    on publication.process_id = requested.id
   and publication.process_version = requested.version;

  return v_result;
end;
$fn$;

alter function api.qry_sample_library_process_publications_v1(jsonb) owner to postgres;
revoke all on function api.qry_sample_library_process_publications_v1(jsonb)
  from public, anon, authenticated, service_role;
grant execute on function api.qry_sample_library_process_publications_v1(jsonb)
  to api_internal_executor, authenticated;

drop function api.qry_sample_library_datasets_v1(text, text, text, integer, integer);
delete from private.api_capability_grants
where routine_identity = 'api.qry_sample_library_datasets_v1(text, text, text, integer, integer)';

-- The shared list/search/hybrid/reference functions are replaced below. Their
-- legacy tg/co/my/te/ex branches are preserved byte-for-byte; only the sl
-- visibility branch and reserved Sample Library filters are added.

DROP FUNCTION IF EXISTS "api"."get_latest_contact_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text");

CREATE OR REPLACE FUNCTION "api"."get_latest_contact_versions"("page_size" bigint DEFAULT 10, "page_current" bigint DEFAULT 1, "data_source" "text" DEFAULT 'tg'::"text", "this_user_id" "text" DEFAULT ''::"text", "team_id_filter" "uuid" DEFAULT NULL::"uuid", "state_code_filter" integer DEFAULT NULL::integer, "sort_by" "text" DEFAULT 'modified_at'::"text", "sort_direction" "text" DEFAULT 'desc'::"text", "sample_origin_filter" text DEFAULT 'all'::text, "sample_publication_status_filter" text DEFAULT 'all'::text) RETURNS TABLE("id" "uuid", "json" "jsonb", "version" character, "modified_at" timestamp with time zone, "team_id" "uuid", "total_count" bigint)
    LANGUAGE "plpgsql"
    SET "search_path" TO 'api', 'private', 'public', 'util', 'extensions', 'extensions', 'pg_temp'
    AS $_$
DECLARE
  normalized_page_size bigint;
  normalized_page_current bigint;
  normalized_sort_by text;
  normalized_sort_direction text;
  normalized_this_user_id uuid;
BEGIN
  normalized_page_size := greatest(coalesce(page_size, 10), 1);
  normalized_page_current := greatest(coalesce(page_current, 1), 1);
  normalized_sort_by := lower(coalesce(sort_by, 'modified_at'));
  normalized_sort_direction := lower(coalesce(sort_direction, 'desc'));
  normalized_this_user_id := CASE
    WHEN coalesce(btrim(this_user_id) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', false)
      THEN btrim(this_user_id)::uuid
    ELSE NULL::uuid
  END;

  RETURN QUERY
    WITH visible_keys AS (
      SELECT c.id, c.version, c.created_at, c.modified_at, c.team_id
      FROM public.contacts c
      WHERE ((((data_source = 'tg' AND c.state_code = 100)) OR api.sample_library_row_matches_v1(data_source, c.state_code, c.user_id, c.id, c.version, '{}'::jsonb, false)) OR (data_source = 'ex' AND c.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL))
        AND (team_id_filter IS NULL OR c.team_id = team_id_filter)
      UNION ALL
      SELECT c.id, c.version, c.created_at, c.modified_at, c.team_id
      FROM public.contacts c
      WHERE data_source = 'co'
        AND c.state_code = 200
        AND (team_id_filter IS NULL OR c.team_id = team_id_filter)
      UNION ALL
      SELECT c.id, c.version, c.created_at, c.modified_at, c.team_id
      FROM public.contacts c
      WHERE data_source = 'my'
        AND normalized_this_user_id IS NOT NULL
        AND c.user_id = normalized_this_user_id
        AND (state_code_filter IS NULL OR c.state_code = state_code_filter)
      UNION ALL
      SELECT c.id, c.version, c.created_at, c.modified_at, c.team_id
      FROM public.contacts c
      WHERE data_source = 'te'
        AND team_id_filter IS NOT NULL
        AND c.team_id = team_id_filter
        AND (state_code_filter IS NULL OR c.state_code = state_code_filter)
    ),
    latest_keys AS (
      SELECT DISTINCT ON (visible_keys.id)
        visible_keys.id,
        visible_keys.version,
        visible_keys.created_at,
        visible_keys.modified_at,
        visible_keys.team_id
      FROM visible_keys
      ORDER BY visible_keys.id, visible_keys.version DESC, visible_keys.modified_at DESC
    ),
    counted_keys AS (
      SELECT latest_keys.*, count(*) OVER()::bigint AS total_count
      FROM latest_keys
      WHERE data_source <> 'sl' OR EXISTS (
        SELECT 1 FROM public.contacts sample_scope_row
        WHERE sample_scope_row.id = latest_keys.id
          AND sample_scope_row.version = latest_keys.version
          AND api.sample_library_row_matches_v1(
            data_source, sample_scope_row.state_code, sample_scope_row.user_id,
            sample_scope_row.id, sample_scope_row.version, jsonb_build_object(
              '__sampleLibraryOrigin', coalesce(sample_origin_filter, 'all'),
              '__sampleLibraryPublicationStatus', coalesce(sample_publication_status_filter, 'all')
            ), false
          )
      )
    ),
    paged_keys AS (
      SELECT counted_keys.*
      FROM counted_keys
      ORDER BY
        CASE
          WHEN normalized_sort_by = 'version' AND normalized_sort_direction = 'asc' THEN counted_keys.version
        END ASC NULLS LAST,
        CASE
          WHEN normalized_sort_by = 'version' AND normalized_sort_direction <> 'asc' THEN counted_keys.version
        END DESC NULLS LAST,
        CASE
          WHEN normalized_sort_by = 'created_at' AND normalized_sort_direction = 'asc' THEN counted_keys.created_at
        END ASC NULLS LAST,
        CASE
          WHEN normalized_sort_by = 'created_at' AND normalized_sort_direction <> 'asc' THEN counted_keys.created_at
        END DESC NULLS LAST,
        CASE
          WHEN normalized_sort_by = 'modified_at' AND normalized_sort_direction = 'asc' THEN counted_keys.modified_at
        END ASC NULLS LAST,
        CASE
          WHEN normalized_sort_by = 'modified_at' AND normalized_sort_direction <> 'asc' THEN counted_keys.modified_at
        END DESC NULLS LAST,
        counted_keys.id
      LIMIT normalized_page_size
      OFFSET (normalized_page_current - 1) * normalized_page_size
    )
    SELECT
      payload.id,
      payload.json,
      payload.version,
      payload.modified_at,
      payload.team_id,
      paged_keys.total_count
    FROM paged_keys
    JOIN public.contacts payload
      ON payload.id = paged_keys.id
     AND payload.version = paged_keys.version
    ORDER BY
      CASE
        WHEN normalized_sort_by = 'version' AND normalized_sort_direction = 'asc' THEN paged_keys.version
      END ASC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'version' AND normalized_sort_direction <> 'asc' THEN paged_keys.version
      END DESC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'created_at' AND normalized_sort_direction = 'asc' THEN paged_keys.created_at
      END ASC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'created_at' AND normalized_sort_direction <> 'asc' THEN paged_keys.created_at
      END DESC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'modified_at' AND normalized_sort_direction = 'asc' THEN paged_keys.modified_at
      END ASC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'modified_at' AND normalized_sort_direction <> 'asc' THEN paged_keys.modified_at
      END DESC NULLS LAST,
      paged_keys.id;
END;
$_$;

ALTER FUNCTION "api"."get_latest_contact_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."get_latest_contact_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."get_latest_contact_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) TO "api_internal_executor";

GRANT ALL ON FUNCTION "api"."get_latest_contact_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) TO "anon";

GRANT ALL ON FUNCTION "api"."get_latest_contact_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) TO "authenticated";

DROP FUNCTION IF EXISTS "api"."get_latest_flow_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "filter_condition" "jsonb", "sort_by" "text", "sort_direction" "text");

CREATE OR REPLACE FUNCTION "api"."get_latest_flow_versions"("page_size" bigint DEFAULT 10, "page_current" bigint DEFAULT 1, "data_source" "text" DEFAULT 'tg'::"text", "this_user_id" "text" DEFAULT ''::"text", "team_id_filter" "uuid" DEFAULT NULL::"uuid", "state_code_filter" integer DEFAULT NULL::integer, "filter_condition" "jsonb" DEFAULT '{}'::"jsonb", "sort_by" "text" DEFAULT 'modified_at'::"text", "sort_direction" "text" DEFAULT 'desc'::"text", "sample_origin_filter" text DEFAULT 'all'::text, "sample_publication_status_filter" text DEFAULT 'all'::text) RETURNS TABLE("id" "uuid", "json" "jsonb", "version" character, "modified_at" timestamp with time zone, "team_id" "uuid", "total_count" bigint)
    LANGUAGE "plpgsql"
    SET "search_path" TO 'api', 'private', 'public', 'util', 'extensions', 'extensions', 'pg_temp'
    SET "statement_timeout" TO '60s'
    AS $_$
DECLARE
  normalized_page_size bigint;
  normalized_page_current bigint;
  normalized_sort_by text;
  normalized_sort_direction text;
  normalized_this_user_id uuid;
  filter_condition_jsonb jsonb;
  flow_type text;
  flow_type_array text[];
  as_input boolean;
  classification_filter jsonb;
BEGIN
  normalized_page_size := greatest(coalesce(page_size, 10), 1);
  normalized_page_current := greatest(coalesce(page_current, 1), 1);
  normalized_sort_by := lower(coalesce(sort_by, 'modified_at'));
  normalized_sort_direction := lower(coalesce(sort_direction, 'desc'));
  normalized_this_user_id := CASE
    WHEN coalesce(btrim(this_user_id) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', false)
      THEN btrim(this_user_id)::uuid
    ELSE NULL::uuid
  END;
  filter_condition_jsonb := coalesce(filter_condition, '{}'::jsonb);

  flow_type := nullif(btrim(filter_condition_jsonb->>'flowType'), '');
  IF flow_type IS NOT NULL THEN
    flow_type_array := string_to_array(flow_type, ',');
  ELSE
    flow_type_array := NULL;
  END IF;
  filter_condition_jsonb := filter_condition_jsonb - 'flowType';

  IF filter_condition_jsonb ? 'asInput' THEN
    as_input := nullif(btrim(filter_condition_jsonb->>'asInput'), '')::boolean;
  ELSE
    as_input := NULL;
  END IF;
  filter_condition_jsonb := filter_condition_jsonb - 'asInput';

  IF jsonb_typeof(filter_condition_jsonb->'classification') = 'array' THEN
    classification_filter := filter_condition_jsonb->'classification';
  ELSE
    classification_filter := '[]'::jsonb;
  END IF;
  filter_condition_jsonb := filter_condition_jsonb - 'classification';

  IF filter_condition_jsonb = '{}'::jsonb
    AND flow_type IS NULL
    AND as_input IS NULL
    AND jsonb_array_length(classification_filter) = 0
  THEN
    RETURN QUERY
      WITH visible_keys AS (
        SELECT f.id, f.version, f.created_at, f.modified_at, f.team_id
        FROM public.flows f
        WHERE ((((data_source = 'tg' AND f.state_code = 100)) OR api.sample_library_row_matches_v1(data_source, f.state_code, f.user_id, f.id, f.version, '{}'::jsonb, false)) OR (data_source = 'ex' AND f.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL))
          AND (team_id_filter IS NULL OR f.team_id = team_id_filter)
        UNION ALL
        SELECT f.id, f.version, f.created_at, f.modified_at, f.team_id
        FROM public.flows f
        WHERE data_source = 'co'
          AND f.state_code = 200
          AND (team_id_filter IS NULL OR f.team_id = team_id_filter)
        UNION ALL
        SELECT f.id, f.version, f.created_at, f.modified_at, f.team_id
        FROM public.flows f
        WHERE data_source = 'my'
          AND normalized_this_user_id IS NOT NULL
          AND f.user_id = normalized_this_user_id
          AND (state_code_filter IS NULL OR f.state_code = state_code_filter)
        UNION ALL
        SELECT f.id, f.version, f.created_at, f.modified_at, f.team_id
        FROM public.flows f
        WHERE data_source = 'te'
          AND team_id_filter IS NOT NULL
          AND f.team_id = team_id_filter
          AND (state_code_filter IS NULL OR f.state_code = state_code_filter)
      ),
      latest_keys AS (
        SELECT DISTINCT ON (visible_keys.id)
          visible_keys.id,
          visible_keys.version,
          visible_keys.created_at,
          visible_keys.modified_at,
          visible_keys.team_id
        FROM visible_keys
        ORDER BY visible_keys.id, visible_keys.version DESC, visible_keys.modified_at DESC
      ),
      counted_keys AS (
        SELECT latest_keys.*, count(*) OVER()::bigint AS total_count
        FROM latest_keys
      WHERE data_source <> 'sl' OR EXISTS (
        SELECT 1 FROM public.flows sample_scope_row
        WHERE sample_scope_row.id = latest_keys.id
          AND sample_scope_row.version = latest_keys.version
          AND api.sample_library_row_matches_v1(
            data_source, sample_scope_row.state_code, sample_scope_row.user_id,
            sample_scope_row.id, sample_scope_row.version, jsonb_build_object(
              '__sampleLibraryOrigin', coalesce(sample_origin_filter, 'all'),
              '__sampleLibraryPublicationStatus', coalesce(sample_publication_status_filter, 'all')
            ), false
          )
      )
      ),
      paged_keys AS (
        SELECT counted_keys.*
        FROM counted_keys
        ORDER BY
          CASE
            WHEN normalized_sort_by = 'version' AND normalized_sort_direction = 'asc' THEN counted_keys.version
          END ASC NULLS LAST,
          CASE
            WHEN normalized_sort_by = 'version' AND normalized_sort_direction <> 'asc' THEN counted_keys.version
          END DESC NULLS LAST,
          CASE
            WHEN normalized_sort_by = 'created_at' AND normalized_sort_direction = 'asc' THEN counted_keys.created_at
          END ASC NULLS LAST,
          CASE
            WHEN normalized_sort_by = 'created_at' AND normalized_sort_direction <> 'asc' THEN counted_keys.created_at
          END DESC NULLS LAST,
          CASE
            WHEN normalized_sort_by = 'modified_at' AND normalized_sort_direction = 'asc' THEN counted_keys.modified_at
          END ASC NULLS LAST,
          CASE
            WHEN normalized_sort_by = 'modified_at' AND normalized_sort_direction <> 'asc' THEN counted_keys.modified_at
          END DESC NULLS LAST,
          counted_keys.id
        LIMIT normalized_page_size
        OFFSET (normalized_page_current - 1) * normalized_page_size
      )
      SELECT
        payload.id,
        payload.json,
        payload.version,
        payload.modified_at,
        payload.team_id,
        paged_keys.total_count
      FROM paged_keys
      JOIN public.flows payload
        ON payload.id = paged_keys.id
       AND payload.version = paged_keys.version
      ORDER BY
        CASE
          WHEN normalized_sort_by = 'version' AND normalized_sort_direction = 'asc' THEN paged_keys.version
        END ASC NULLS LAST,
        CASE
          WHEN normalized_sort_by = 'version' AND normalized_sort_direction <> 'asc' THEN paged_keys.version
        END DESC NULLS LAST,
        CASE
          WHEN normalized_sort_by = 'created_at' AND normalized_sort_direction = 'asc' THEN paged_keys.created_at
        END ASC NULLS LAST,
        CASE
          WHEN normalized_sort_by = 'created_at' AND normalized_sort_direction <> 'asc' THEN paged_keys.created_at
        END DESC NULLS LAST,
        CASE
          WHEN normalized_sort_by = 'modified_at' AND normalized_sort_direction = 'asc' THEN paged_keys.modified_at
        END ASC NULLS LAST,
        CASE
          WHEN normalized_sort_by = 'modified_at' AND normalized_sort_direction <> 'asc' THEN paged_keys.modified_at
        END DESC NULLS LAST,
        paged_keys.id;
    RETURN;
  END IF;

  RETURN QUERY
    WITH visible_rows AS (
      SELECT f.*
      FROM public.flows f
      WHERE ((((data_source = 'tg' AND f.state_code = 100)) OR api.sample_library_row_matches_v1(data_source, f.state_code, f.user_id, f.id, f.version, '{}'::jsonb, false)) OR (data_source = 'ex' AND f.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL))
        AND (team_id_filter IS NULL OR f.team_id = team_id_filter)
      UNION ALL
      SELECT f.*
      FROM public.flows f
      WHERE data_source = 'co'
        AND f.state_code = 200
        AND (team_id_filter IS NULL OR f.team_id = team_id_filter)
      UNION ALL
      SELECT f.*
      FROM public.flows f
      WHERE data_source = 'my'
        AND normalized_this_user_id IS NOT NULL
        AND f.user_id = normalized_this_user_id
        AND (state_code_filter IS NULL OR f.state_code = state_code_filter)
      UNION ALL
      SELECT f.*
      FROM public.flows f
      WHERE data_source = 'te'
        AND team_id_filter IS NOT NULL
        AND f.team_id = team_id_filter
        AND (state_code_filter IS NULL OR f.state_code = state_code_filter)
    ),
    matched_ids AS (
      SELECT DISTINCT visible_rows.id
      FROM visible_rows
      WHERE visible_rows.json @> filter_condition_jsonb
        AND (
          flow_type IS NULL
          OR (visible_rows.json #>> '{flowDataSet,modellingAndValidation,LCIMethod,typeOfDataSet}') = ANY(flow_type_array)
        )
        AND (
          as_input IS NULL
          OR as_input = false
          OR NOT (
            visible_rows.json @> '{"flowDataSet":{"flowInformation":{"dataSetInformation":{"classificationInformation":{"common:elementaryFlowCategorization":{"common:category":[{"#text":"Emissions","@level":"0"}]}}}}}}'
          )
        )
        AND (
          jsonb_array_length(classification_filter) = 0
          OR EXISTS (
            SELECT 1
            FROM jsonb_array_elements(classification_filter) AS selected_class(item)
            WHERE
              (
                selected_class.item->>'scope' = 'elementary'
                AND EXISTS (
                  SELECT 1
                  FROM jsonb_array_elements(
                    CASE jsonb_typeof(visible_rows.json #> '{flowDataSet,flowInformation,dataSetInformation,classificationInformation,common:elementaryFlowCategorization,common:category}')
                      WHEN 'array' THEN visible_rows.json #> '{flowDataSet,flowInformation,dataSetInformation,classificationInformation,common:elementaryFlowCategorization,common:category}'
                      WHEN 'object' THEN jsonb_build_array(visible_rows.json #> '{flowDataSet,flowInformation,dataSetInformation,classificationInformation,common:elementaryFlowCategorization,common:category}')
                      ELSE '[]'::jsonb
                    END
                  ) AS category(item)
                  WHERE category.item->>'@catId' = selected_class.item->>'code'
                )
              )
              OR (
                selected_class.item->>'scope' = 'classification'
                AND EXISTS (
                  SELECT 1
                  FROM jsonb_array_elements(
                    CASE jsonb_typeof(visible_rows.json #> '{flowDataSet,flowInformation,dataSetInformation,classificationInformation,common:classification,common:class}')
                      WHEN 'array' THEN visible_rows.json #> '{flowDataSet,flowInformation,dataSetInformation,classificationInformation,common:classification,common:class}'
                      WHEN 'object' THEN jsonb_build_array(visible_rows.json #> '{flowDataSet,flowInformation,dataSetInformation,classificationInformation,common:classification,common:class}')
                      ELSE '[]'::jsonb
                    END
                  ) AS class_item(item)
                  WHERE class_item.item->>'@classId' = selected_class.item->>'code'
                )
              )
          )
        )
    ),
    latest_rows AS (
      SELECT DISTINCT ON (visible_rows.id)
        visible_rows.id,
        visible_rows.json,
        visible_rows.version,
        visible_rows.created_at,
        visible_rows.modified_at,
        visible_rows.team_id
      FROM visible_rows
      JOIN matched_ids ON matched_ids.id = visible_rows.id
      ORDER BY visible_rows.id, visible_rows.version DESC, visible_rows.modified_at DESC
    ),
    counted_rows AS (
      SELECT latest_rows.*, count(*) OVER()::bigint AS total_count
      FROM latest_rows
      WHERE data_source <> 'sl' OR EXISTS (
        SELECT 1 FROM public.flows sample_scope_row
        WHERE sample_scope_row.id = latest_rows.id
          AND sample_scope_row.version = latest_rows.version
          AND api.sample_library_row_matches_v1(
            data_source, sample_scope_row.state_code, sample_scope_row.user_id,
            sample_scope_row.id, sample_scope_row.version, jsonb_build_object(
              '__sampleLibraryOrigin', coalesce(sample_origin_filter, 'all'),
              '__sampleLibraryPublicationStatus', coalesce(sample_publication_status_filter, 'all')
            ), false
          )
      )
    )
    SELECT
      counted_rows.id,
      counted_rows.json,
      counted_rows.version,
      counted_rows.modified_at,
      counted_rows.team_id,
      counted_rows.total_count
    FROM counted_rows
    ORDER BY
      CASE
        WHEN normalized_sort_by = 'version' AND normalized_sort_direction = 'asc' THEN counted_rows.version
      END ASC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'version' AND normalized_sort_direction <> 'asc' THEN counted_rows.version
      END DESC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'created_at' AND normalized_sort_direction = 'asc' THEN counted_rows.created_at
      END ASC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'created_at' AND normalized_sort_direction <> 'asc' THEN counted_rows.created_at
      END DESC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'modified_at' AND normalized_sort_direction = 'asc' THEN counted_rows.modified_at
      END ASC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'modified_at' AND normalized_sort_direction <> 'asc' THEN counted_rows.modified_at
      END DESC NULLS LAST,
      counted_rows.id
    LIMIT normalized_page_size
    OFFSET (normalized_page_current - 1) * normalized_page_size;
END;
$_$;

ALTER FUNCTION "api"."get_latest_flow_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "filter_condition" "jsonb", "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."get_latest_flow_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "filter_condition" "jsonb", "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."get_latest_flow_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "filter_condition" "jsonb", "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) TO "api_internal_executor";

GRANT ALL ON FUNCTION "api"."get_latest_flow_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "filter_condition" "jsonb", "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) TO "anon";

GRANT ALL ON FUNCTION "api"."get_latest_flow_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "filter_condition" "jsonb", "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) TO "authenticated";

DROP FUNCTION IF EXISTS "api"."get_latest_flowproperty_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text");

CREATE OR REPLACE FUNCTION "api"."get_latest_flowproperty_versions"("page_size" bigint DEFAULT 10, "page_current" bigint DEFAULT 1, "data_source" "text" DEFAULT 'tg'::"text", "this_user_id" "text" DEFAULT ''::"text", "team_id_filter" "uuid" DEFAULT NULL::"uuid", "state_code_filter" integer DEFAULT NULL::integer, "sort_by" "text" DEFAULT 'modified_at'::"text", "sort_direction" "text" DEFAULT 'desc'::"text", "sample_origin_filter" text DEFAULT 'all'::text, "sample_publication_status_filter" text DEFAULT 'all'::text) RETURNS TABLE("id" "uuid", "json" "jsonb", "version" character, "modified_at" timestamp with time zone, "team_id" "uuid", "total_count" bigint)
    LANGUAGE "plpgsql"
    SET "search_path" TO 'api', 'private', 'public', 'util', 'extensions', 'extensions', 'pg_temp'
    AS $_$
DECLARE
  normalized_page_size bigint;
  normalized_page_current bigint;
  normalized_sort_by text;
  normalized_sort_direction text;
  normalized_this_user_id uuid;
BEGIN
  normalized_page_size := greatest(coalesce(page_size, 10), 1);
  normalized_page_current := greatest(coalesce(page_current, 1), 1);
  normalized_sort_by := lower(coalesce(sort_by, 'modified_at'));
  normalized_sort_direction := lower(coalesce(sort_direction, 'desc'));
  normalized_this_user_id := CASE
    WHEN coalesce(btrim(this_user_id) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', false)
      THEN btrim(this_user_id)::uuid
    ELSE NULL::uuid
  END;

  RETURN QUERY
    WITH visible_keys AS (
      SELECT f.id, f.version, f.created_at, f.modified_at, f.team_id
      FROM public.flowproperties f
      WHERE ((((data_source = 'tg' AND f.state_code = 100)) OR api.sample_library_row_matches_v1(data_source, f.state_code, f.user_id, f.id, f.version, '{}'::jsonb, false)) OR (data_source = 'ex' AND f.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL))
        AND (team_id_filter IS NULL OR f.team_id = team_id_filter)
      UNION ALL
      SELECT f.id, f.version, f.created_at, f.modified_at, f.team_id
      FROM public.flowproperties f
      WHERE data_source = 'co'
        AND f.state_code = 200
        AND (team_id_filter IS NULL OR f.team_id = team_id_filter)
      UNION ALL
      SELECT f.id, f.version, f.created_at, f.modified_at, f.team_id
      FROM public.flowproperties f
      WHERE data_source = 'my'
        AND normalized_this_user_id IS NOT NULL
        AND f.user_id = normalized_this_user_id
        AND (state_code_filter IS NULL OR f.state_code = state_code_filter)
      UNION ALL
      SELECT f.id, f.version, f.created_at, f.modified_at, f.team_id
      FROM public.flowproperties f
      WHERE data_source = 'te'
        AND team_id_filter IS NOT NULL
        AND f.team_id = team_id_filter
        AND (state_code_filter IS NULL OR f.state_code = state_code_filter)
    ),
    latest_keys AS (
      SELECT DISTINCT ON (visible_keys.id)
        visible_keys.id,
        visible_keys.version,
        visible_keys.created_at,
        visible_keys.modified_at,
        visible_keys.team_id
      FROM visible_keys
      ORDER BY visible_keys.id, visible_keys.version DESC, visible_keys.modified_at DESC
    ),
    counted_keys AS (
      SELECT latest_keys.*, count(*) OVER()::bigint AS total_count
      FROM latest_keys
      WHERE data_source <> 'sl' OR EXISTS (
        SELECT 1 FROM public.flowproperties sample_scope_row
        WHERE sample_scope_row.id = latest_keys.id
          AND sample_scope_row.version = latest_keys.version
          AND api.sample_library_row_matches_v1(
            data_source, sample_scope_row.state_code, sample_scope_row.user_id,
            sample_scope_row.id, sample_scope_row.version, jsonb_build_object(
              '__sampleLibraryOrigin', coalesce(sample_origin_filter, 'all'),
              '__sampleLibraryPublicationStatus', coalesce(sample_publication_status_filter, 'all')
            ), false
          )
      )
    ),
    paged_keys AS (
      SELECT counted_keys.*
      FROM counted_keys
      ORDER BY
        CASE
          WHEN normalized_sort_by = 'version' AND normalized_sort_direction = 'asc' THEN counted_keys.version
        END ASC NULLS LAST,
        CASE
          WHEN normalized_sort_by = 'version' AND normalized_sort_direction <> 'asc' THEN counted_keys.version
        END DESC NULLS LAST,
        CASE
          WHEN normalized_sort_by = 'created_at' AND normalized_sort_direction = 'asc' THEN counted_keys.created_at
        END ASC NULLS LAST,
        CASE
          WHEN normalized_sort_by = 'created_at' AND normalized_sort_direction <> 'asc' THEN counted_keys.created_at
        END DESC NULLS LAST,
        CASE
          WHEN normalized_sort_by = 'modified_at' AND normalized_sort_direction = 'asc' THEN counted_keys.modified_at
        END ASC NULLS LAST,
        CASE
          WHEN normalized_sort_by = 'modified_at' AND normalized_sort_direction <> 'asc' THEN counted_keys.modified_at
        END DESC NULLS LAST,
        counted_keys.id
      LIMIT normalized_page_size
      OFFSET (normalized_page_current - 1) * normalized_page_size
    )
    SELECT
      payload.id,
      payload.json,
      payload.version,
      payload.modified_at,
      payload.team_id,
      paged_keys.total_count
    FROM paged_keys
    JOIN public.flowproperties payload
      ON payload.id = paged_keys.id
     AND payload.version = paged_keys.version
    ORDER BY
      CASE
        WHEN normalized_sort_by = 'version' AND normalized_sort_direction = 'asc' THEN paged_keys.version
      END ASC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'version' AND normalized_sort_direction <> 'asc' THEN paged_keys.version
      END DESC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'created_at' AND normalized_sort_direction = 'asc' THEN paged_keys.created_at
      END ASC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'created_at' AND normalized_sort_direction <> 'asc' THEN paged_keys.created_at
      END DESC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'modified_at' AND normalized_sort_direction = 'asc' THEN paged_keys.modified_at
      END ASC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'modified_at' AND normalized_sort_direction <> 'asc' THEN paged_keys.modified_at
      END DESC NULLS LAST,
      paged_keys.id;
END;
$_$;

ALTER FUNCTION "api"."get_latest_flowproperty_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."get_latest_flowproperty_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."get_latest_flowproperty_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) TO "api_internal_executor";

GRANT ALL ON FUNCTION "api"."get_latest_flowproperty_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) TO "anon";

GRANT ALL ON FUNCTION "api"."get_latest_flowproperty_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) TO "authenticated";

DROP FUNCTION IF EXISTS "api"."get_latest_lifecyclemodel_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text");

CREATE OR REPLACE FUNCTION "api"."get_latest_lifecyclemodel_versions"("page_size" bigint DEFAULT 10, "page_current" bigint DEFAULT 1, "data_source" "text" DEFAULT 'tg'::"text", "this_user_id" "text" DEFAULT ''::"text", "team_id_filter" "uuid" DEFAULT NULL::"uuid", "state_code_filter" integer DEFAULT NULL::integer, "sort_by" "text" DEFAULT 'modified_at'::"text", "sort_direction" "text" DEFAULT 'desc'::"text", "sample_origin_filter" text DEFAULT 'all'::text, "sample_publication_status_filter" text DEFAULT 'all'::text) RETURNS TABLE("id" "uuid", "json" "jsonb", "version" character, "modified_at" timestamp with time zone, "team_id" "uuid", "total_count" bigint)
    LANGUAGE "plpgsql"
    SET "search_path" TO 'api', 'private', 'public', 'util', 'extensions', 'extensions', 'pg_temp'
    SET "statement_timeout" TO '60s'
    AS $_$
DECLARE
  normalized_page_size bigint;
  normalized_page_current bigint;
  normalized_sort_by text;
  normalized_sort_direction text;
  normalized_this_user_id uuid;
BEGIN
  normalized_page_size := greatest(coalesce(page_size, 10), 1);
  normalized_page_current := greatest(coalesce(page_current, 1), 1);
  normalized_sort_by := lower(coalesce(sort_by, 'modified_at'));
  normalized_sort_direction := lower(coalesce(sort_direction, 'desc'));
  normalized_this_user_id := CASE
    WHEN coalesce(btrim(this_user_id) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', false)
      THEN btrim(this_user_id)::uuid
    ELSE NULL::uuid
  END;

  RETURN QUERY
    WITH visible_rows AS (
      SELECT l.*
      FROM public.lifecyclemodels l
      WHERE ((((data_source = 'tg' AND l.state_code = 100)) OR api.sample_library_row_matches_v1(data_source, l.state_code, l.user_id, l.id, l.version, '{}'::jsonb, false)) OR (data_source = 'ex' AND l.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL))
        AND (team_id_filter IS NULL OR l.team_id = team_id_filter)
      UNION ALL
      SELECT l.*
      FROM public.lifecyclemodels l
      WHERE data_source = 'co'
        AND l.state_code = 200
        AND (team_id_filter IS NULL OR l.team_id = team_id_filter)
      UNION ALL
      SELECT l.*
      FROM public.lifecyclemodels l
      WHERE data_source = 'my'
        AND normalized_this_user_id IS NOT NULL
        AND l.user_id = normalized_this_user_id
        AND (state_code_filter IS NULL OR l.state_code = state_code_filter)
      UNION ALL
      SELECT l.*
      FROM public.lifecyclemodels l
      WHERE data_source = 'te'
        AND team_id_filter IS NOT NULL
        AND l.team_id = team_id_filter
        AND (state_code_filter IS NULL OR l.state_code = state_code_filter)
    ),
    latest_rows AS (
      SELECT DISTINCT ON (visible_rows.id)
        visible_rows.id,
        visible_rows.json,
        visible_rows.version,
        visible_rows.created_at,
        visible_rows.modified_at,
        visible_rows.team_id
      FROM visible_rows
      ORDER BY visible_rows.id, visible_rows.version DESC, visible_rows.modified_at DESC
    ),
    counted_rows AS (
      SELECT latest_rows.*, count(*) OVER()::bigint AS total_count
      FROM latest_rows
      WHERE data_source <> 'sl' OR EXISTS (
        SELECT 1 FROM public.lifecyclemodels sample_scope_row
        WHERE sample_scope_row.id = latest_rows.id
          AND sample_scope_row.version = latest_rows.version
          AND api.sample_library_row_matches_v1(
            data_source, sample_scope_row.state_code, sample_scope_row.user_id,
            sample_scope_row.id, sample_scope_row.version, jsonb_build_object(
              '__sampleLibraryOrigin', coalesce(sample_origin_filter, 'all'),
              '__sampleLibraryPublicationStatus', coalesce(sample_publication_status_filter, 'all')
            ), false
          )
      )
    )
    SELECT
      counted_rows.id,
      counted_rows.json,
      counted_rows.version,
      counted_rows.modified_at,
      counted_rows.team_id,
      counted_rows.total_count
    FROM counted_rows
    ORDER BY
      CASE
        WHEN normalized_sort_by = 'version' AND normalized_sort_direction = 'asc' THEN counted_rows.version
      END ASC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'version' AND normalized_sort_direction <> 'asc' THEN counted_rows.version
      END DESC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'created_at' AND normalized_sort_direction = 'asc' THEN counted_rows.created_at
      END ASC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'created_at' AND normalized_sort_direction <> 'asc' THEN counted_rows.created_at
      END DESC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'modified_at' AND normalized_sort_direction = 'asc' THEN counted_rows.modified_at
      END ASC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'modified_at' AND normalized_sort_direction <> 'asc' THEN counted_rows.modified_at
      END DESC NULLS LAST,
      counted_rows.id
    LIMIT normalized_page_size
    OFFSET (normalized_page_current - 1) * normalized_page_size;
END;
$_$;

ALTER FUNCTION "api"."get_latest_lifecyclemodel_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."get_latest_lifecyclemodel_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."get_latest_lifecyclemodel_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) TO "api_internal_executor";

GRANT ALL ON FUNCTION "api"."get_latest_lifecyclemodel_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) TO "anon";

GRANT ALL ON FUNCTION "api"."get_latest_lifecyclemodel_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) TO "authenticated";

DROP FUNCTION IF EXISTS "api"."get_latest_process_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "type_of_data_set_filter" "text", "sort_by" "text", "sort_direction" "text");

CREATE OR REPLACE FUNCTION "api"."get_latest_process_versions"("page_size" bigint DEFAULT 10, "page_current" bigint DEFAULT 1, "data_source" "text" DEFAULT 'tg'::"text", "this_user_id" "text" DEFAULT ''::"text", "team_id_filter" "uuid" DEFAULT NULL::"uuid", "state_code_filter" integer DEFAULT NULL::integer, "type_of_data_set_filter" "text" DEFAULT 'all'::"text", "sort_by" "text" DEFAULT 'modified_at'::"text", "sort_direction" "text" DEFAULT 'desc'::"text", "sample_origin_filter" text DEFAULT 'all'::text, "sample_publication_status_filter" text DEFAULT 'all'::text) RETURNS TABLE("id" "uuid", "json" "jsonb", "version" character, "modified_at" timestamp with time zone, "team_id" "uuid", "model_id" "uuid", "model_version" character, "total_count" bigint)
    LANGUAGE "plpgsql"
    SET "search_path" TO 'api', 'private', 'public', 'util', 'extensions', 'extensions', 'pg_temp'
    SET "statement_timeout" TO '60s'
    AS $_$
DECLARE
  normalized_page_size bigint;
  normalized_page_current bigint;
  normalized_sort_by text;
  normalized_sort_direction text;
  normalized_this_user_id uuid;
BEGIN
  normalized_page_size := greatest(coalesce(page_size, 10), 1);
  normalized_page_current := greatest(coalesce(page_current, 1), 1);
  normalized_sort_by := lower(coalesce(sort_by, 'modified_at'));
  normalized_sort_direction := lower(coalesce(sort_direction, 'desc'));
  normalized_this_user_id := CASE
    WHEN coalesce(btrim(this_user_id) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', false)
      THEN btrim(this_user_id)::uuid
    ELSE NULL::uuid
  END;

  RETURN QUERY
    WITH visible_rows AS (
      SELECT p.*
      FROM public.processes p
      WHERE ((((data_source = 'tg' AND p.state_code = 100)) OR api.sample_library_row_matches_v1(data_source, p.state_code, p.user_id, p.id, p.version, '{}'::jsonb, true)) OR (data_source = 'ex' AND p.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL))
        AND (team_id_filter IS NULL OR p.team_id = team_id_filter)
      UNION ALL
      SELECT p.*
      FROM public.processes p
      WHERE data_source = 'co'
        AND p.state_code = 200
        AND (team_id_filter IS NULL OR p.team_id = team_id_filter)
      UNION ALL
      SELECT p.*
      FROM public.processes p
      WHERE data_source = 'my'
        AND normalized_this_user_id IS NOT NULL
        AND p.user_id = normalized_this_user_id
        AND (state_code_filter IS NULL OR p.state_code = state_code_filter)
      UNION ALL
      SELECT p.*
      FROM public.processes p
      WHERE data_source = 'te'
        AND team_id_filter IS NOT NULL
        AND p.team_id = team_id_filter
        AND (state_code_filter IS NULL OR p.state_code = state_code_filter)
    ),
    matched_ids AS (
      SELECT DISTINCT visible_rows.id
      FROM visible_rows
      WHERE
        coalesce(type_of_data_set_filter, 'all') = 'all'
        OR visible_rows.json #>> '{processDataSet,modellingAndValidation,LCIMethodAndAllocation,typeOfDataSet}' = type_of_data_set_filter
    ),
    latest_rows AS (
      SELECT DISTINCT ON (visible_rows.id)
        visible_rows.id,
        visible_rows.json,
        visible_rows.version,
        visible_rows.created_at,
        visible_rows.modified_at,
        visible_rows.team_id,
        visible_rows.model_id,
        visible_rows.model_version
      FROM visible_rows
      JOIN matched_ids ON matched_ids.id = visible_rows.id
      ORDER BY visible_rows.id, visible_rows.version DESC, visible_rows.modified_at DESC
    ),
    counted_rows AS (
      SELECT latest_rows.*, count(*) OVER()::bigint AS total_count
      FROM latest_rows
      WHERE data_source <> 'sl' OR EXISTS (
        SELECT 1 FROM public.processes sample_scope_row
        WHERE sample_scope_row.id = latest_rows.id
          AND sample_scope_row.version = latest_rows.version
          AND api.sample_library_row_matches_v1(
            data_source, sample_scope_row.state_code, sample_scope_row.user_id,
            sample_scope_row.id, sample_scope_row.version, jsonb_build_object(
              '__sampleLibraryOrigin', coalesce(sample_origin_filter, 'all'),
              '__sampleLibraryPublicationStatus', coalesce(sample_publication_status_filter, 'all')
            ), true
          )
      )
    )
    SELECT
      counted_rows.id,
      counted_rows.json,
      counted_rows.version,
      counted_rows.modified_at,
      counted_rows.team_id,
      counted_rows.model_id,
      counted_rows.model_version,
      counted_rows.total_count
    FROM counted_rows
    ORDER BY
      CASE
        WHEN normalized_sort_by = 'version' AND normalized_sort_direction = 'asc' THEN counted_rows.version
      END ASC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'version' AND normalized_sort_direction <> 'asc' THEN counted_rows.version
      END DESC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'created_at' AND normalized_sort_direction = 'asc' THEN counted_rows.created_at
      END ASC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'created_at' AND normalized_sort_direction <> 'asc' THEN counted_rows.created_at
      END DESC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'modified_at' AND normalized_sort_direction = 'asc' THEN counted_rows.modified_at
      END ASC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'modified_at' AND normalized_sort_direction <> 'asc' THEN counted_rows.modified_at
      END DESC NULLS LAST,
      counted_rows.id
    LIMIT normalized_page_size
    OFFSET (normalized_page_current - 1) * normalized_page_size;
END;
$_$;

ALTER FUNCTION "api"."get_latest_process_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "type_of_data_set_filter" "text", "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."get_latest_process_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "type_of_data_set_filter" "text", "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."get_latest_process_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "type_of_data_set_filter" "text", "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) TO "api_internal_executor";

GRANT ALL ON FUNCTION "api"."get_latest_process_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "type_of_data_set_filter" "text", "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) TO "anon";

GRANT ALL ON FUNCTION "api"."get_latest_process_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "type_of_data_set_filter" "text", "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) TO "authenticated";

DROP FUNCTION IF EXISTS "api"."get_latest_source_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text");

CREATE OR REPLACE FUNCTION "api"."get_latest_source_versions"("page_size" bigint DEFAULT 10, "page_current" bigint DEFAULT 1, "data_source" "text" DEFAULT 'tg'::"text", "this_user_id" "text" DEFAULT ''::"text", "team_id_filter" "uuid" DEFAULT NULL::"uuid", "state_code_filter" integer DEFAULT NULL::integer, "sort_by" "text" DEFAULT 'modified_at'::"text", "sort_direction" "text" DEFAULT 'desc'::"text", "sample_origin_filter" text DEFAULT 'all'::text, "sample_publication_status_filter" text DEFAULT 'all'::text) RETURNS TABLE("id" "uuid", "json" "jsonb", "version" character, "modified_at" timestamp with time zone, "team_id" "uuid", "total_count" bigint)
    LANGUAGE "plpgsql"
    SET "search_path" TO 'api', 'private', 'public', 'util', 'extensions', 'extensions', 'pg_temp'
    AS $_$
DECLARE
  normalized_page_size bigint;
  normalized_page_current bigint;
  normalized_sort_by text;
  normalized_sort_direction text;
  normalized_this_user_id uuid;
BEGIN
  normalized_page_size := greatest(coalesce(page_size, 10), 1);
  normalized_page_current := greatest(coalesce(page_current, 1), 1);
  normalized_sort_by := lower(coalesce(sort_by, 'modified_at'));
  normalized_sort_direction := lower(coalesce(sort_direction, 'desc'));
  normalized_this_user_id := CASE
    WHEN coalesce(btrim(this_user_id) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', false)
      THEN btrim(this_user_id)::uuid
    ELSE NULL::uuid
  END;

  RETURN QUERY
    WITH visible_keys AS (
      SELECT f.id, f.version, f.created_at, f.modified_at, f.team_id
      FROM public.sources f
      WHERE ((((data_source = 'tg' AND f.state_code = 100)) OR api.sample_library_row_matches_v1(data_source, f.state_code, f.user_id, f.id, f.version, '{}'::jsonb, false)) OR (data_source = 'ex' AND f.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL))
        AND (team_id_filter IS NULL OR f.team_id = team_id_filter)
      UNION ALL
      SELECT f.id, f.version, f.created_at, f.modified_at, f.team_id
      FROM public.sources f
      WHERE data_source = 'co'
        AND f.state_code = 200
        AND (team_id_filter IS NULL OR f.team_id = team_id_filter)
      UNION ALL
      SELECT f.id, f.version, f.created_at, f.modified_at, f.team_id
      FROM public.sources f
      WHERE data_source = 'my'
        AND normalized_this_user_id IS NOT NULL
        AND f.user_id = normalized_this_user_id
        AND (state_code_filter IS NULL OR f.state_code = state_code_filter)
      UNION ALL
      SELECT f.id, f.version, f.created_at, f.modified_at, f.team_id
      FROM public.sources f
      WHERE data_source = 'te'
        AND team_id_filter IS NOT NULL
        AND f.team_id = team_id_filter
        AND (state_code_filter IS NULL OR f.state_code = state_code_filter)
    ),
    latest_keys AS (
      SELECT DISTINCT ON (visible_keys.id)
        visible_keys.id,
        visible_keys.version,
        visible_keys.created_at,
        visible_keys.modified_at,
        visible_keys.team_id
      FROM visible_keys
      ORDER BY visible_keys.id, visible_keys.version DESC, visible_keys.modified_at DESC
    ),
    counted_keys AS (
      SELECT latest_keys.*, count(*) OVER()::bigint AS total_count
      FROM latest_keys
      WHERE data_source <> 'sl' OR EXISTS (
        SELECT 1 FROM public.sources sample_scope_row
        WHERE sample_scope_row.id = latest_keys.id
          AND sample_scope_row.version = latest_keys.version
          AND api.sample_library_row_matches_v1(
            data_source, sample_scope_row.state_code, sample_scope_row.user_id,
            sample_scope_row.id, sample_scope_row.version, jsonb_build_object(
              '__sampleLibraryOrigin', coalesce(sample_origin_filter, 'all'),
              '__sampleLibraryPublicationStatus', coalesce(sample_publication_status_filter, 'all')
            ), false
          )
      )
    ),
    paged_keys AS (
      SELECT counted_keys.*
      FROM counted_keys
      ORDER BY
        CASE
          WHEN normalized_sort_by = 'version' AND normalized_sort_direction = 'asc' THEN counted_keys.version
        END ASC NULLS LAST,
        CASE
          WHEN normalized_sort_by = 'version' AND normalized_sort_direction <> 'asc' THEN counted_keys.version
        END DESC NULLS LAST,
        CASE
          WHEN normalized_sort_by = 'created_at' AND normalized_sort_direction = 'asc' THEN counted_keys.created_at
        END ASC NULLS LAST,
        CASE
          WHEN normalized_sort_by = 'created_at' AND normalized_sort_direction <> 'asc' THEN counted_keys.created_at
        END DESC NULLS LAST,
        CASE
          WHEN normalized_sort_by = 'modified_at' AND normalized_sort_direction = 'asc' THEN counted_keys.modified_at
        END ASC NULLS LAST,
        CASE
          WHEN normalized_sort_by = 'modified_at' AND normalized_sort_direction <> 'asc' THEN counted_keys.modified_at
        END DESC NULLS LAST,
        counted_keys.id
      LIMIT normalized_page_size
      OFFSET (normalized_page_current - 1) * normalized_page_size
    )
    SELECT
      payload.id,
      payload.json,
      payload.version,
      payload.modified_at,
      payload.team_id,
      paged_keys.total_count
    FROM paged_keys
    JOIN public.sources payload
      ON payload.id = paged_keys.id
     AND payload.version = paged_keys.version
    ORDER BY
      CASE
        WHEN normalized_sort_by = 'version' AND normalized_sort_direction = 'asc' THEN paged_keys.version
      END ASC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'version' AND normalized_sort_direction <> 'asc' THEN paged_keys.version
      END DESC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'created_at' AND normalized_sort_direction = 'asc' THEN paged_keys.created_at
      END ASC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'created_at' AND normalized_sort_direction <> 'asc' THEN paged_keys.created_at
      END DESC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'modified_at' AND normalized_sort_direction = 'asc' THEN paged_keys.modified_at
      END ASC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'modified_at' AND normalized_sort_direction <> 'asc' THEN paged_keys.modified_at
      END DESC NULLS LAST,
      paged_keys.id;
END;
$_$;

ALTER FUNCTION "api"."get_latest_source_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."get_latest_source_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."get_latest_source_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) TO "api_internal_executor";

GRANT ALL ON FUNCTION "api"."get_latest_source_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) TO "anon";

GRANT ALL ON FUNCTION "api"."get_latest_source_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) TO "authenticated";

DROP FUNCTION IF EXISTS "api"."get_latest_unitgroup_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text");

CREATE OR REPLACE FUNCTION "api"."get_latest_unitgroup_versions"("page_size" bigint DEFAULT 10, "page_current" bigint DEFAULT 1, "data_source" "text" DEFAULT 'tg'::"text", "this_user_id" "text" DEFAULT ''::"text", "team_id_filter" "uuid" DEFAULT NULL::"uuid", "state_code_filter" integer DEFAULT NULL::integer, "sort_by" "text" DEFAULT 'modified_at'::"text", "sort_direction" "text" DEFAULT 'desc'::"text", "sample_origin_filter" text DEFAULT 'all'::text, "sample_publication_status_filter" text DEFAULT 'all'::text) RETURNS TABLE("id" "uuid", "json" "jsonb", "version" character, "modified_at" timestamp with time zone, "team_id" "uuid", "total_count" bigint)
    LANGUAGE "plpgsql"
    SET "search_path" TO 'api', 'private', 'public', 'util', 'extensions', 'extensions', 'pg_temp'
    AS $_$
DECLARE
  normalized_page_size bigint;
  normalized_page_current bigint;
  normalized_sort_by text;
  normalized_sort_direction text;
  normalized_this_user_id uuid;
BEGIN
  normalized_page_size := greatest(coalesce(page_size, 10), 1);
  normalized_page_current := greatest(coalesce(page_current, 1), 1);
  normalized_sort_by := lower(coalesce(sort_by, 'modified_at'));
  normalized_sort_direction := lower(coalesce(sort_direction, 'desc'));
  normalized_this_user_id := CASE
    WHEN coalesce(btrim(this_user_id) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', false)
      THEN btrim(this_user_id)::uuid
    ELSE NULL::uuid
  END;

  RETURN QUERY
    WITH visible_keys AS (
      SELECT u.id, u.version, u.created_at, u.modified_at, u.team_id
      FROM public.unitgroups u
      WHERE ((((data_source = 'tg' AND u.state_code = 100)) OR api.sample_library_row_matches_v1(data_source, u.state_code, u.user_id, u.id, u.version, '{}'::jsonb, false)) OR (data_source = 'ex' AND u.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL))
        AND (team_id_filter IS NULL OR u.team_id = team_id_filter)
      UNION ALL
      SELECT u.id, u.version, u.created_at, u.modified_at, u.team_id
      FROM public.unitgroups u
      WHERE data_source = 'co'
        AND u.state_code = 200
        AND (team_id_filter IS NULL OR u.team_id = team_id_filter)
      UNION ALL
      SELECT u.id, u.version, u.created_at, u.modified_at, u.team_id
      FROM public.unitgroups u
      WHERE data_source = 'my'
        AND normalized_this_user_id IS NOT NULL
        AND u.user_id = normalized_this_user_id
        AND (state_code_filter IS NULL OR u.state_code = state_code_filter)
      UNION ALL
      SELECT u.id, u.version, u.created_at, u.modified_at, u.team_id
      FROM public.unitgroups u
      WHERE data_source = 'te'
        AND team_id_filter IS NOT NULL
        AND u.team_id = team_id_filter
        AND (state_code_filter IS NULL OR u.state_code = state_code_filter)
    ),
    latest_keys AS (
      SELECT DISTINCT ON (visible_keys.id)
        visible_keys.id,
        visible_keys.version,
        visible_keys.created_at,
        visible_keys.modified_at,
        visible_keys.team_id
      FROM visible_keys
      ORDER BY visible_keys.id, visible_keys.version DESC, visible_keys.modified_at DESC
    ),
    counted_keys AS (
      SELECT latest_keys.*, count(*) OVER()::bigint AS total_count
      FROM latest_keys
      WHERE data_source <> 'sl' OR EXISTS (
        SELECT 1 FROM public.unitgroups sample_scope_row
        WHERE sample_scope_row.id = latest_keys.id
          AND sample_scope_row.version = latest_keys.version
          AND api.sample_library_row_matches_v1(
            data_source, sample_scope_row.state_code, sample_scope_row.user_id,
            sample_scope_row.id, sample_scope_row.version, jsonb_build_object(
              '__sampleLibraryOrigin', coalesce(sample_origin_filter, 'all'),
              '__sampleLibraryPublicationStatus', coalesce(sample_publication_status_filter, 'all')
            ), false
          )
      )
    ),
    paged_keys AS (
      SELECT counted_keys.*
      FROM counted_keys
      ORDER BY
        CASE
          WHEN normalized_sort_by = 'version' AND normalized_sort_direction = 'asc' THEN counted_keys.version
        END ASC NULLS LAST,
        CASE
          WHEN normalized_sort_by = 'version' AND normalized_sort_direction <> 'asc' THEN counted_keys.version
        END DESC NULLS LAST,
        CASE
          WHEN normalized_sort_by = 'created_at' AND normalized_sort_direction = 'asc' THEN counted_keys.created_at
        END ASC NULLS LAST,
        CASE
          WHEN normalized_sort_by = 'created_at' AND normalized_sort_direction <> 'asc' THEN counted_keys.created_at
        END DESC NULLS LAST,
        CASE
          WHEN normalized_sort_by = 'modified_at' AND normalized_sort_direction = 'asc' THEN counted_keys.modified_at
        END ASC NULLS LAST,
        CASE
          WHEN normalized_sort_by = 'modified_at' AND normalized_sort_direction <> 'asc' THEN counted_keys.modified_at
        END DESC NULLS LAST,
        counted_keys.id
      LIMIT normalized_page_size
      OFFSET (normalized_page_current - 1) * normalized_page_size
    )
    SELECT
      payload.id,
      payload.json,
      payload.version,
      payload.modified_at,
      payload.team_id,
      paged_keys.total_count
    FROM paged_keys
    JOIN public.unitgroups payload
      ON payload.id = paged_keys.id
     AND payload.version = paged_keys.version
    ORDER BY
      CASE
        WHEN normalized_sort_by = 'version' AND normalized_sort_direction = 'asc' THEN paged_keys.version
      END ASC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'version' AND normalized_sort_direction <> 'asc' THEN paged_keys.version
      END DESC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'created_at' AND normalized_sort_direction = 'asc' THEN paged_keys.created_at
      END ASC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'created_at' AND normalized_sort_direction <> 'asc' THEN paged_keys.created_at
      END DESC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'modified_at' AND normalized_sort_direction = 'asc' THEN paged_keys.modified_at
      END ASC NULLS LAST,
      CASE
        WHEN normalized_sort_by = 'modified_at' AND normalized_sort_direction <> 'asc' THEN paged_keys.modified_at
      END DESC NULLS LAST,
      paged_keys.id;
END;
$_$;

ALTER FUNCTION "api"."get_latest_unitgroup_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."get_latest_unitgroup_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."get_latest_unitgroup_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) TO "api_internal_executor";

GRANT ALL ON FUNCTION "api"."get_latest_unitgroup_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) TO "anon";

GRANT ALL ON FUNCTION "api"."get_latest_unitgroup_versions"("page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "sort_by" "text", "sort_direction" "text", "sample_origin_filter" text, "sample_publication_status_filter" text) TO "authenticated";

DROP FUNCTION IF EXISTS "api"."search_dataset_json_uuid_mentions"("p_uuid" "uuid", "p_source_entity_kinds" "text"[], "p_data_source" "text", "p_this_user_id" "text", "p_team_id_filter" "uuid", "p_state_code_filter" integer, "p_limit" integer);
DROP FUNCTION IF EXISTS "private"."search_dataset_json_uuid_mentions_impl"("p_uuid" "uuid", "p_source_entity_kinds" "text"[], "p_data_source" "text", "p_this_user_id" "text", "p_team_id_filter" "uuid", "p_state_code_filter" integer, "p_limit" integer);

CREATE OR REPLACE FUNCTION "private"."search_dataset_json_uuid_mentions_impl"("p_uuid" "uuid", "p_source_entity_kinds" "text"[] DEFAULT NULL::"text"[], "p_data_source" "text" DEFAULT 'tg'::"text", "p_this_user_id" "text" DEFAULT ''::"text", "p_team_id_filter" "uuid" DEFAULT NULL::"uuid", "p_state_code_filter" integer DEFAULT NULL::integer, "p_limit" integer DEFAULT 20, "p_sample_origin_filter" text DEFAULT 'all'::text, "p_sample_publication_status_filter" text DEFAULT 'all'::text) RETURNS TABLE("rank" bigint, "source_entity_kind" "text", "source_id" "uuid", "source_version" character, "source_name" "text", "source_modified_at" timestamp with time zone, "source_team_id" "uuid", "source_json" "jsonb", "matched_by" "text", "matched_entity_table" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'private', 'api', 'public', 'util', 'extensions', 'extensions', 'pg_temp'
    SET "statement_timeout" TO '20s'
    AS $_$
declare
  normalized_data_source text;
  effective_user_id uuid;
  can_read_team_filter boolean;
  normalized_limit integer;
  per_entity_limit integer;
  uuid_pattern text;
  normalized_source_entity_kinds text[];
  branches text[] := array[]::text[];
  v_sql text;
  sample_filter jsonb;
begin
  normalized_data_source := coalesce(nullif(lower(btrim(p_data_source)), ''), 'tg');
  effective_user_id := private.dataset_search_effective_user_id(p_this_user_id);
  can_read_team_filter := private.dataset_search_can_read_team_filter(p_team_id_filter, effective_user_id);
  normalized_limit := least(greatest(coalesce(p_limit, 20), 1), 50);
  per_entity_limit := normalized_limit;
  uuid_pattern := '%' || p_uuid::text || '%';
  sample_filter := jsonb_build_object(
    '__sampleLibraryOrigin', coalesce(p_sample_origin_filter, 'all'),
    '__sampleLibraryPublicationStatus', coalesce(p_sample_publication_status_filter, 'all')
  );

  if p_source_entity_kinds is not null then
    select array_agg(distinct normalized_kind order by normalized_kind)
    into normalized_source_entity_kinds
    from (
      select case lower(btrim(kind))
        when 'flow' then 'flow'
        when 'flows' then 'flow'
        when 'process' then 'process'
        when 'processes' then 'process'
        when 'lifecyclemodel' then 'lifecyclemodel'
        when 'lifecyclemodels' then 'lifecyclemodel'
        when 'model' then 'lifecyclemodel'
        when 'models' then 'lifecyclemodel'
        when 'source' then 'source'
        when 'sources' then 'source'
        when 'contact' then 'contact'
        when 'contacts' then 'contact'
        when 'unitgroup' then 'unitgroup'
        when 'unitgroups' then 'unitgroup'
        when 'flowproperty' then 'flowproperty'
        when 'flowproperties' then 'flowproperty'
        else null
      end as normalized_kind
      from unnest(p_source_entity_kinds) as requested(kind)
    ) normalized
    where normalized_kind is not null;

    if coalesce(array_length(normalized_source_entity_kinds, 1), 0) = 0 then
      return;
    end if;
  end if;

  if normalized_source_entity_kinds is null or 'process' = any(normalized_source_entity_kinds) then
    branches := branches || array[$branch$
      (select *
      from (
        select distinct on (d.id)
          10::integer as entity_rank,
          'process'::text as source_entity_kind,
          d.id as source_id,
          d.version as source_version,
          private.dataset_json_display_name('process', d.json) as source_name,
          d.modified_at as source_modified_at,
          d.team_id as source_team_id,
          d.json as source_json,
          'json_uuid_scan'::text as matched_by,
          'public.processes'::text as matched_entity_table
        from public.processes d
        where (
            (((($1 = 'tg' AND d.state_code = 100) OR api.sample_library_row_matches_v1($1, d.state_code, d.user_id, d.id, d.version, $9, true)) OR ($1 = 'ex' AND d.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL)) and ($3 is null or d.team_id = $3))
            or ($1 = 'co' and d.state_code = 200 and ($3 is null or d.team_id = $3))
            or ($1 = 'my' and $2 is not null and d.user_id = $2 and ($4 is null or d.state_code = $4) and d.state_code is distinct from 120)
            or ($1 = 'te' and $3 is not null and $5 and d.team_id = $3 and ($4 is null or d.state_code = $4) and d.state_code is distinct from 120)
          )
        order by d.id, d.version desc, d.modified_at desc
      ) latest
      where latest.source_json::text like $6
      order by latest.source_modified_at desc nulls last, latest.source_id
      limit $8
      )
    $branch$];
  end if;

  if normalized_source_entity_kinds is null or 'flow' = any(normalized_source_entity_kinds) then
    branches := branches || array[$branch$
      (select *
      from (
        select distinct on (d.id)
          20::integer as entity_rank,
          'flow'::text as source_entity_kind,
          d.id as source_id,
          d.version as source_version,
          private.dataset_json_display_name('flow', d.json) as source_name,
          d.modified_at as source_modified_at,
          d.team_id as source_team_id,
          d.json as source_json,
          'json_uuid_scan'::text as matched_by,
          'public.flows'::text as matched_entity_table
        from public.flows d
        where (
            (((($1 = 'tg' AND d.state_code = 100) OR api.sample_library_row_matches_v1($1, d.state_code, d.user_id, d.id, d.version, $9, false)) OR ($1 = 'ex' AND d.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL)) and ($3 is null or d.team_id = $3))
            or ($1 = 'co' and d.state_code = 200 and ($3 is null or d.team_id = $3))
            or ($1 = 'my' and $2 is not null and d.user_id = $2 and ($4 is null or d.state_code = $4))
            or ($1 = 'te' and $3 is not null and $5 and d.team_id = $3 and ($4 is null or d.state_code = $4))
          )
        order by d.id, d.version desc, d.modified_at desc
      ) latest
      where latest.source_json::text like $6
      order by latest.source_modified_at desc nulls last, latest.source_id
      limit $8
      )
    $branch$];
  end if;

  if normalized_source_entity_kinds is null or 'lifecyclemodel' = any(normalized_source_entity_kinds) then
    branches := branches || array[$branch$
      (select *
      from (
        select distinct on (d.id)
          30::integer as entity_rank,
          'lifecyclemodel'::text as source_entity_kind,
          d.id as source_id,
          d.version as source_version,
          private.dataset_json_display_name('lifecyclemodel', d.json) as source_name,
          d.modified_at as source_modified_at,
          d.team_id as source_team_id,
          d.json as source_json,
          'json_uuid_scan'::text as matched_by,
          'public.lifecyclemodels'::text as matched_entity_table
        from public.lifecyclemodels d
        where (
            (((($1 = 'tg' AND d.state_code = 100) OR api.sample_library_row_matches_v1($1, d.state_code, d.user_id, d.id, d.version, $9, false)) OR ($1 = 'ex' AND d.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL)) and ($3 is null or d.team_id = $3))
            or ($1 = 'co' and d.state_code = 200 and ($3 is null or d.team_id = $3))
            or ($1 = 'my' and $2 is not null and d.user_id = $2 and ($4 is null or d.state_code = $4))
            or ($1 = 'te' and $3 is not null and $5 and d.team_id = $3 and ($4 is null or d.state_code = $4))
          )
        order by d.id, d.version desc, d.modified_at desc
      ) latest
      where latest.source_json::text like $6
      order by latest.source_modified_at desc nulls last, latest.source_id
      limit $8
      )
    $branch$];
  end if;

  if normalized_source_entity_kinds is null or 'source' = any(normalized_source_entity_kinds) then
    branches := branches || array[$branch$
      (select *
      from (
        select distinct on (d.id)
          40::integer as entity_rank,
          'source'::text as source_entity_kind,
          d.id as source_id,
          d.version as source_version,
          private.dataset_json_display_name('source', d.json) as source_name,
          d.modified_at as source_modified_at,
          d.team_id as source_team_id,
          d.json as source_json,
          'json_uuid_scan'::text as matched_by,
          'public.sources'::text as matched_entity_table
        from public.sources d
        where (
            (((($1 = 'tg' AND d.state_code = 100) OR api.sample_library_row_matches_v1($1, d.state_code, d.user_id, d.id, d.version, $9, false)) OR ($1 = 'ex' AND d.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL)) and ($3 is null or d.team_id = $3))
            or ($1 = 'co' and d.state_code = 200 and ($3 is null or d.team_id = $3))
            or ($1 = 'my' and $2 is not null and d.user_id = $2 and ($4 is null or d.state_code = $4))
            or ($1 = 'te' and $3 is not null and $5 and d.team_id = $3 and ($4 is null or d.state_code = $4))
          )
        order by d.id, d.version desc, d.modified_at desc
      ) latest
      where latest.source_json::text like $6
      order by latest.source_modified_at desc nulls last, latest.source_id
      limit $8
      )
    $branch$];
  end if;

  if normalized_source_entity_kinds is null or 'contact' = any(normalized_source_entity_kinds) then
    branches := branches || array[$branch$
      (select *
      from (
        select distinct on (d.id)
          50::integer as entity_rank,
          'contact'::text as source_entity_kind,
          d.id as source_id,
          d.version as source_version,
          private.dataset_json_display_name('contact', d.json) as source_name,
          d.modified_at as source_modified_at,
          d.team_id as source_team_id,
          d.json as source_json,
          'json_uuid_scan'::text as matched_by,
          'public.contacts'::text as matched_entity_table
        from public.contacts d
        where (
            (((($1 = 'tg' AND d.state_code = 100) OR api.sample_library_row_matches_v1($1, d.state_code, d.user_id, d.id, d.version, $9, false)) OR ($1 = 'ex' AND d.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL)) and ($3 is null or d.team_id = $3))
            or ($1 = 'co' and d.state_code = 200 and ($3 is null or d.team_id = $3))
            or ($1 = 'my' and $2 is not null and d.user_id = $2 and ($4 is null or d.state_code = $4))
            or ($1 = 'te' and $3 is not null and $5 and d.team_id = $3 and ($4 is null or d.state_code = $4))
          )
        order by d.id, d.version desc, d.modified_at desc
      ) latest
      where latest.source_json::text like $6
      order by latest.source_modified_at desc nulls last, latest.source_id
      limit $8
      )
    $branch$];
  end if;

  if normalized_source_entity_kinds is null or 'unitgroup' = any(normalized_source_entity_kinds) then
    branches := branches || array[$branch$
      (select *
      from (
        select distinct on (d.id)
          60::integer as entity_rank,
          'unitgroup'::text as source_entity_kind,
          d.id as source_id,
          d.version as source_version,
          private.dataset_json_display_name('unitgroup', d.json) as source_name,
          d.modified_at as source_modified_at,
          d.team_id as source_team_id,
          d.json as source_json,
          'json_uuid_scan'::text as matched_by,
          'public.unitgroups'::text as matched_entity_table
        from public.unitgroups d
        where (
            (((($1 = 'tg' AND d.state_code = 100) OR api.sample_library_row_matches_v1($1, d.state_code, d.user_id, d.id, d.version, $9, false)) OR ($1 = 'ex' AND d.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL)) and ($3 is null or d.team_id = $3))
            or ($1 = 'co' and d.state_code = 200 and ($3 is null or d.team_id = $3))
            or ($1 = 'my' and $2 is not null and d.user_id = $2 and ($4 is null or d.state_code = $4))
            or ($1 = 'te' and $3 is not null and $5 and d.team_id = $3 and ($4 is null or d.state_code = $4))
          )
        order by d.id, d.version desc, d.modified_at desc
      ) latest
      where latest.source_json::text like $6
      order by latest.source_modified_at desc nulls last, latest.source_id
      limit $8
      )
    $branch$];
  end if;

  if normalized_source_entity_kinds is null or 'flowproperty' = any(normalized_source_entity_kinds) then
    branches := branches || array[$branch$
      (select *
      from (
        select distinct on (d.id)
          70::integer as entity_rank,
          'flowproperty'::text as source_entity_kind,
          d.id as source_id,
          d.version as source_version,
          private.dataset_json_display_name('flowproperty', d.json) as source_name,
          d.modified_at as source_modified_at,
          d.team_id as source_team_id,
          d.json as source_json,
          'json_uuid_scan'::text as matched_by,
          'public.flowproperties'::text as matched_entity_table
        from public.flowproperties d
        where (
            (((($1 = 'tg' AND d.state_code = 100) OR api.sample_library_row_matches_v1($1, d.state_code, d.user_id, d.id, d.version, $9, false)) OR ($1 = 'ex' AND d.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL)) and ($3 is null or d.team_id = $3))
            or ($1 = 'co' and d.state_code = 200 and ($3 is null or d.team_id = $3))
            or ($1 = 'my' and $2 is not null and d.user_id = $2 and ($4 is null or d.state_code = $4))
            or ($1 = 'te' and $3 is not null and $5 and d.team_id = $3 and ($4 is null or d.state_code = $4))
          )
        order by d.id, d.version desc, d.modified_at desc
      ) latest
      where latest.source_json::text like $6
      order by latest.source_modified_at desc nulls last, latest.source_id
      limit $8
      )
    $branch$];
  end if;

  if coalesce(array_length(branches, 1), 0) = 0 then
    return;
  end if;

  v_sql := format($sql$
    with matched_rows as (
      %s
    )
    select
      row_number() over (
        order by entity_rank, source_modified_at desc nulls last, source_entity_kind, source_id
      )::bigint as rank,
      source_entity_kind,
      source_id,
      source_version,
      source_name,
      source_modified_at,
      source_team_id,
      source_json,
      matched_by,
      matched_entity_table
    from matched_rows
    order by entity_rank, source_modified_at desc nulls last, source_entity_kind, source_id
    limit $7
  $sql$, array_to_string(branches, E'\nunion all\n'));

  return query execute v_sql
    using normalized_data_source, effective_user_id, p_team_id_filter, p_state_code_filter,
          can_read_team_filter, uuid_pattern, normalized_limit, per_entity_limit, sample_filter;
end;
$_$;

ALTER FUNCTION "private"."search_dataset_json_uuid_mentions_impl"("p_uuid" "uuid", "p_source_entity_kinds" "text"[], "p_data_source" "text", "p_this_user_id" "text", "p_team_id_filter" "uuid", "p_state_code_filter" integer, "p_limit" integer, "p_sample_origin_filter" text, "p_sample_publication_status_filter" text) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."search_dataset_json_uuid_mentions_impl"("p_uuid" "uuid", "p_source_entity_kinds" "text"[], "p_data_source" "text", "p_this_user_id" "text", "p_team_id_filter" "uuid", "p_state_code_filter" integer, "p_limit" integer, "p_sample_origin_filter" text, "p_sample_publication_status_filter" text) FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."search_dataset_json_uuid_mentions_impl"("p_uuid" "uuid", "p_source_entity_kinds" "text"[], "p_data_source" "text", "p_this_user_id" "text", "p_team_id_filter" "uuid", "p_state_code_filter" integer, "p_limit" integer, "p_sample_origin_filter" text, "p_sample_publication_status_filter" text) TO "service_role";

GRANT ALL ON FUNCTION "private"."search_dataset_json_uuid_mentions_impl"("p_uuid" "uuid", "p_source_entity_kinds" "text"[], "p_data_source" "text", "p_this_user_id" "text", "p_team_id_filter" "uuid", "p_state_code_filter" integer, "p_limit" integer, "p_sample_origin_filter" text, "p_sample_publication_status_filter" text) TO "api_internal_executor";

GRANT "api_internal_executor" TO "postgres";
GRANT CREATE ON SCHEMA "api" TO "api_internal_executor";
SET ROLE "api_internal_executor";

CREATE OR REPLACE FUNCTION "api"."search_dataset_json_uuid_mentions"("p_uuid" "uuid", "p_source_entity_kinds" "text"[] DEFAULT NULL::"text"[], "p_data_source" "text" DEFAULT 'tg'::"text", "p_this_user_id" "text" DEFAULT ''::"text", "p_team_id_filter" "uuid" DEFAULT NULL::"uuid", "p_state_code_filter" integer DEFAULT NULL::integer, "p_limit" integer DEFAULT 20, "p_sample_origin_filter" text DEFAULT 'all'::text, "p_sample_publication_status_filter" text DEFAULT 'all'::text) RETURNS TABLE("rank" bigint, "source_entity_kind" "text", "source_id" "uuid", "source_version" character, "source_name" "text", "source_modified_at" timestamp with time zone, "source_team_id" "uuid", "source_json" "jsonb", "matched_by" "text", "matched_entity_table" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'api', 'private', 'public', 'util', 'extensions', 'extensions', 'pg_temp'
    SET "statement_timeout" TO '20s'
    AS $$
begin
  return query
    select *
    from private.search_dataset_json_uuid_mentions_impl(
      p_uuid,
      p_source_entity_kinds,
      p_data_source,
      p_this_user_id,
      p_team_id_filter,
      p_state_code_filter,
      p_limit,
      p_sample_origin_filter,
      p_sample_publication_status_filter
    );
end;
$$;

ALTER FUNCTION "api"."search_dataset_json_uuid_mentions"("p_uuid" "uuid", "p_source_entity_kinds" "text"[], "p_data_source" "text", "p_this_user_id" "text", "p_team_id_filter" "uuid", "p_state_code_filter" integer, "p_limit" integer, "p_sample_origin_filter" text, "p_sample_publication_status_filter" text) OWNER TO "api_internal_executor";

REVOKE ALL ON FUNCTION "api"."search_dataset_json_uuid_mentions"("p_uuid" "uuid", "p_source_entity_kinds" "text"[], "p_data_source" "text", "p_this_user_id" "text", "p_team_id_filter" "uuid", "p_state_code_filter" integer, "p_limit" integer, "p_sample_origin_filter" text, "p_sample_publication_status_filter" text) FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."search_dataset_json_uuid_mentions"("p_uuid" "uuid", "p_source_entity_kinds" "text"[], "p_data_source" "text", "p_this_user_id" "text", "p_team_id_filter" "uuid", "p_state_code_filter" integer, "p_limit" integer, "p_sample_origin_filter" text, "p_sample_publication_status_filter" text) TO "anon";

GRANT ALL ON FUNCTION "api"."search_dataset_json_uuid_mentions"("p_uuid" "uuid", "p_source_entity_kinds" "text"[], "p_data_source" "text", "p_this_user_id" "text", "p_team_id_filter" "uuid", "p_state_code_filter" integer, "p_limit" integer, "p_sample_origin_filter" text, "p_sample_publication_status_filter" text) TO "authenticated";

RESET ROLE;
REVOKE CREATE ON SCHEMA "api" FROM "api_internal_executor";
REVOKE "api_internal_executor" FROM "postgres";

CREATE OR REPLACE FUNCTION "api"."_search_simple_dataset_latest"("p_table" "regclass", "query_text" "text", "filter_condition" "jsonb" DEFAULT '{}'::"jsonb", "page_size" bigint DEFAULT 10, "page_current" bigint DEFAULT 1, "data_source" "text" DEFAULT 'tg'::"text", "this_user_id" "text" DEFAULT ''::"text", "team_id_filter" "uuid" DEFAULT NULL::"uuid", "state_code_filter" integer DEFAULT NULL::integer) RETURNS TABLE("rank" bigint, "id" "uuid", "json" "jsonb", "version" character, "modified_at" timestamp with time zone, "team_id" "uuid", "total_count" bigint)
    LANGUAGE "plpgsql"
    SET "search_path" TO 'api', 'private', 'public', 'util', 'extensions', 'extensions', 'pg_temp'
    SET "statement_timeout" TO '60s'
    AS $_$
declare
  normalized_page_size bigint;
  normalized_page_current bigint;
  normalized_this_user_id uuid;
  exact_query_id uuid;
  filter_condition_jsonb jsonb;
  json_filter_clause text;
  v_sql text;
begin
  normalized_page_size := greatest(coalesce(page_size, 10), 1);
  normalized_page_current := greatest(coalesce(page_current, 1), 1);
  normalized_this_user_id := case
    when coalesce(btrim(this_user_id) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', false)
      then btrim(this_user_id)::uuid
    else null::uuid
  end;
  exact_query_id := case
    when coalesce(btrim(query_text) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', false)
      then btrim(query_text)::uuid
    else null::uuid
  end;
  filter_condition_jsonb := coalesce(filter_condition, '{}'::jsonb);
  json_filter_clause := case
    when private.sample_library_business_filter_v1(filter_condition_jsonb) = '{}'::jsonb then ''
    else 'and d.json @> private.sample_library_business_filter_v1($8)'
  end;

  if exact_query_id is not null then
    v_sql := format($sql$
      with matched_ids as (
        select d.id, 1.0::double precision as search_score
        from %1$s d
        where d.id = $1
          and (
            (((($4 = 'tg' AND d.state_code = 100) OR api.sample_library_row_matches_v1($4, d.state_code, d.user_id, d.id, d.version, '{}'::jsonb, false)) OR ($4 = 'ex' AND d.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL)) and ($6 is null or d.team_id = $6))
            or ($4 = 'co' and d.state_code = 200 and ($6 is null or d.team_id = $6))
            or ($4 = 'my' and $5 is not null and d.user_id = $5 and ($7 is null or d.state_code = $7))
            or ($4 = 'te' and $6 is not null and d.team_id = $6 and ($7 is null or d.state_code = $7))
          )
          %2$s
        group by d.id
      ),
      latest_rows as (
        select matched_ids.id, latest_row.json, latest_row.version, latest_row.modified_at, latest_row.team_id, matched_ids.search_score
        from matched_ids
        join lateral (
          select d2.json, d2.version, d2.modified_at, d2.team_id
          from %1$s d2
          where d2.id = matched_ids.id
            and (
              (((($4 = 'tg' AND d2.state_code = 100) OR api.sample_library_row_matches_v1($4, d2.state_code, d2.user_id, d2.id, d2.version, $8, false)) OR ($4 = 'ex' AND d2.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL)) and ($6 is null or d2.team_id = $6))
              or ($4 = 'co' and d2.state_code = 200 and ($6 is null or d2.team_id = $6))
              or ($4 = 'my' and $5 is not null and d2.user_id = $5 and ($7 is null or d2.state_code = $7))
              or ($4 = 'te' and $6 is not null and d2.team_id = $6 and ($7 is null or d2.state_code = $7))
            )
          order by d2.version desc, d2.modified_at desc
          limit 1
        ) latest_row on true
      ),
      counted_rows as (
        select latest_rows.*, count(*) over()::bigint as total_count
        from latest_rows
      )
      select 1::bigint as rank, counted_rows.id, counted_rows.json, counted_rows.version, counted_rows.modified_at, counted_rows.team_id, counted_rows.total_count
      from counted_rows
      order by rank, counted_rows.id
      limit $2
      offset ($3 - 1) * $2
    $sql$, p_table, json_filter_clause);

    return query execute v_sql
      using exact_query_id, normalized_page_size, normalized_page_current,
            data_source, normalized_this_user_id, team_id_filter, state_code_filter,
            filter_condition_jsonb;
    return;
  end if;

  json_filter_clause := case
    when private.sample_library_business_filter_v1(filter_condition_jsonb) = '{}'::jsonb then ''
    else 'and d.json @> private.sample_library_business_filter_v1($2)'
  end;

  v_sql := format($sql$
    with text_matches as materialized (
      select d.id,
             d.json,
             d.state_code,
             d.team_id,
             d.user_id,
             d.version,
             pgroonga_score(d.tableoid, d.ctid) as search_score
      from %1$s d
      where d.search_text &@~ $1
    ),
    matched_ids as (
      select d.id, max(d.search_score) as search_score
      from text_matches d
      where (
          (((($5 = 'tg' AND d.state_code = 100) OR api.sample_library_row_matches_v1($5, d.state_code, d.user_id, d.id, d.version, '{}'::jsonb, false)) OR ($5 = 'ex' AND d.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL)) and ($7 is null or d.team_id = $7))
          or ($5 = 'co' and d.state_code = 200 and ($7 is null or d.team_id = $7))
          or ($5 = 'my' and $6 is not null and d.user_id = $6 and ($8 is null or d.state_code = $8))
          or ($5 = 'te' and $7 is not null and d.team_id = $7 and ($8 is null or d.state_code = $8))
        )
        %2$s
      group by d.id
    ),
    latest_rows as (
      select matched_ids.id, latest_row.json, latest_row.version, latest_row.modified_at, latest_row.team_id, matched_ids.search_score
      from matched_ids
      join lateral (
        select d2.json, d2.version, d2.modified_at, d2.team_id
        from %1$s d2
        where d2.id = matched_ids.id
          and (
            (((($5 = 'tg' AND d2.state_code = 100) OR api.sample_library_row_matches_v1($5, d2.state_code, d2.user_id, d2.id, d2.version, $2, false)) OR ($5 = 'ex' AND d2.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL)) and ($7 is null or d2.team_id = $7))
            or ($5 = 'co' and d2.state_code = 200 and ($7 is null or d2.team_id = $7))
            or ($5 = 'my' and $6 is not null and d2.user_id = $6 and ($8 is null or d2.state_code = $8))
            or ($5 = 'te' and $7 is not null and d2.team_id = $7 and ($8 is null or d2.state_code = $8))
          )
        order by d2.version desc, d2.modified_at desc
        limit 1
      ) latest_row on true
    ),
    counted_rows as (
      select latest_rows.*, count(*) over()::bigint as total_count
      from latest_rows
    ),
    ranked_rows as (
      select rank() over (order by counted_rows.search_score desc, counted_rows.modified_at desc, counted_rows.id)::bigint as rank,
             counted_rows.*
      from counted_rows
    )
    select ranked_rows.rank, ranked_rows.id, ranked_rows.json, ranked_rows.version, ranked_rows.modified_at, ranked_rows.team_id, ranked_rows.total_count
    from ranked_rows
    order by ranked_rows.rank, ranked_rows.id
    limit $3
    offset ($4 - 1) * $3
  $sql$, p_table, json_filter_clause);

  return query execute v_sql
    using query_text, filter_condition_jsonb, normalized_page_size, normalized_page_current,
          data_source, normalized_this_user_id, team_id_filter, state_code_filter;
end;
$_$;

ALTER FUNCTION "api"."_search_simple_dataset_latest"("p_table" "regclass", "query_text" "text", "filter_condition" "jsonb", "page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."_search_simple_dataset_latest"("p_table" "regclass", "query_text" "text", "filter_condition" "jsonb", "page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer) FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."_search_simple_dataset_latest"("p_table" "regclass", "query_text" "text", "filter_condition" "jsonb", "page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer) TO "api_internal_executor";

CREATE OR REPLACE FUNCTION "private"."search_flows_latest_impl"("query_text" "text", "filter_condition" "jsonb" DEFAULT '{}'::"jsonb", "page_size" bigint DEFAULT 10, "page_current" bigint DEFAULT 1, "data_source" "text" DEFAULT 'tg'::"text", "this_user_id" "text" DEFAULT ''::"text", "team_id_filter" "uuid" DEFAULT NULL::"uuid", "state_code_filter" integer DEFAULT NULL::integer, "query_terms" "text"[] DEFAULT NULL::"text"[]) RETURNS TABLE("rank" bigint, "id" "uuid", "json" "jsonb", "version" character, "modified_at" timestamp with time zone, "team_id" "uuid", "total_count" bigint)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'private', 'api', 'public', 'util', 'extensions', 'extensions', 'pg_temp'
    SET "statement_timeout" TO '60s'
    AS $_$
declare
  normalized_page_size bigint;
  normalized_page_current bigint;
  normalized_data_source text;
  effective_user_id uuid;
  can_read_team_filter boolean;
  exact_query_id uuid;
  filter_condition_jsonb jsonb;
  flow_type text;
  flow_type_array text[];
  as_input boolean;
  classification_filter jsonb;
  json_filter_clause text;
  v_sql text;
  escaped_query_terms text[];
  text_match_clause text;
begin
  normalized_page_size := greatest(coalesce(page_size, 10), 1);
  normalized_page_current := greatest(coalesce(page_current, 1), 1);
  normalized_data_source := coalesce(nullif(lower(btrim(data_source)), ''), 'tg');
  effective_user_id := private.dataset_search_effective_user_id(this_user_id);
  can_read_team_filter := private.dataset_search_can_read_team_filter(team_id_filter, effective_user_id);
  exact_query_id := case
    when coalesce(btrim(query_text) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', false)
      then btrim(query_text)::uuid
    else null::uuid
  end;
  filter_condition_jsonb := coalesce(filter_condition, '{}'::jsonb);
  escaped_query_terms := private.pgroonga_escape_query_terms(query_terms);
  if cardinality(escaped_query_terms) = 0 then
    escaped_query_terms := private.pgroonga_escape_query_terms(array[query_text]);
  end if;
  text_match_clause := 'where f.search_text &@~| $14';

  flow_type := nullif(btrim(filter_condition_jsonb->>'flowType'), '');
  if flow_type is not null then
    flow_type_array := string_to_array(flow_type, ',');
  else
    flow_type_array := null;
  end if;
  filter_condition_jsonb := filter_condition_jsonb - 'flowType';

  if filter_condition_jsonb ? 'asInput' then
    as_input := nullif(btrim(filter_condition_jsonb->>'asInput'), '')::boolean;
  else
    as_input := null;
  end if;
  filter_condition_jsonb := filter_condition_jsonb - 'asInput';

  if jsonb_typeof(filter_condition_jsonb->'classification') = 'array' then
    classification_filter := filter_condition_jsonb->'classification';
  else
    classification_filter := '[]'::jsonb;
  end if;
  filter_condition_jsonb := filter_condition_jsonb - 'classification';

  if exact_query_id is not null then
    return query
      with matched_ids as (
        select f.id, 1.0::double precision as search_score
        from public.flows f
        where f.id = exact_query_id
          and f.json @> private.sample_library_business_filter_v1(filter_condition_jsonb)
          and (
            ((((normalized_data_source = 'tg' AND f.state_code = 100) OR api.sample_library_row_matches_v1(normalized_data_source, f.state_code, f.user_id, f.id, f.version, '{}'::jsonb, false)) OR (normalized_data_source = 'ex' AND f.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL)) and (team_id_filter is null or f.team_id = team_id_filter))
            or (normalized_data_source = 'co' and f.state_code = 200 and (team_id_filter is null or f.team_id = team_id_filter))
            or (normalized_data_source = 'my' and effective_user_id is not null and f.user_id = effective_user_id and (state_code_filter is null or f.state_code = state_code_filter))
            or (normalized_data_source = 'te' and team_id_filter is not null and can_read_team_filter and f.team_id = team_id_filter and (state_code_filter is null or f.state_code = state_code_filter))
          )
          and (
            flow_type is null
            or (f.json #>> '{flowDataSet,modellingAndValidation,LCIMethod,typeOfDataSet}') = any(flow_type_array)
          )
          and (
            as_input is null
            or as_input = false
            or not (
              f.json @> '{"flowDataSet":{"flowInformation":{"dataSetInformation":{"classificationInformation":{"common:elementaryFlowCategorization":{"common:category":[{"#text":"Emissions","@level":"0"}]}}}}}}'
            )
          )
          and (
            jsonb_array_length(classification_filter) = 0
            or exists (
              select 1
              from jsonb_array_elements(classification_filter) as selected_class(item)
              where
                (
                  selected_class.item->>'scope' = 'elementary'
                  and exists (
                    select 1
                    from jsonb_array_elements(
                      case jsonb_typeof(f.json #> '{flowDataSet,flowInformation,dataSetInformation,classificationInformation,common:elementaryFlowCategorization,common:category}')
                        when 'array' then f.json #> '{flowDataSet,flowInformation,dataSetInformation,classificationInformation,common:elementaryFlowCategorization,common:category}'
                        when 'object' then jsonb_build_array(f.json #> '{flowDataSet,flowInformation,dataSetInformation,classificationInformation,common:elementaryFlowCategorization,common:category}')
                        else '[]'::jsonb
                      end
                    ) as category(item)
                    where category.item->>'@catId' = selected_class.item->>'code'
                  )
                )
                or (
                  selected_class.item->>'scope' = 'classification'
                  and exists (
                    select 1
                    from jsonb_array_elements(
                      case jsonb_typeof(f.json #> '{flowDataSet,flowInformation,dataSetInformation,classificationInformation,common:classification,common:class}')
                        when 'array' then f.json #> '{flowDataSet,flowInformation,dataSetInformation,classificationInformation,common:classification,common:class}'
                        when 'object' then jsonb_build_array(f.json #> '{flowDataSet,flowInformation,dataSetInformation,classificationInformation,common:classification,common:class}')
                        else '[]'::jsonb
                      end
                    ) as class_item(item)
                    where class_item.item->>'@classId' = selected_class.item->>'code'
                  )
                )
            )
          )
        group by f.id
      ),
      latest_rows as (
        select matched_ids.id, latest_row.json, latest_row.version, latest_row.modified_at, latest_row.team_id, matched_ids.search_score
        from matched_ids
        join lateral (
          select f2.json, f2.version, f2.modified_at, f2.team_id
          from public.flows f2
          where f2.id = matched_ids.id
            and (
              ((((normalized_data_source = 'tg' AND f2.state_code = 100) OR api.sample_library_row_matches_v1(normalized_data_source, f2.state_code, f2.user_id, f2.id, f2.version, filter_condition_jsonb, false)) OR (normalized_data_source = 'ex' AND f2.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL)) and (team_id_filter is null or f2.team_id = team_id_filter))
              or (normalized_data_source = 'co' and f2.state_code = 200 and (team_id_filter is null or f2.team_id = team_id_filter))
              or (normalized_data_source = 'my' and effective_user_id is not null and f2.user_id = effective_user_id and (state_code_filter is null or f2.state_code = state_code_filter))
              or (normalized_data_source = 'te' and team_id_filter is not null and can_read_team_filter and f2.team_id = team_id_filter and (state_code_filter is null or f2.state_code = state_code_filter))
            )
          order by f2.version desc, f2.modified_at desc
          limit 1
        ) latest_row on true
      ),
      counted_rows as (
        select latest_rows.*, count(*) over()::bigint as total_count
        from latest_rows
      )
      select 1::bigint as rank, counted_rows.id, counted_rows.json, counted_rows.version, counted_rows.modified_at, counted_rows.team_id, counted_rows.total_count
      from counted_rows
      order by rank, counted_rows.id
      limit normalized_page_size
      offset (normalized_page_current - 1) * normalized_page_size;
    return;
  end if;

  json_filter_clause := case
    when private.sample_library_business_filter_v1(filter_condition_jsonb) = '{}'::jsonb then ''
    else 'and f.json @> private.sample_library_business_filter_v1($2)'
  end;

  v_sql := format($sql$
    with text_matches as materialized (
      select f.id,
             f.version,
             f.json,
             f.state_code,
             f.team_id,
             f.user_id,
             pgroonga_score(f.tableoid, f.ctid) as search_score
      from public.flows f
      %s
    ),
    matched_ids as (
      select f.id, max(f.search_score) as search_score
      from text_matches f
      where (
          (((($5 = 'tg' AND f.state_code = 100) OR api.sample_library_row_matches_v1($5, f.state_code, f.user_id, f.id, f.version, '{}'::jsonb, false)) OR ($5 = 'ex' AND f.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL)) and ($7 is null or f.team_id = $7))
          or ($5 = 'co' and f.state_code = 200 and ($7 is null or f.team_id = $7))
          or ($5 = 'my' and $6 is not null and f.user_id = $6 and ($8 is null or f.state_code = $8))
          or ($5 = 'te' and $7 is not null and $9 and f.team_id = $7 and ($8 is null or f.state_code = $8))
        )
        %s
        and (
          $10 is null
          or (f.json #>> '{flowDataSet,modellingAndValidation,LCIMethod,typeOfDataSet}') = any($11)
        )
        and (
          $12 is null
          or $12 = false
          or not (
            f.json @> '{"flowDataSet":{"flowInformation":{"dataSetInformation":{"classificationInformation":{"common:elementaryFlowCategorization":{"common:category":[{"#text":"Emissions","@level":"0"}]}}}}}}'
          )
        )
        and (
          jsonb_array_length($13) = 0
          or exists (
            select 1
            from jsonb_array_elements($13) as selected_class(item)
            where
              (
                selected_class.item->>'scope' = 'elementary'
                and exists (
                  select 1
                  from jsonb_array_elements(
                    case jsonb_typeof(f.json #> '{flowDataSet,flowInformation,dataSetInformation,classificationInformation,common:elementaryFlowCategorization,common:category}')
                      when 'array' then f.json #> '{flowDataSet,flowInformation,dataSetInformation,classificationInformation,common:elementaryFlowCategorization,common:category}'
                      when 'object' then jsonb_build_array(f.json #> '{flowDataSet,flowInformation,dataSetInformation,classificationInformation,common:elementaryFlowCategorization,common:category}')
                      else '[]'::jsonb
                    end
                  ) as category(item)
                  where category.item->>'@catId' = selected_class.item->>'code'
                )
              )
              or (
                selected_class.item->>'scope' = 'classification'
                and exists (
                  select 1
                  from jsonb_array_elements(
                    case jsonb_typeof(f.json #> '{flowDataSet,flowInformation,dataSetInformation,classificationInformation,common:classification,common:class}')
                      when 'array' then f.json #> '{flowDataSet,flowInformation,dataSetInformation,classificationInformation,common:classification,common:class}'
                      when 'object' then jsonb_build_array(f.json #> '{flowDataSet,flowInformation,dataSetInformation,classificationInformation,common:classification,common:class}')
                      else '[]'::jsonb
                    end
                  ) as class_item(item)
                  where class_item.item->>'@classId' = selected_class.item->>'code'
                )
              )
          )
        )
      group by f.id
    ),
    latest_rows as (
      select matched_ids.id, latest_row.json, latest_row.version, latest_row.modified_at, latest_row.team_id, matched_ids.search_score
      from matched_ids
      join lateral (
        select f2.json, f2.version, f2.modified_at, f2.team_id
        from public.flows f2
        where f2.id = matched_ids.id
          and (
            (((($5 = 'tg' AND f2.state_code = 100) OR api.sample_library_row_matches_v1($5, f2.state_code, f2.user_id, f2.id, f2.version, $2, false)) OR ($5 = 'ex' AND f2.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL)) and ($7 is null or f2.team_id = $7))
            or ($5 = 'co' and f2.state_code = 200 and ($7 is null or f2.team_id = $7))
            or ($5 = 'my' and $6 is not null and f2.user_id = $6 and ($8 is null or f2.state_code = $8))
            or ($5 = 'te' and $7 is not null and $9 and f2.team_id = $7 and ($8 is null or f2.state_code = $8))
          )
        order by f2.version desc, f2.modified_at desc
        limit 1
      ) latest_row on true
    ),
    counted_rows as (
      select latest_rows.*, count(*) over()::bigint as total_count
      from latest_rows
    ),
    ranked_rows as (
      select rank() over (order by counted_rows.search_score desc, counted_rows.modified_at desc, counted_rows.id)::bigint as rank,
             counted_rows.*
      from counted_rows
    )
    select ranked_rows.rank, ranked_rows.id, ranked_rows.json, ranked_rows.version, ranked_rows.modified_at, ranked_rows.team_id, ranked_rows.total_count
    from ranked_rows
    order by ranked_rows.rank, ranked_rows.id
    limit $3
    offset ($4 - 1) * $3
  $sql$, text_match_clause, json_filter_clause);

  return query execute v_sql
    using query_text, filter_condition_jsonb, normalized_page_size, normalized_page_current,
          normalized_data_source, effective_user_id, team_id_filter, state_code_filter,
          can_read_team_filter, flow_type, flow_type_array, as_input, classification_filter,
          escaped_query_terms;
end;
$_$;

ALTER FUNCTION "private"."search_flows_latest_impl"("query_text" "text", "filter_condition" "jsonb", "page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "query_terms" "text"[]) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."search_flows_latest_impl"("query_text" "text", "filter_condition" "jsonb", "page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "query_terms" "text"[]) FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."search_flows_latest_impl"("query_text" "text", "filter_condition" "jsonb", "page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "query_terms" "text"[]) TO "service_role";

GRANT ALL ON FUNCTION "private"."search_flows_latest_impl"("query_text" "text", "filter_condition" "jsonb", "page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "query_terms" "text"[]) TO "api_internal_executor";

CREATE OR REPLACE FUNCTION "private"."search_lifecyclemodels_latest_impl"("query_text" "text", "filter_condition" "jsonb" DEFAULT '{}'::"jsonb", "page_size" bigint DEFAULT 10, "page_current" bigint DEFAULT 1, "data_source" "text" DEFAULT 'tg'::"text", "this_user_id" "text" DEFAULT ''::"text", "team_id_filter" "uuid" DEFAULT NULL::"uuid", "state_code_filter" integer DEFAULT NULL::integer, "query_terms" "text"[] DEFAULT NULL::"text"[]) RETURNS TABLE("rank" bigint, "id" "uuid", "json" "jsonb", "version" character, "modified_at" timestamp with time zone, "team_id" "uuid", "total_count" bigint)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'private', 'api', 'public', 'util', 'extensions', 'extensions', 'pg_temp'
    SET "statement_timeout" TO '60s'
    AS $_$
declare
  normalized_page_size bigint;
  normalized_page_current bigint;
  normalized_data_source text;
  effective_user_id uuid;
  can_read_team_filter boolean;
  exact_query_id uuid;
  filter_condition_jsonb jsonb;
  json_filter_clause text;
  v_sql text;
  escaped_query_terms text[];
  text_match_clause text;
begin
  normalized_page_size := greatest(coalesce(page_size, 10), 1);
  normalized_page_current := greatest(coalesce(page_current, 1), 1);
  normalized_data_source := coalesce(nullif(lower(btrim(data_source)), ''), 'tg');
  effective_user_id := private.dataset_search_effective_user_id(this_user_id);
  can_read_team_filter := private.dataset_search_can_read_team_filter(team_id_filter, effective_user_id);
  exact_query_id := case
    when coalesce(btrim(query_text) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', false)
      then btrim(query_text)::uuid
    else null::uuid
  end;
  filter_condition_jsonb := coalesce(filter_condition, '{}'::jsonb);
  escaped_query_terms := private.pgroonga_escape_query_terms(query_terms);
  if cardinality(escaped_query_terms) = 0 then
    escaped_query_terms := private.pgroonga_escape_query_terms(array[query_text]);
  end if;
  text_match_clause := 'where l.search_text &@~| $10';

  if exact_query_id is not null then
    return query
      with matched_ids as (
        select l.id, 1.0::double precision as search_score
        from public.lifecyclemodels l
        where l.id = exact_query_id
          and l.json @> private.sample_library_business_filter_v1(filter_condition_jsonb)
          and (
            ((((normalized_data_source = 'tg' AND l.state_code = 100) OR api.sample_library_row_matches_v1(normalized_data_source, l.state_code, l.user_id, l.id, l.version, '{}'::jsonb, false)) OR (normalized_data_source = 'ex' AND l.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL)) and (team_id_filter is null or l.team_id = team_id_filter))
            or (normalized_data_source = 'co' and l.state_code = 200 and (team_id_filter is null or l.team_id = team_id_filter))
            or (normalized_data_source = 'my' and effective_user_id is not null and l.user_id = effective_user_id and (state_code_filter is null or l.state_code = state_code_filter))
            or (normalized_data_source = 'te' and team_id_filter is not null and can_read_team_filter and l.team_id = team_id_filter and (state_code_filter is null or l.state_code = state_code_filter))
          )
        group by l.id
      ),
      latest_rows as (
        select matched_ids.id, latest_row.json, latest_row.version, latest_row.modified_at, latest_row.team_id, matched_ids.search_score
        from matched_ids
        join lateral (
          select l2.json, l2.version, l2.modified_at, l2.team_id
          from public.lifecyclemodels l2
          where l2.id = matched_ids.id
            and (
              ((((normalized_data_source = 'tg' AND l2.state_code = 100) OR api.sample_library_row_matches_v1(normalized_data_source, l2.state_code, l2.user_id, l2.id, l2.version, filter_condition_jsonb, false)) OR (normalized_data_source = 'ex' AND l2.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL)) and (team_id_filter is null or l2.team_id = team_id_filter))
              or (normalized_data_source = 'co' and l2.state_code = 200 and (team_id_filter is null or l2.team_id = team_id_filter))
              or (normalized_data_source = 'my' and effective_user_id is not null and l2.user_id = effective_user_id and (state_code_filter is null or l2.state_code = state_code_filter))
              or (normalized_data_source = 'te' and team_id_filter is not null and can_read_team_filter and l2.team_id = team_id_filter and (state_code_filter is null or l2.state_code = state_code_filter))
            )
          order by l2.version desc, l2.modified_at desc
          limit 1
        ) latest_row on true
      ),
      counted_rows as (
        select latest_rows.*, count(*) over()::bigint as total_count
        from latest_rows
      )
      select 1::bigint as rank, counted_rows.id, counted_rows.json, counted_rows.version, counted_rows.modified_at, counted_rows.team_id, counted_rows.total_count
      from counted_rows
      order by rank, counted_rows.id
      limit normalized_page_size
      offset (normalized_page_current - 1) * normalized_page_size;
    return;
  end if;

  json_filter_clause := case
    when private.sample_library_business_filter_v1(filter_condition_jsonb) = '{}'::jsonb then ''
    else 'and l.json @> private.sample_library_business_filter_v1($2)'
  end;

  v_sql := format($sql$
    with text_matches as materialized (
      select l.id,
             l.version,
             l.json,
             l.state_code,
             l.team_id,
             l.user_id,
             pgroonga_score(l.tableoid, l.ctid) as search_score
      from public.lifecyclemodels l
      %s
    ),
    matched_ids as (
      select l.id, max(l.search_score) as search_score
      from text_matches l
      where (
          (((($5 = 'tg' AND l.state_code = 100) OR api.sample_library_row_matches_v1($5, l.state_code, l.user_id, l.id, l.version, '{}'::jsonb, false)) OR ($5 = 'ex' AND l.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL)) and ($7 is null or l.team_id = $7))
          or ($5 = 'co' and l.state_code = 200 and ($7 is null or l.team_id = $7))
          or ($5 = 'my' and $6 is not null and l.user_id = $6 and ($8 is null or l.state_code = $8))
          or ($5 = 'te' and $7 is not null and $9 and l.team_id = $7 and ($8 is null or l.state_code = $8))
        )
        %s
      group by l.id
    ),
    latest_rows as (
      select matched_ids.id, latest_row.json, latest_row.version, latest_row.modified_at, latest_row.team_id, matched_ids.search_score
      from matched_ids
      join lateral (
        select l2.json, l2.version, l2.modified_at, l2.team_id
        from public.lifecyclemodels l2
        where l2.id = matched_ids.id
          and (
            (((($5 = 'tg' AND l2.state_code = 100) OR api.sample_library_row_matches_v1($5, l2.state_code, l2.user_id, l2.id, l2.version, $2, false)) OR ($5 = 'ex' AND l2.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL)) and ($7 is null or l2.team_id = $7))
            or ($5 = 'co' and l2.state_code = 200 and ($7 is null or l2.team_id = $7))
            or ($5 = 'my' and $6 is not null and l2.user_id = $6 and ($8 is null or l2.state_code = $8))
            or ($5 = 'te' and $7 is not null and $9 and l2.team_id = $7 and ($8 is null or l2.state_code = $8))
          )
        order by l2.version desc, l2.modified_at desc
        limit 1
      ) latest_row on true
    ),
    counted_rows as (
      select latest_rows.*, count(*) over()::bigint as total_count
      from latest_rows
    ),
    ranked_rows as (
      select rank() over (order by counted_rows.search_score desc, counted_rows.modified_at desc, counted_rows.id)::bigint as rank,
             counted_rows.*
      from counted_rows
    )
    select ranked_rows.rank, ranked_rows.id, ranked_rows.json, ranked_rows.version, ranked_rows.modified_at, ranked_rows.team_id, ranked_rows.total_count
    from ranked_rows
    order by ranked_rows.rank, ranked_rows.id
    limit $3
    offset ($4 - 1) * $3
  $sql$, text_match_clause, json_filter_clause);

  return query execute v_sql
    using query_text, filter_condition_jsonb, normalized_page_size, normalized_page_current,
          normalized_data_source, effective_user_id, team_id_filter, state_code_filter,
          can_read_team_filter, escaped_query_terms;
end;
$_$;

ALTER FUNCTION "private"."search_lifecyclemodels_latest_impl"("query_text" "text", "filter_condition" "jsonb", "page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "query_terms" "text"[]) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."search_lifecyclemodels_latest_impl"("query_text" "text", "filter_condition" "jsonb", "page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "query_terms" "text"[]) FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."search_lifecyclemodels_latest_impl"("query_text" "text", "filter_condition" "jsonb", "page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "query_terms" "text"[]) TO "service_role";

GRANT ALL ON FUNCTION "private"."search_lifecyclemodels_latest_impl"("query_text" "text", "filter_condition" "jsonb", "page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "query_terms" "text"[]) TO "api_internal_executor";

CREATE OR REPLACE FUNCTION "private"."search_processes_latest_v2_impl"("query_text" "text", "filter_condition" "jsonb" DEFAULT '{}'::"jsonb", "page_size" bigint DEFAULT 10, "page_current" bigint DEFAULT 1, "data_source" "text" DEFAULT 'tg'::"text", "this_user_id" "text" DEFAULT ''::"text", "team_id_filter" "uuid" DEFAULT NULL::"uuid", "state_code_filter" integer DEFAULT NULL::integer, "type_of_data_set_filter" "text" DEFAULT 'all'::"text", "query_terms" "text"[] DEFAULT NULL::"text"[], "owner_draft_only" boolean DEFAULT false) RETURNS TABLE("rank" bigint, "id" "uuid", "json" "jsonb", "version" character, "modified_at" timestamp with time zone, "team_id" "uuid", "model_id" "uuid", "total_count" bigint)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'private', 'api', 'public', 'util', 'extensions', 'extensions', 'pg_temp'
    SET "statement_timeout" TO '60s'
    AS $_$
declare
  normalized_page_size bigint;
  normalized_page_current bigint;
  normalized_data_source text;
  effective_user_id uuid;
  can_read_team_filter boolean;
  exact_query_id uuid;
  filter_condition_jsonb jsonb;
  json_filter_clause text;
  v_sql text;
  escaped_query_terms text[];
  text_match_clause text;
begin
  normalized_page_size := greatest(coalesce(page_size, 10), 1);
  normalized_page_current := greatest(coalesce(page_current, 1), 1);
  normalized_data_source := coalesce(nullif(lower(btrim(data_source)), ''), 'tg');
  if owner_draft_only and normalized_data_source <> 'my' then
    return;
  end if;
  effective_user_id := private.dataset_search_effective_user_id(this_user_id);
  can_read_team_filter := private.dataset_search_can_read_team_filter(team_id_filter, effective_user_id);
  exact_query_id := case
    when coalesce(btrim(query_text) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', false)
      then btrim(query_text)::uuid
    else null::uuid
  end;
  filter_condition_jsonb := coalesce(filter_condition, '{}'::jsonb);
  escaped_query_terms := private.pgroonga_escape_query_terms(query_terms);
  if cardinality(escaped_query_terms) = 0 then
    escaped_query_terms := private.pgroonga_escape_query_terms(array[query_text]);
  end if;
  text_match_clause := 'where p.search_text &@~| $11';

  if exact_query_id is not null then
    return query
      with matched_ids as (
        select p.id, 1.0::double precision as search_score
        from public.processes p
        where p.id = exact_query_id
          and p.json @> private.sample_library_business_filter_v1(filter_condition_jsonb)
          and (
            ((((normalized_data_source = 'tg' AND p.state_code = 100) OR api.sample_library_row_matches_v1(normalized_data_source, p.state_code, p.user_id, p.id, p.version, '{}'::jsonb, true)) OR (normalized_data_source = 'ex' AND p.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL)) and (team_id_filter is null or p.team_id = team_id_filter))
            or (normalized_data_source = 'co' and p.state_code = 200 and (team_id_filter is null or p.team_id = team_id_filter))
            or (normalized_data_source = 'my' and effective_user_id is not null and p.user_id = effective_user_id and (state_code_filter is null or p.state_code = state_code_filter) and (not owner_draft_only or (p.state_code = 0)) and p.state_code is distinct from 120)
            or (normalized_data_source = 'te' and team_id_filter is not null and can_read_team_filter and p.team_id = team_id_filter and (state_code_filter is null or p.state_code = state_code_filter) and p.state_code is distinct from 120)
          )
          and (
            coalesce(type_of_data_set_filter, 'all') = 'all'
            or p.json #>> '{processDataSet,modellingAndValidation,LCIMethodAndAllocation,typeOfDataSet}' = type_of_data_set_filter
          )
        group by p.id
      ),
      latest_rows as (
        select matched_ids.id, latest_row.json, latest_row.version, latest_row.modified_at, latest_row.team_id, latest_row.model_id, matched_ids.search_score
        from matched_ids
        join lateral (
          select p2.json, p2.version, p2.modified_at, p2.team_id, p2.model_id
          from public.processes p2
          where p2.id = matched_ids.id
            and (
              ((((normalized_data_source = 'tg' AND p2.state_code = 100) OR api.sample_library_row_matches_v1(normalized_data_source, p2.state_code, p2.user_id, p2.id, p2.version, filter_condition_jsonb, true)) OR (normalized_data_source = 'ex' AND p2.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL)) and (team_id_filter is null or p2.team_id = team_id_filter))
              or (normalized_data_source = 'co' and p2.state_code = 200 and (team_id_filter is null or p2.team_id = team_id_filter))
              or (normalized_data_source = 'my' and effective_user_id is not null and p2.user_id = effective_user_id and (state_code_filter is null or p2.state_code = state_code_filter) and (not owner_draft_only or (p2.state_code = 0)) and p2.state_code is distinct from 120)
              or (normalized_data_source = 'te' and team_id_filter is not null and can_read_team_filter and p2.team_id = team_id_filter and (state_code_filter is null or p2.state_code = state_code_filter) and p2.state_code is distinct from 120)
            )
          order by p2.version desc, p2.modified_at desc
          limit 1
        ) latest_row on true
      ),
      counted_rows as (
        select latest_rows.*, count(*) over()::bigint as total_count
        from latest_rows
      )
      select 1::bigint as rank, counted_rows.id, counted_rows.json, counted_rows.version, counted_rows.modified_at, counted_rows.team_id, counted_rows.model_id, counted_rows.total_count
      from counted_rows
      order by rank, counted_rows.id
      limit normalized_page_size
      offset (normalized_page_current - 1) * normalized_page_size;
    return;
  end if;

  json_filter_clause := case
    when private.sample_library_business_filter_v1(filter_condition_jsonb) = '{}'::jsonb then ''
    else 'and p.json @> private.sample_library_business_filter_v1($2)'
  end;

  v_sql := format($sql$
    with text_matches as materialized (
      select p.id,
             p.version,
             p.json,
             p.state_code,
             p.team_id,
             p.user_id,
             p.model_id,
             p.review_id,
             pgroonga_score(p.tableoid, p.ctid) as search_score
      from public.processes p
      %s
    ),
    matched_ids as (
      select p.id, max(p.search_score) as search_score
      from text_matches p
      where (
          (((($5 = 'tg' AND p.state_code = 100) OR api.sample_library_row_matches_v1($5, p.state_code, p.user_id, p.id, p.version, '{}'::jsonb, true)) OR ($5 = 'ex' AND p.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL)) and ($7 is null or p.team_id = $7))
          or ($5 = 'co' and p.state_code = 200 and ($7 is null or p.team_id = $7))
          or ($5 = 'my' and $6 is not null and p.user_id = $6 and ($8 is null or p.state_code = $8) and (not $12 or (p.state_code = 0)) and p.state_code is distinct from 120)
          or ($5 = 'te' and $7 is not null and $9 and p.team_id = $7 and ($8 is null or p.state_code = $8) and p.state_code is distinct from 120)
        )
        %s
        and (
          coalesce($10, 'all') = 'all'
          or p.json #>> '{processDataSet,modellingAndValidation,LCIMethodAndAllocation,typeOfDataSet}' = $10
        )
      group by p.id
    ),
    latest_rows as (
      select matched_ids.id, latest_row.json, latest_row.version, latest_row.modified_at, latest_row.team_id, latest_row.model_id, matched_ids.search_score
      from matched_ids
      join lateral (
        select p2.json, p2.version, p2.modified_at, p2.team_id, p2.model_id
        from public.processes p2
        where p2.id = matched_ids.id
          and (
            (((($5 = 'tg' AND p2.state_code = 100) OR api.sample_library_row_matches_v1($5, p2.state_code, p2.user_id, p2.id, p2.version, $2, true)) OR ($5 = 'ex' AND p2.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL)) and ($7 is null or p2.team_id = $7))
            or ($5 = 'co' and p2.state_code = 200 and ($7 is null or p2.team_id = $7))
            or ($5 = 'my' and $6 is not null and p2.user_id = $6 and ($8 is null or p2.state_code = $8) and (not $12 or (p2.state_code = 0)) and p2.state_code is distinct from 120)
            or ($5 = 'te' and $7 is not null and $9 and p2.team_id = $7 and ($8 is null or p2.state_code = $8) and p2.state_code is distinct from 120)
          )
        order by p2.version desc, p2.modified_at desc
        limit 1
      ) latest_row on true
    ),
    counted_rows as (
      select latest_rows.*, count(*) over()::bigint as total_count
      from latest_rows
    ),
    ranked_rows as (
      select rank() over (order by counted_rows.search_score desc, counted_rows.modified_at desc, counted_rows.id)::bigint as rank,
             counted_rows.*
      from counted_rows
    )
    select ranked_rows.rank, ranked_rows.id, ranked_rows.json, ranked_rows.version, ranked_rows.modified_at, ranked_rows.team_id, ranked_rows.model_id, ranked_rows.total_count
    from ranked_rows
    order by ranked_rows.rank, ranked_rows.id
    limit $3
    offset ($4 - 1) * $3
  $sql$, text_match_clause, json_filter_clause);

  return query execute v_sql
    using query_text, filter_condition_jsonb, normalized_page_size, normalized_page_current,
          normalized_data_source, effective_user_id, team_id_filter, state_code_filter,
          can_read_team_filter, type_of_data_set_filter, escaped_query_terms,
          owner_draft_only;
end;
$_$;

ALTER FUNCTION "private"."search_processes_latest_v2_impl"("query_text" "text", "filter_condition" "jsonb", "page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "type_of_data_set_filter" "text", "query_terms" "text"[], "owner_draft_only" boolean) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."search_processes_latest_v2_impl"("query_text" "text", "filter_condition" "jsonb", "page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "type_of_data_set_filter" "text", "query_terms" "text"[], "owner_draft_only" boolean) FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."search_processes_latest_v2_impl"("query_text" "text", "filter_condition" "jsonb", "page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "type_of_data_set_filter" "text", "query_terms" "text"[], "owner_draft_only" boolean) TO "service_role";

GRANT ALL ON FUNCTION "private"."search_processes_latest_v2_impl"("query_text" "text", "filter_condition" "jsonb", "page_size" bigint, "page_current" bigint, "data_source" "text", "this_user_id" "text", "team_id_filter" "uuid", "state_code_filter" integer, "type_of_data_set_filter" "text", "query_terms" "text"[], "owner_draft_only" boolean) TO "api_internal_executor";

-- Sample Library semantic candidates use a separate function because the
-- existing candidate functions carry a hosted pgvector SET option that the
-- migration role cannot set when replacing their definitions.
create or replace function private.semantic_sample_library_candidates_v1(
  p_table regclass,
  query_embedding text,
  filter_condition text default '',
  match_threshold double precision default 0.5,
  match_count integer default 20
) returns table(rank bigint, id uuid, distance double precision)
language plpgsql
security definer
set search_path = 'pg_catalog', 'extensions'
set statement_timeout = '60s'
set plan_cache_mode = 'force_custom_plan'
as $fn$
declare
  query_embedding_vector extensions.vector(1024);
  filter_json jsonb;
  business_filter jsonb;
  flow_type text;
  flow_types text[];
  as_input boolean;
  normalized_match_count integer;
  candidate_size integer;
  threshold_distance double precision;
  candidate_sql text;
begin
  if p_table not in (
    'public.processes'::regclass, 'public.flows'::regclass,
    'public.lifecyclemodels'::regclass, 'public.contacts'::regclass,
    'public.flowproperties'::regclass, 'public.sources'::regclass,
    'public.unitgroups'::regclass
  ) then
    raise exception 'unsupported Sample Library semantic table: %', p_table;
  end if;

  query_embedding_vector := query_embedding::extensions.vector(1024);
  filter_json := coalesce(nullif(btrim(filter_condition), ''), '{}')::jsonb;
  business_filter := filter_json;
  if p_table = 'public.flows'::regclass then
    flow_type := nullif(btrim(filter_json->>'flowType'), '');
    flow_types := case when flow_type is null then null else string_to_array(flow_type, ',') end;
    as_input := case when filter_json ? 'asInput'
      then nullif(btrim(filter_json->>'asInput'), '')::boolean else null end;
    business_filter := filter_json - 'flowType' - 'asInput';
  end if;
  normalized_match_count := case
    when p_table in (
      'public.contacts'::regclass, 'public.flowproperties'::regclass,
      'public.sources'::regclass, 'public.unitgroups'::regclass
    ) then least(greatest(coalesce(match_count, 20), 1), 200)
    else greatest(coalesce(match_count, 20), 1)
  end;
  candidate_size := greatest(normalized_match_count * 10, 200);
  threshold_distance := 1 - coalesce(match_threshold, 0.5);

  candidate_sql := format($sql$
    with candidates as materialized (
      select d.id as candidate_id,
             d.embedding_ft <=> $1 as candidate_distance
      from %s d
      where d.embedding_ft is not null
        and api.sample_library_row_matches_v1(
          'sl', d.state_code, d.user_id, d.id, d.version, $2, $3)
        and d.json @> private.sample_library_business_filter_v1($4)
        and ($5::text[] is null or
          d.json #>> '{flowDataSet,modellingAndValidation,LCIMethod,typeOfDataSet}' = any($5))
        and ($6::boolean is null or $6 = false or not (
          d.json @> '{"flowDataSet":{"flowInformation":{"dataSetInformation":{"classificationInformation":{"common:elementaryFlowCategorization":{"common:category":[{"#text":"Emissions","@level":"0"}]}}}}}}'
        ))
      order by d.embedding_ft <=> $1
      limit $7
    ),
    deduplicated as (
      select candidate_id, min(candidate_distance) as candidate_distance
      from candidates
      where candidate_distance < $8
      group by candidate_id
    )
    select rank() over (
      order by candidate_distance, candidate_id)::bigint,
      candidate_id, candidate_distance
    from deduplicated
    order by candidate_distance, candidate_id
    limit $9
  $sql$, p_table);

  return query execute candidate_sql
    using query_embedding_vector, business_filter,
          p_table = 'public.processes'::regclass, business_filter,
          flow_types, as_input, candidate_size,
          threshold_distance, normalized_match_count;
end;
$fn$;

alter function private.semantic_sample_library_candidates_v1(
  regclass, text, text, double precision, integer) owner to postgres;
revoke all on function private.semantic_sample_library_candidates_v1(
  regclass, text, text, double precision, integer)
  from public, anon, authenticated, service_role;
grant execute on function private.semantic_sample_library_candidates_v1(
  regclass, text, text, double precision, integer)
  to api_internal_executor, service_role;

create or replace function private.semantic_dataset_candidates_dispatch_v1(
  p_table regclass,
  query_embedding text,
  filter_condition text default '',
  match_threshold double precision default 0.5,
  match_count integer default 20,
  data_source text default 'tg',
  state_code_filter integer default null,
  team_id_filter uuid default null
) returns table(rank bigint, id uuid, distance double precision)
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if lower(coalesce(data_source, 'tg')) = 'sl' then
    return query select candidate.rank, candidate.id, candidate.distance
    from private.semantic_sample_library_candidates_v1(
      p_table, query_embedding, filter_condition, match_threshold, match_count
    ) candidate;
  elsif p_table = 'public.processes'::regclass then
    return query select candidate.rank, candidate.id, candidate.distance
    from private.semantic_process_candidates(
      query_embedding, filter_condition, match_threshold, match_count, data_source
    ) candidate;
  elsif p_table = 'public.flows'::regclass then
    return query select candidate.rank, candidate.id, candidate.distance
    from private.semantic_flow_candidates(
      query_embedding, filter_condition, match_threshold, match_count, data_source
    ) candidate;
  elsif p_table = 'public.lifecyclemodels'::regclass then
    return query select candidate.rank, candidate.id, candidate.distance
    from private.semantic_lifecyclemodel_candidates(
      query_embedding, filter_condition, match_threshold, match_count, data_source
    ) candidate;
  else
    return query select candidate.rank, candidate.id, candidate.distance
    from private.semantic_simple_dataset_candidates(
      p_table, query_embedding, filter_condition, match_threshold, match_count,
      data_source, state_code_filter, team_id_filter
    ) candidate;
  end if;
end;
$fn$;

alter function private.semantic_dataset_candidates_dispatch_v1(
  regclass, text, text, double precision, integer, text, integer, uuid)
  owner to postgres;
revoke all on function private.semantic_dataset_candidates_dispatch_v1(
  regclass, text, text, double precision, integer, text, integer, uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.semantic_dataset_candidates_dispatch_v1(
  regclass, text, text, double precision, integer, text, integer, uuid)
  to api_internal_executor, service_role;


CREATE OR REPLACE FUNCTION "private"."hybrid_search_processes_v2_impl"("query_text" "text", "query_embedding" "text", "filter_condition" "text" DEFAULT ''::"text", "match_threshold" double precision DEFAULT 0.5, "match_count" integer DEFAULT 20, "lexical_weight" double precision DEFAULT 0.5, "semantic_weight" double precision DEFAULT 0.5, "rrf_k" integer DEFAULT 10, "data_source" "text" DEFAULT 'tg'::"text", "page_size" integer DEFAULT 10, "page_current" integer DEFAULT 1, "query_terms" "text"[] DEFAULT NULL::"text"[]) RETURNS TABLE("id" "uuid", "json" "jsonb", "version" character, "modified_at" timestamp with time zone, "model_id" "uuid", "team_id" "uuid", "total_count" bigint)
    LANGUAGE "plpgsql"
    SET "statement_timeout" TO '60s'
    SET "search_path" TO 'private', 'api', 'public', 'util', 'extensions', 'extensions', 'pg_temp'
    AS $$
declare
  candidate_limit integer;
  semantic_match_count integer;
  filter_condition_jsonb jsonb;
  text_weight double precision;
begin
  candidate_limit := greatest(coalesce(match_count, 20), coalesce(page_size, 10)) * 10;
  semantic_match_count := greatest(coalesce(match_count, 20), coalesce(page_size, 10));
  filter_condition_jsonb := coalesce(nullif(btrim(filter_condition), ''), '{}')::jsonb;
  text_weight := coalesce(lexical_weight, 0);

  return query
    with text_matches as (
      select ts.rank as text_rank, ts.id as text_id
      from api.search_processes_latest(
        query_text,
        filter_condition_jsonb,
        '{}'::jsonb,
        candidate_limit,
        1,
        data_source,
        '',
        null::uuid,
        null::integer,
        'all',
        query_terms
      ) ts
    ),
    semantic as (
      select ss.rank as ss_rank, ss.id as ss_id
      from private.semantic_dataset_candidates_dispatch_v1(
        'public.processes'::regclass, query_embedding, filter_condition,
        match_threshold, semantic_match_count, data_source
      ) ss
    ),
    fused_raw as (
      select
        coalesce(text_matches.text_id, semantic.ss_id) as id,
        coalesce(1.0 / (rrf_k + text_matches.text_rank), 0.0) * text_weight
          + coalesce(1.0 / (rrf_k + semantic.ss_rank), 0.0) * semantic_weight as score
      from text_matches
      full outer join semantic on text_matches.text_id = semantic.ss_id
    ),
    fused as (
      select fused_raw.id, sum(fused_raw.score) as score
      from fused_raw
      where fused_raw.id is not null
      group by fused_raw.id
    ),
    visible_rows as (
      select p.*
      from public.processes p
      join fused on fused.id = p.id
      where (
        ((((data_source = 'tg' AND p.state_code = 100) OR api.sample_library_row_matches_v1(data_source, p.state_code, p.user_id, p.id, p.version, '{}'::jsonb, true)) OR (data_source = 'ex' AND p.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL)))
        or (data_source = 'co' and p.state_code = 200)
        or (data_source = 'my' and p.user_id = auth.uid())
        or (
          data_source = 'te'
          and exists (
            select 1
            from private.roles r
            where r.user_id = auth.uid()
              and r.team_id = p.team_id
              and r.role::text in ('admin', 'member', 'owner')
          )
        )
      )
    ),
    latest_rows as (
      select distinct on (visible_rows.id)
        visible_rows.id,
        visible_rows.json,
        visible_rows.version,
        visible_rows.modified_at,
        visible_rows.model_id,
        visible_rows.team_id,
        fused.score
      from visible_rows
      join fused on fused.id = visible_rows.id
      order by visible_rows.id, visible_rows.version desc, visible_rows.modified_at desc
    ),
    counted_rows as (
      select latest_rows.*, count(*) over()::bigint as total_count
      from latest_rows
    where data_source <> 'sl' or exists (
      select 1 from public.processes sample_scope_row
      where sample_scope_row.id = latest_rows.id
        and sample_scope_row.version = latest_rows.version
        and api.sample_library_row_matches_v1(
          data_source, sample_scope_row.state_code, sample_scope_row.user_id,
          sample_scope_row.id, sample_scope_row.version, filter_condition_jsonb,
          true
        )
    )
    )
    select
      counted_rows.id,
      counted_rows.json,
      counted_rows.version,
      counted_rows.modified_at,
      counted_rows.model_id,
      counted_rows.team_id,
      counted_rows.total_count
    from counted_rows
    order by counted_rows.score desc, counted_rows.modified_at desc, counted_rows.id
    limit greatest(coalesce(page_size, 10), 1)
    offset (greatest(coalesce(page_current, 1), 1) - 1) * greatest(coalesce(page_size, 10), 1);
end;
$$;

ALTER FUNCTION "private"."hybrid_search_processes_v2_impl"("query_text" "text", "query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer, "lexical_weight" double precision, "semantic_weight" double precision, "rrf_k" integer, "data_source" "text", "page_size" integer, "page_current" integer, "query_terms" "text"[]) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."hybrid_search_processes_v2_impl"("query_text" "text", "query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer, "lexical_weight" double precision, "semantic_weight" double precision, "rrf_k" integer, "data_source" "text", "page_size" integer, "page_current" integer, "query_terms" "text"[]) FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."hybrid_search_processes_v2_impl"("query_text" "text", "query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer, "lexical_weight" double precision, "semantic_weight" double precision, "rrf_k" integer, "data_source" "text", "page_size" integer, "page_current" integer, "query_terms" "text"[]) TO "service_role";

GRANT ALL ON FUNCTION "private"."hybrid_search_processes_v2_impl"("query_text" "text", "query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer, "lexical_weight" double precision, "semantic_weight" double precision, "rrf_k" integer, "data_source" "text", "page_size" integer, "page_current" integer, "query_terms" "text"[]) TO "api_internal_executor";

CREATE OR REPLACE FUNCTION "private"."hybrid_search_flows_v2_impl"("query_text" "text", "query_embedding" "text", "filter_condition" "text" DEFAULT ''::"text", "match_threshold" double precision DEFAULT 0.5, "match_count" integer DEFAULT 20, "lexical_weight" double precision DEFAULT 0.5, "semantic_weight" double precision DEFAULT 0.5, "rrf_k" integer DEFAULT 10, "data_source" "text" DEFAULT 'tg'::"text", "page_size" integer DEFAULT 10, "page_current" integer DEFAULT 1, "query_terms" "text"[] DEFAULT NULL::"text"[]) RETURNS TABLE("id" "uuid", "json" "jsonb", "version" character, "modified_at" timestamp with time zone, "team_id" "uuid", "total_count" bigint)
    LANGUAGE "plpgsql"
    SET "statement_timeout" TO '60s'
    SET "search_path" TO 'private', 'api', 'public', 'util', 'extensions', 'extensions', 'pg_temp'
    AS $$
declare
  candidate_limit integer;
  semantic_match_count integer;
  filter_condition_jsonb jsonb;
  text_weight double precision;
begin
  candidate_limit := greatest(coalesce(match_count, 20), coalesce(page_size, 10)) * 10;
  semantic_match_count := greatest(coalesce(match_count, 20), coalesce(page_size, 10));
  filter_condition_jsonb := coalesce(nullif(btrim(filter_condition), ''), '{}')::jsonb;
  text_weight := coalesce(lexical_weight, 0);

  return query
    with text_matches as (
      select ts.rank as text_rank, ts.id as text_id
      from api.search_flows_latest(
        query_text,
        filter_condition_jsonb,
        '{}'::jsonb,
        candidate_limit,
        1,
        data_source,
        '',
        null::uuid,
        null::integer,
        query_terms
      ) ts
    ),
    semantic as (
      select ss.rank as ss_rank, ss.id as ss_id
      from private.semantic_dataset_candidates_dispatch_v1(
        'public.flows'::regclass, query_embedding, filter_condition,
        match_threshold, semantic_match_count, data_source
      ) ss
    ),
    fused_raw as (
      select
        coalesce(text_matches.text_id, semantic.ss_id) as id,
        coalesce(1.0 / (rrf_k + text_matches.text_rank), 0.0) * text_weight
          + coalesce(1.0 / (rrf_k + semantic.ss_rank), 0.0) * semantic_weight as score
      from text_matches
      full outer join semantic on text_matches.text_id = semantic.ss_id
    ),
    fused as (
      select fused_raw.id, sum(fused_raw.score) as score
      from fused_raw
      where fused_raw.id is not null
      group by fused_raw.id
    ),
    visible_rows as (
      select f.*
      from public.flows f
      join fused on fused.id = f.id
      where (
        ((((data_source = 'tg' AND f.state_code = 100) OR api.sample_library_row_matches_v1(data_source, f.state_code, f.user_id, f.id, f.version, '{}'::jsonb, false)) OR (data_source = 'ex' AND f.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL)))
        or (data_source = 'co' and f.state_code = 200)
        or (data_source = 'my' and f.user_id = auth.uid())
        or (
          data_source = 'te'
          and exists (
            select 1
            from private.roles r
            where r.user_id = auth.uid()
              and r.team_id = f.team_id
              and r.role::text in ('admin', 'member', 'owner')
          )
        )
      )
    ),
    latest_rows as (
      select distinct on (visible_rows.id)
        visible_rows.id,
        visible_rows.json,
        visible_rows.version,
        visible_rows.modified_at,
        visible_rows.team_id,
        fused.score
      from visible_rows
      join fused on fused.id = visible_rows.id
      order by visible_rows.id, visible_rows.version desc, visible_rows.modified_at desc
    ),
    counted_rows as (
      select latest_rows.*, count(*) over()::bigint as total_count
      from latest_rows
    where data_source <> 'sl' or exists (
      select 1 from public.flows sample_scope_row
      where sample_scope_row.id = latest_rows.id
        and sample_scope_row.version = latest_rows.version
        and api.sample_library_row_matches_v1(
          data_source, sample_scope_row.state_code, sample_scope_row.user_id,
          sample_scope_row.id, sample_scope_row.version, filter_condition_jsonb,
          false
        )
    )
    )
    select
      counted_rows.id,
      counted_rows.json,
      counted_rows.version,
      counted_rows.modified_at,
      counted_rows.team_id,
      counted_rows.total_count
    from counted_rows
    order by counted_rows.score desc, counted_rows.modified_at desc, counted_rows.id
    limit greatest(coalesce(page_size, 10), 1)
    offset (greatest(coalesce(page_current, 1), 1) - 1) * greatest(coalesce(page_size, 10), 1);
end;
$$;

ALTER FUNCTION "private"."hybrid_search_flows_v2_impl"("query_text" "text", "query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer, "lexical_weight" double precision, "semantic_weight" double precision, "rrf_k" integer, "data_source" "text", "page_size" integer, "page_current" integer, "query_terms" "text"[]) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."hybrid_search_flows_v2_impl"("query_text" "text", "query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer, "lexical_weight" double precision, "semantic_weight" double precision, "rrf_k" integer, "data_source" "text", "page_size" integer, "page_current" integer, "query_terms" "text"[]) FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."hybrid_search_flows_v2_impl"("query_text" "text", "query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer, "lexical_weight" double precision, "semantic_weight" double precision, "rrf_k" integer, "data_source" "text", "page_size" integer, "page_current" integer, "query_terms" "text"[]) TO "service_role";

GRANT ALL ON FUNCTION "private"."hybrid_search_flows_v2_impl"("query_text" "text", "query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer, "lexical_weight" double precision, "semantic_weight" double precision, "rrf_k" integer, "data_source" "text", "page_size" integer, "page_current" integer, "query_terms" "text"[]) TO "api_internal_executor";

CREATE OR REPLACE FUNCTION "private"."hybrid_search_lifecyclemodels_v2_impl"("query_text" "text", "query_embedding" "text", "filter_condition" "text" DEFAULT ''::"text", "match_threshold" double precision DEFAULT 0.5, "match_count" integer DEFAULT 20, "lexical_weight" double precision DEFAULT 0.5, "semantic_weight" double precision DEFAULT 0.5, "rrf_k" integer DEFAULT 10, "data_source" "text" DEFAULT 'tg'::"text", "page_size" integer DEFAULT 10, "page_current" integer DEFAULT 1, "query_terms" "text"[] DEFAULT NULL::"text"[]) RETURNS TABLE("id" "uuid", "json" "jsonb", "version" character, "modified_at" timestamp with time zone, "team_id" "uuid", "total_count" bigint)
    LANGUAGE "plpgsql"
    SET "statement_timeout" TO '60s'
    SET "search_path" TO 'private', 'api', 'public', 'util', 'extensions', 'extensions', 'pg_temp'
    AS $$
declare
  candidate_limit integer;
  semantic_match_count integer;
  filter_condition_jsonb jsonb;
  text_weight double precision;
begin
  candidate_limit := greatest(coalesce(match_count, 20), coalesce(page_size, 10)) * 10;
  semantic_match_count := greatest(coalesce(match_count, 20), coalesce(page_size, 10));
  filter_condition_jsonb := coalesce(nullif(btrim(filter_condition), ''), '{}')::jsonb;
  text_weight := coalesce(lexical_weight, 0);

  return query
    with text_matches as (
      select ts.rank as text_rank, ts.id as text_id
      from api.search_lifecyclemodels_latest(
        query_text,
        filter_condition_jsonb,
        '{}'::jsonb,
        candidate_limit,
        1,
        data_source,
        '',
        null::uuid,
        null::integer,
        query_terms
      ) ts
    ),
    semantic as (
      select ss.rank as ss_rank, ss.id as ss_id
      from private.semantic_dataset_candidates_dispatch_v1(
        'public.lifecyclemodels'::regclass, query_embedding, filter_condition,
        match_threshold, semantic_match_count, data_source
      ) ss
    ),
    fused_raw as (
      select
        coalesce(text_matches.text_id, semantic.ss_id) as id,
        coalesce(1.0 / (rrf_k + text_matches.text_rank), 0.0) * text_weight
          + coalesce(1.0 / (rrf_k + semantic.ss_rank), 0.0) * semantic_weight as score
      from text_matches
      full outer join semantic on text_matches.text_id = semantic.ss_id
    ),
    fused as (
      select fused_raw.id, sum(fused_raw.score) as score
      from fused_raw
      where fused_raw.id is not null
      group by fused_raw.id
    ),
    visible_rows as (
      select l.*
      from public.lifecyclemodels l
      join fused on fused.id = l.id
      where (
        ((((data_source = 'tg' AND l.state_code = 100) OR api.sample_library_row_matches_v1(data_source, l.state_code, l.user_id, l.id, l.version, '{}'::jsonb, false)) OR (data_source = 'ex' AND l.state_code = -1 AND (SELECT auth.uid()) IS NOT NULL)))
        or (data_source = 'co' and l.state_code = 200)
        or (data_source = 'my' and l.user_id = auth.uid())
        or (
          data_source = 'te'
          and exists (
            select 1
            from private.roles r
            where r.user_id = auth.uid()
              and r.team_id = l.team_id
              and r.role::text in ('admin', 'member', 'owner')
          )
        )
      )
    ),
    latest_rows as (
      select distinct on (visible_rows.id)
        visible_rows.id,
        visible_rows.json,
        visible_rows.version,
        visible_rows.modified_at,
        visible_rows.team_id,
        fused.score
      from visible_rows
      join fused on fused.id = visible_rows.id
      order by visible_rows.id, visible_rows.version desc, visible_rows.modified_at desc
    ),
    counted_rows as (
      select latest_rows.*, count(*) over()::bigint as total_count
      from latest_rows
    where data_source <> 'sl' or exists (
      select 1 from public.lifecyclemodels sample_scope_row
      where sample_scope_row.id = latest_rows.id
        and sample_scope_row.version = latest_rows.version
        and api.sample_library_row_matches_v1(
          data_source, sample_scope_row.state_code, sample_scope_row.user_id,
          sample_scope_row.id, sample_scope_row.version, filter_condition_jsonb,
          false
        )
    )
    )
    select
      counted_rows.id,
      counted_rows.json,
      counted_rows.version,
      counted_rows.modified_at,
      counted_rows.team_id,
      counted_rows.total_count
    from counted_rows
    order by counted_rows.score desc, counted_rows.modified_at desc, counted_rows.id
    limit greatest(coalesce(page_size, 10), 1)
    offset (greatest(coalesce(page_current, 1), 1) - 1) * greatest(coalesce(page_size, 10), 1);
end;
$$;

ALTER FUNCTION "private"."hybrid_search_lifecyclemodels_v2_impl"("query_text" "text", "query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer, "lexical_weight" double precision, "semantic_weight" double precision, "rrf_k" integer, "data_source" "text", "page_size" integer, "page_current" integer, "query_terms" "text"[]) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."hybrid_search_lifecyclemodels_v2_impl"("query_text" "text", "query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer, "lexical_weight" double precision, "semantic_weight" double precision, "rrf_k" integer, "data_source" "text", "page_size" integer, "page_current" integer, "query_terms" "text"[]) FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."hybrid_search_lifecyclemodels_v2_impl"("query_text" "text", "query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer, "lexical_weight" double precision, "semantic_weight" double precision, "rrf_k" integer, "data_source" "text", "page_size" integer, "page_current" integer, "query_terms" "text"[]) TO "service_role";

GRANT ALL ON FUNCTION "private"."hybrid_search_lifecyclemodels_v2_impl"("query_text" "text", "query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer, "lexical_weight" double precision, "semantic_weight" double precision, "rrf_k" integer, "data_source" "text", "page_size" integer, "page_current" integer, "query_terms" "text"[]) TO "api_internal_executor";

CREATE OR REPLACE FUNCTION "private"."hybrid_search_simple_dataset_v2"("p_table" "regclass", "query_text" "text", "query_embedding" "text", "filter_condition" "text" DEFAULT ''::"text", "match_threshold" double precision DEFAULT 0.5, "match_count" integer DEFAULT 20, "lexical_weight" double precision DEFAULT 0.5, "semantic_weight" double precision DEFAULT 0.5, "rrf_k" integer DEFAULT 10, "data_source" "text" DEFAULT 'tg'::"text", "page_size" integer DEFAULT 10, "page_current" integer DEFAULT 1, "query_terms" "text"[] DEFAULT NULL::"text"[], "state_code_filter" integer DEFAULT NULL::integer, "team_id_filter" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("id" "uuid", "json" "jsonb", "version" character, "modified_at" timestamp with time zone, "team_id" "uuid", "total_count" bigint)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'private', 'api', 'public', 'util', 'extensions', 'extensions', 'pg_temp'
    SET "statement_timeout" TO '60s'
    SET "plan_cache_mode" TO 'force_custom_plan'
    AS $_$
declare
  normalized_data_source text;
  normalized_match_count integer;
  semantic_match_count integer;
  normalized_page_size integer;
  normalized_page_current integer;
  candidate_limit integer;
  normalized_rrf_k integer;
  filter_condition_jsonb jsonb;
  escaped_query_terms text[];
  effective_user_id uuid;
  can_read_team_filter boolean;
  visibility_clause text;
  json_filter_clause text;
  text_match_clause text;
  text_weight double precision;
  hybrid_sql text;
begin
  if p_table not in (
    'public.contacts'::regclass,
    'public.flowproperties'::regclass,
    'public.sources'::regclass,
    'public.unitgroups'::regclass
  ) then
    raise exception 'unsupported hybrid dataset table: %', p_table;
  end if;

  normalized_data_source := coalesce(nullif(lower(btrim(data_source)), ''), 'tg');
  normalized_match_count := least(greatest(coalesce(match_count, 20), 1), 200);
  normalized_page_size := least(greatest(coalesce(page_size, 10), 1), 200);
  normalized_page_current := greatest(coalesce(page_current, 1), 1);
  semantic_match_count := greatest(normalized_match_count, normalized_page_size);
  candidate_limit := least(greatest(normalized_match_count, normalized_page_size) * 10, 5000);
  normalized_rrf_k := greatest(coalesce(rrf_k, 10), 1);
  filter_condition_jsonb := coalesce(nullif(btrim(filter_condition), ''), '{}')::jsonb;
  escaped_query_terms := private.pgroonga_escape_query_terms(query_terms);
  if cardinality(escaped_query_terms) = 0 then
    escaped_query_terms := private.pgroonga_escape_query_terms(array[query_text]);
  end if;
  effective_user_id := private.dataset_search_effective_user_id('');
  can_read_team_filter := private.dataset_search_can_read_team_filter(
    team_id_filter,
    effective_user_id
  );
  text_weight := coalesce(lexical_weight, 0);

  if normalized_data_source = 'tg' then
    visibility_clause := 'd.state_code = 100 and ($5::uuid is null or d.team_id = $5)';
  elsif normalized_data_source = 'sl' then
    visibility_clause := 'api.sample_library_row_matches_v1($3, d.state_code, d.user_id, d.id, d.version, ''{}''::jsonb, false)';
  elsif normalized_data_source = 'ex' then
    if auth.uid() is null then return; end if;
    visibility_clause := 'd.state_code = -1 and ($5::uuid is null or d.team_id = $5)';
  elsif normalized_data_source = 'co' then
    visibility_clause := 'd.state_code = 200 and ($5::uuid is null or d.team_id = $5)';
  elsif normalized_data_source = 'my' then
    if effective_user_id is null then
      return;
    end if;
    visibility_clause := 'd.user_id = $4 and ($6::integer is null or d.state_code = $6)';
  elsif normalized_data_source = 'te' then
    if team_id_filter is null or not can_read_team_filter then
      return;
    end if;
    visibility_clause := 'd.team_id = $5 and ($6::integer is null or d.state_code = $6)';
  else
    return;
  end if;

  json_filter_clause := case
    when private.sample_library_business_filter_v1(filter_condition_jsonb) = '{}'::jsonb then ''
    else 'and d.json @> private.sample_library_business_filter_v1($2)'
  end;
  text_match_clause := case
    when cardinality(escaped_query_terms) = 0 then 'false'
    else 'd.search_text &@~| $1'
  end;

  hybrid_sql := format(
    $sql$
      with text_rows as materialized (
        select
          d.id,
          pgroonga_score(d.tableoid, d.ctid) as search_score
        from %1$s d
        where %2$s
          and %3$s
          %4$s
      ),
      text_scores as (
        select text_rows.id, max(text_rows.search_score) as search_score
        from text_rows
        group by text_rows.id
      ),
      text_matches as materialized (
        select
          rank() over (
            order by text_scores.search_score desc, text_scores.id
          )::bigint as text_rank,
          text_scores.id as text_id
        from text_scores
        order by text_scores.search_score desc, text_scores.id
        limit $7
      ),
      semantic as materialized (
        select
          candidate.rank as semantic_rank,
          candidate.id as semantic_id
        from private.semantic_dataset_candidates_dispatch_v1(
          $8, $9, $10, $11, $12, $3, $6, $5
        ) candidate
      ),
      fused_raw as (
        select
          coalesce(text_matches.text_id, semantic.semantic_id) as id,
          coalesce(
            1.0 / ($13 + text_matches.text_rank),
            0.0
          ) * $14
          + coalesce(
            1.0 / ($13 + semantic.semantic_rank),
            0.0
          ) * $15 as score
        from text_matches
        full outer join semantic
          on text_matches.text_id = semantic.semantic_id
      ),
      fused as (
        select fused_raw.id, sum(fused_raw.score) as score
        from fused_raw
        where fused_raw.id is not null
        group by fused_raw.id
      ),
      visible_rows as (
        select d.*, fused.score
        from %1$s d
        join fused on fused.id = d.id
        where %3$s
      ),
      latest_rows as (
        select distinct on (visible_rows.id)
          visible_rows.id,
          visible_rows.json,
          visible_rows.version,
          visible_rows.modified_at,
          visible_rows.team_id,
          visible_rows.score
        from visible_rows
        order by visible_rows.id, visible_rows.version desc, visible_rows.modified_at desc
      ),
      counted_rows as (
        select latest_rows.*, count(*) over()::bigint as total_count
        from latest_rows
        where $3 <> 'sl' or exists (
          select 1 from %1$s sample_scope_row
          where sample_scope_row.id = latest_rows.id
            and sample_scope_row.version = latest_rows.version
            and api.sample_library_row_matches_v1(
              $3, sample_scope_row.state_code, sample_scope_row.user_id,
              sample_scope_row.id, sample_scope_row.version, $2, false
            )
        )
      )
      select
        counted_rows.id,
        counted_rows.json,
        counted_rows.version,
        counted_rows.modified_at,
        counted_rows.team_id,
        counted_rows.total_count
      from counted_rows
      order by counted_rows.score desc, counted_rows.modified_at desc, counted_rows.id
      limit $16
      offset ($17 - 1) * $16
    $sql$,
    p_table,
    text_match_clause,
    visibility_clause,
    json_filter_clause
  );

  return query execute hybrid_sql
    using escaped_query_terms, filter_condition_jsonb, normalized_data_source,
          effective_user_id, team_id_filter, state_code_filter, candidate_limit,
          p_table, query_embedding, filter_condition, match_threshold,
          semantic_match_count, normalized_rrf_k, text_weight,
          coalesce(semantic_weight, 0), normalized_page_size,
          normalized_page_current;
end;
$_$;

ALTER FUNCTION "private"."hybrid_search_simple_dataset_v2"("p_table" "regclass", "query_text" "text", "query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer, "lexical_weight" double precision, "semantic_weight" double precision, "rrf_k" integer, "data_source" "text", "page_size" integer, "page_current" integer, "query_terms" "text"[], "state_code_filter" integer, "team_id_filter" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."hybrid_search_simple_dataset_v2"("p_table" "regclass", "query_text" "text", "query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer, "lexical_weight" double precision, "semantic_weight" double precision, "rrf_k" integer, "data_source" "text", "page_size" integer, "page_current" integer, "query_terms" "text"[], "state_code_filter" integer, "team_id_filter" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."hybrid_search_simple_dataset_v2"("p_table" "regclass", "query_text" "text", "query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer, "lexical_weight" double precision, "semantic_weight" double precision, "rrf_k" integer, "data_source" "text", "page_size" integer, "page_current" integer, "query_terms" "text"[], "state_code_filter" integer, "team_id_filter" "uuid") TO "service_role";

GRANT ALL ON FUNCTION "private"."hybrid_search_simple_dataset_v2"("p_table" "regclass", "query_text" "text", "query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer, "lexical_weight" double precision, "semantic_weight" double precision, "rrf_k" integer, "data_source" "text", "page_size" integer, "page_current" integer, "query_terms" "text"[], "state_code_filter" integer, "team_id_filter" "uuid") TO "api_internal_executor";

delete from private.api_capability_grants where routine_identity in (
  'api.get_latest_contact_versions(bigint, bigint, text, text, uuid, integer, text, text)',
  'api.get_latest_flow_versions(bigint, bigint, text, text, uuid, integer, jsonb, text, text)',
  'api.get_latest_flowproperty_versions(bigint, bigint, text, text, uuid, integer, text, text)',
  'api.get_latest_lifecyclemodel_versions(bigint, bigint, text, text, uuid, integer, text, text)',
  'api.get_latest_process_versions(bigint, bigint, text, text, uuid, integer, text, text, text)',
  'api.get_latest_source_versions(bigint, bigint, text, text, uuid, integer, text, text)',
  'api.get_latest_unitgroup_versions(bigint, bigint, text, text, uuid, integer, text, text)',
  'api.search_dataset_json_uuid_mentions(uuid, text[], text, text, uuid, integer, integer)'
);

insert into private.api_capability_grants (
  routine_identity, capability_id, allow_anon, allow_authenticated, allow_service_role
) values
  ('api.get_latest_contact_versions(bigint, bigint, text, text, uuid, integer, text, text, text, text)', 'NX-CORE-02', true, true, false),
  ('api.get_latest_flow_versions(bigint, bigint, text, text, uuid, integer, jsonb, text, text, text, text)', 'NX-CORE-02', true, true, false),
  ('api.get_latest_flowproperty_versions(bigint, bigint, text, text, uuid, integer, text, text, text, text)', 'NX-CORE-02', true, true, false),
  ('api.get_latest_lifecyclemodel_versions(bigint, bigint, text, text, uuid, integer, text, text, text, text)', 'NX-CORE-02', true, true, false),
  ('api.get_latest_process_versions(bigint, bigint, text, text, uuid, integer, text, text, text, text, text)', 'NX-CORE-02', true, true, false),
  ('api.get_latest_source_versions(bigint, bigint, text, text, uuid, integer, text, text, text, text)', 'NX-CORE-02', true, true, false),
  ('api.get_latest_unitgroup_versions(bigint, bigint, text, text, uuid, integer, text, text, text, text)', 'NX-CORE-02', true, true, false),
  ('api.search_dataset_json_uuid_mentions(uuid, text[], text, text, uuid, integer, integer, text, text)', 'NX-CORE-02', true, true, false),
  ('api.sample_library_row_matches_v1(text, integer, uuid, uuid, character, jsonb, boolean)', 'NX-CORE-02', true, true, true),
  ('api.qry_sample_library_process_publications_v1(jsonb)', 'NX-CORE-02', false, true, false)
on conflict (routine_identity) do update set
  capability_id = excluded.capability_id,
  allow_anon = excluded.allow_anon,
  allow_authenticated = excluded.allow_authenticated,
  allow_service_role = excluded.allow_service_role;

notify pgrst, 'reload schema';

commit;
