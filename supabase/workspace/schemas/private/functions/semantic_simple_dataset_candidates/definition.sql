CREATE OR REPLACE FUNCTION "private"."semantic_simple_dataset_candidates"("p_table" "regclass", "query_embedding" "text", "filter_condition" "text" DEFAULT ''::"text", "match_threshold" double precision DEFAULT 0.5, "match_count" integer DEFAULT 20, "data_source" "text" DEFAULT 'tg'::"text", "state_code_filter" integer DEFAULT NULL::integer, "team_id_filter" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("rank" bigint, "id" "uuid", "distance" double precision)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'private', 'api', 'public', 'util', 'extensions', 'extensions', 'pg_temp'
    SET "statement_timeout" TO '60s'
    SET "plan_cache_mode" TO 'force_custom_plan'
    SET "hnsw.iterative_scan" TO 'strict_order'
    AS $_$
declare
  query_embedding_vector extensions.vector(1024);
  filter_condition_jsonb jsonb;
  normalized_data_source text;
  normalized_match_count integer;
  candidate_size integer;
  threshold_distance double precision;
  effective_user_id uuid;
  can_read_team_filter boolean;
  visibility_clause text;
  json_filter_clause text;
  candidate_sql text;
begin
  if p_table not in (
    'public.contacts'::regclass,
    'public.flowproperties'::regclass,
    'public.sources'::regclass,
    'public.unitgroups'::regclass
  ) then
    raise exception 'unsupported semantic dataset table: %', p_table;
  end if;

  query_embedding_vector := query_embedding::extensions.vector(1024);
  filter_condition_jsonb := coalesce(nullif(btrim(filter_condition), ''), '{}')::jsonb;
  normalized_data_source := coalesce(nullif(lower(btrim(data_source)), ''), 'tg');
  normalized_match_count := least(greatest(coalesce(match_count, 20), 1), 200);
  candidate_size := greatest(normalized_match_count * 10, 200);
  threshold_distance := 1 - least(greatest(coalesce(match_threshold, 0.5), -1), 1);
  effective_user_id := private.dataset_search_effective_user_id('');
  can_read_team_filter := private.dataset_search_can_read_team_filter(
    team_id_filter,
    effective_user_id
  );

  if normalized_data_source = 'tg' then
    visibility_clause := 'd.state_code = 100 and ($7::uuid is null or d.team_id = $7)';
  elsif normalized_data_source = 'ex' then
    if auth.uid() is null then return; end if;
    visibility_clause := 'd.state_code = -1 and ($7::uuid is null or d.team_id = $7)';
  elsif normalized_data_source = 'co' then
    visibility_clause := 'd.state_code = 200 and ($7::uuid is null or d.team_id = $7)';
  elsif normalized_data_source = 'my' then
    if effective_user_id is null then
      return;
    end if;
    visibility_clause := 'd.user_id = $5 and ($8::integer is null or d.state_code = $8)';
  elsif normalized_data_source = 'te' then
    if team_id_filter is null or not can_read_team_filter then
      return;
    end if;
    visibility_clause := 'd.team_id = $7 and ($8::integer is null or d.state_code = $8)';
  else
    return;
  end if;

  json_filter_clause := case
    when filter_condition_jsonb = '{}'::jsonb then ''
    else 'and d.json @> $2'
  end;

  candidate_sql := format(
    $sql$
      with candidates as materialized (
        select
          d.id as candidate_id,
          d.embedding_ft <=> $1 as candidate_distance
        from %1$s d
        where d.embedding_ft is not null
          and %2$s
          %3$s
        order by d.embedding_ft <=> $1
        limit $3
      ),
      deduplicated as (
        select
          candidates.candidate_id,
          min(candidates.candidate_distance) as candidate_distance
        from candidates
        where candidates.candidate_distance < $4
        group by candidates.candidate_id
      )
      select
        rank() over (
          order by deduplicated.candidate_distance, deduplicated.candidate_id
        )::bigint,
        deduplicated.candidate_id,
        deduplicated.candidate_distance
      from deduplicated
      order by deduplicated.candidate_distance, deduplicated.candidate_id
      limit $6
    $sql$,
    p_table,
    visibility_clause,
    json_filter_clause
  );

  return query execute candidate_sql
    using query_embedding_vector, filter_condition_jsonb, candidate_size,
          threshold_distance, effective_user_id, normalized_match_count,
          team_id_filter, state_code_filter;
end;
$_$;

ALTER FUNCTION "private"."semantic_simple_dataset_candidates"("p_table" "regclass", "query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer, "data_source" "text", "state_code_filter" integer, "team_id_filter" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."semantic_simple_dataset_candidates"("p_table" "regclass", "query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer, "data_source" "text", "state_code_filter" integer, "team_id_filter" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."semantic_simple_dataset_candidates"("p_table" "regclass", "query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer, "data_source" "text", "state_code_filter" integer, "team_id_filter" "uuid") TO "service_role";

GRANT ALL ON FUNCTION "private"."semantic_simple_dataset_candidates"("p_table" "regclass", "query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer, "data_source" "text", "state_code_filter" integer, "team_id_filter" "uuid") TO "api_internal_executor";
