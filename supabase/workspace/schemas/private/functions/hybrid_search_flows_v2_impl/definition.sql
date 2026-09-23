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
