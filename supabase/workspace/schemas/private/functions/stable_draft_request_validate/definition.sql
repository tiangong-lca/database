CREATE OR REPLACE FUNCTION "private"."stable_draft_request_validate"("p_request_id" "uuid", "p_request" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $_$
declare
  v_item jsonb;
  v_source jsonb;
  v_drafts jsonb;
  v_count bigint;
  v_distinct_count bigint;
  v_uuid_pattern constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_version_pattern constant text := '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$';
begin
  if p_request_id is null or jsonb_typeof(p_request) is distinct from 'object' then
    return jsonb_build_object('ok', false, 'code', 'INVALID_STABLE_DRAFT_REQUEST', 'status', 400,
      'message', 'A request UUID and complete request object are required');
  end if;
  if p_request ? 'initialJsonOrdered' or p_request->'source' = 'null'::jsonb then
    return jsonb_build_object('ok', false, 'code', 'DATASET_INITIAL_CREATION_UNSUPPORTED', 'status', 400,
      'message', 'This contract requires an exact public source; initial creation is not supported');
  end if;
  if p_request->>'table' = 'lifecyclemodels' then
    return jsonb_build_object('ok', false, 'code', 'LIFECYCLEMODEL_BUNDLE_REQUIRED', 'status', 409,
      'message', 'LifecycleModels require their native bundle contract');
  end if;
  if p_request->>'table' is null or p_request->>'table' not in ('contacts', 'sources', 'flows', 'processes') then
    return jsonb_build_object('ok', false, 'code', 'INVALID_DATASET_TABLE', 'status', 400,
      'message', 'Stable draft preparation supports contacts, sources, flows and standalone processes');
  end if;
  if (p_request - array['table','id','expectedActorId','expectedDrafts','selectedVersion','source']) <> '{}'::jsonb
     or not (p_request ?& array['table','id','expectedActorId','expectedDrafts','source'])
     or jsonb_typeof(p_request->'id') is distinct from 'string'
     or (p_request->>'id') !~ v_uuid_pattern
     or jsonb_typeof(p_request->'expectedActorId') is distinct from 'string'
     or (p_request->>'expectedActorId') !~ v_uuid_pattern
     or jsonb_typeof(p_request->'expectedDrafts') is distinct from 'array'
     or (p_request->'selectedVersion' is not null and p_request->'selectedVersion' <> 'null'::jsonb
         and (jsonb_typeof(p_request->'selectedVersion') <> 'string'
              or (p_request->>'selectedVersion') !~ v_version_pattern)) then
    return jsonb_build_object('ok', false, 'code', 'INVALID_STABLE_DRAFT_REQUEST', 'status', 400,
      'message', 'Invalid request fields, UUIDs, versions or complete draft set');
  end if;
  v_source := p_request->'source';
  if jsonb_typeof(v_source) is distinct from 'object'
     or (v_source - array['version','userId','stateCode','jsonOrdered']) <> '{}'::jsonb
     or not (v_source ?& array['version','userId','stateCode','jsonOrdered'])
     or jsonb_typeof(v_source->'version') is distinct from 'string'
     or (v_source->>'version') !~ v_version_pattern
     or jsonb_typeof(v_source->'userId') is distinct from 'string'
     or (v_source->>'userId') !~ v_uuid_pattern
     or v_source->'stateCode' not in ('100'::jsonb,'200'::jsonb)
     or jsonb_typeof(v_source->'jsonOrdered') is distinct from 'object' then
    return jsonb_build_object('ok', false, 'code', 'INVALID_STABLE_DRAFT_REQUEST', 'status', 400,
      'message', 'An exact state-100/200 source owner/version and complete JSON object are required');
  end if;
  for v_item in select value from jsonb_array_elements(p_request->'expectedDrafts') loop
    if jsonb_typeof(v_item) is distinct from 'object'
       or (v_item - array['version','jsonOrdered']) <> '{}'::jsonb
       or not (v_item ?& array['version','jsonOrdered'])
       or jsonb_typeof(v_item->'version') is distinct from 'string'
       or (v_item->>'version') !~ v_version_pattern
       or jsonb_typeof(v_item->'jsonOrdered') is distinct from 'object' then
      return jsonb_build_object('ok', false, 'code', 'INVALID_STABLE_DRAFT_REQUEST', 'status', 400,
        'message', 'Each expected draft requires one exact version and complete JSON object');
    end if;
  end loop;
  select count(*), count(distinct value->>'version'),
    coalesce(jsonb_agg(value order by value->>'version'), '[]'::jsonb)
    into v_count, v_distinct_count, v_drafts
    from jsonb_array_elements(p_request->'expectedDrafts');
  if v_count <> v_distinct_count then
    return jsonb_build_object('ok', false, 'code', 'INVALID_STABLE_DRAFT_REQUEST', 'status', 400,
      'message', 'Expected draft versions must be unique');
  end if;
  return jsonb_build_object('ok', true, 'data',
    jsonb_set(jsonb_set(p_request, '{expectedDrafts}', v_drafts),
      '{selectedVersion}', coalesce(p_request->'selectedVersion','null'::jsonb)));
end;
$_$;

ALTER FUNCTION "private"."stable_draft_request_validate"("p_request_id" "uuid", "p_request" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."stable_draft_request_validate"("p_request_id" "uuid", "p_request" "jsonb") FROM PUBLIC;
