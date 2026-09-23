CREATE OR REPLACE FUNCTION "private"."semantic_sample_library_candidates_v1"("p_table" "regclass", "query_embedding" "text", "filter_condition" "text" DEFAULT ''::"text", "match_threshold" double precision DEFAULT 0.5, "match_count" integer DEFAULT 20) RETURNS TABLE("rank" bigint, "id" "uuid", "distance" double precision)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'extensions'
    SET "statement_timeout" TO '60s'
    SET "plan_cache_mode" TO 'force_custom_plan'
    AS $_$
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
$_$;

ALTER FUNCTION "private"."semantic_sample_library_candidates_v1"("p_table" "regclass", "query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."semantic_sample_library_candidates_v1"("p_table" "regclass", "query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer) FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."semantic_sample_library_candidates_v1"("p_table" "regclass", "query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer) TO "api_internal_executor";

GRANT ALL ON FUNCTION "private"."semantic_sample_library_candidates_v1"("p_table" "regclass", "query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer) TO "service_role";
