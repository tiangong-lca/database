CREATE OR REPLACE FUNCTION "private"."semantic_dataset_candidates_dispatch_v1"("p_table" "regclass", "query_embedding" "text", "filter_condition" "text" DEFAULT ''::"text", "match_threshold" double precision DEFAULT 0.5, "match_count" integer DEFAULT 20, "data_source" "text" DEFAULT 'tg'::"text", "state_code_filter" integer DEFAULT NULL::integer, "team_id_filter" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("rank" bigint, "id" "uuid", "distance" double precision)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
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
$$;

ALTER FUNCTION "private"."semantic_dataset_candidates_dispatch_v1"("p_table" "regclass", "query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer, "data_source" "text", "state_code_filter" integer, "team_id_filter" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."semantic_dataset_candidates_dispatch_v1"("p_table" "regclass", "query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer, "data_source" "text", "state_code_filter" integer, "team_id_filter" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."semantic_dataset_candidates_dispatch_v1"("p_table" "regclass", "query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer, "data_source" "text", "state_code_filter" integer, "team_id_filter" "uuid") TO "api_internal_executor";

GRANT ALL ON FUNCTION "private"."semantic_dataset_candidates_dispatch_v1"("p_table" "regclass", "query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer, "data_source" "text", "state_code_filter" integer, "team_id_filter" "uuid") TO "service_role";
