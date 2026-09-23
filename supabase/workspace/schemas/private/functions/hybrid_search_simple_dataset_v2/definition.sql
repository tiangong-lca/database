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
