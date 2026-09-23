CREATE OR REPLACE FUNCTION "private"."semantic_lifecyclemodel_candidates"("query_embedding" "text", "filter_condition" "text" DEFAULT ''::"text", "match_threshold" double precision DEFAULT 0.5, "match_count" integer DEFAULT 20, "data_source" "text" DEFAULT 'tg'::"text") RETURNS TABLE("rank" bigint, "id" "uuid", "distance" double precision)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'private', 'api', 'public', 'util', 'extensions', 'extensions', 'pg_temp'
    SET "statement_timeout" TO '60s'
    AS $$
declare
  query_embedding_vector vector(1024);
  filter_condition_jsonb jsonb;
  normalized_data_source text;
  normalized_match_count integer;
  candidate_size integer;
  threshold_distance double precision;
  effective_user_id uuid;
begin
  query_embedding_vector := query_embedding::vector(1024);
  filter_condition_jsonb := coalesce(nullif(btrim(filter_condition), ''), '{}')::jsonb;
  normalized_data_source := coalesce(nullif(lower(btrim(data_source)), ''), 'tg');
  normalized_match_count := greatest(coalesce(match_count, 20), 1);
  candidate_size := greatest(normalized_match_count * 10, 200);
  threshold_distance := 1 - coalesce(match_threshold, 0.5);
  effective_user_id := private.dataset_search_effective_user_id('');

  if normalized_data_source = 'tg' then
    return query
      with candidates as materialized (
        select
          l.id as candidate_id,
          (l.embedding_ft <=> query_embedding_vector) as candidate_distance
        from public.lifecyclemodels l
        where l.embedding_ft is not null
          and l.state_code = 100
          and l.json @> filter_condition_jsonb
        order by l.embedding_ft <=> query_embedding_vector
        limit candidate_size
      ),
      filtered as (
        select candidates.*
        from candidates
        where candidates.candidate_distance < threshold_distance
      )
      select
        rank() over (order by filtered.candidate_distance)::bigint,
        filtered.candidate_id,
        filtered.candidate_distance
      from filtered
      order by filtered.candidate_distance
      limit normalized_match_count;
    return;
  end if;

  if normalized_data_source = 'ex' and auth.uid() is not null then
    return query
      with candidates as materialized (
        select
          l.id as candidate_id,
          (l.embedding_ft <=> query_embedding_vector) as candidate_distance
        from public.lifecyclemodels l
        where l.embedding_ft is not null
          and l.state_code = -1
          and l.json @> filter_condition_jsonb
        order by l.embedding_ft <=> query_embedding_vector
        limit candidate_size
      ),
      filtered as (
        select candidates.*
        from candidates
        where candidates.candidate_distance < threshold_distance
      )
      select
        rank() over (order by filtered.candidate_distance)::bigint,
        filtered.candidate_id,
        filtered.candidate_distance
      from filtered
      order by filtered.candidate_distance
      limit normalized_match_count;
    return;
  end if;

  if normalized_data_source = 'co' then
    return query
      with candidates as materialized (
        select
          l.id as candidate_id,
          (l.embedding_ft <=> query_embedding_vector) as candidate_distance
        from public.lifecyclemodels l
        where l.embedding_ft is not null
          and l.state_code = 200
          and l.json @> filter_condition_jsonb
        order by l.embedding_ft <=> query_embedding_vector
        limit candidate_size
      ),
      filtered as (
        select candidates.*
        from candidates
        where candidates.candidate_distance < threshold_distance
      )
      select
        rank() over (order by filtered.candidate_distance)::bigint,
        filtered.candidate_id,
        filtered.candidate_distance
      from filtered
      order by filtered.candidate_distance
      limit normalized_match_count;
    return;
  end if;

  if normalized_data_source = 'my' then
    if effective_user_id is null then
      return;
    end if;

    return query
      with candidates as materialized (
        select
          l.id as candidate_id,
          (l.embedding_ft <=> query_embedding_vector) as candidate_distance
        from public.lifecyclemodels l
        where l.embedding_ft is not null
          and l.user_id = effective_user_id
          and l.json @> filter_condition_jsonb
        order by l.embedding_ft <=> query_embedding_vector
        limit candidate_size
      ),
      filtered as (
        select candidates.*
        from candidates
        where candidates.candidate_distance < threshold_distance
      )
      select
        rank() over (order by filtered.candidate_distance)::bigint,
        filtered.candidate_id,
        filtered.candidate_distance
      from filtered
      order by filtered.candidate_distance
      limit normalized_match_count;
    return;
  end if;

  if normalized_data_source = 'te' then
    if effective_user_id is null then
      return;
    end if;

    return query
      with candidates as materialized (
        select
          l.id as candidate_id,
          (l.embedding_ft <=> query_embedding_vector) as candidate_distance
        from public.lifecyclemodels l
        where l.embedding_ft is not null
          and exists (
            select 1
            from private.roles r
            where r.user_id = effective_user_id
              and r.team_id = l.team_id
              and r.role::text in ('admin', 'member', 'owner')
          )
          and l.json @> filter_condition_jsonb
        order by l.embedding_ft <=> query_embedding_vector
        limit candidate_size
      ),
      filtered as (
        select candidates.*
        from candidates
        where candidates.candidate_distance < threshold_distance
      )
      select
        rank() over (order by filtered.candidate_distance)::bigint,
        filtered.candidate_id,
        filtered.candidate_distance
      from filtered
      order by filtered.candidate_distance
      limit normalized_match_count;
    return;
  end if;
end;
$$;

ALTER FUNCTION "private"."semantic_lifecyclemodel_candidates"("query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer, "data_source" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."semantic_lifecyclemodel_candidates"("query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer, "data_source" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."semantic_lifecyclemodel_candidates"("query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer, "data_source" "text") TO "service_role";

GRANT ALL ON FUNCTION "private"."semantic_lifecyclemodel_candidates"("query_embedding" "text", "filter_condition" "text", "match_threshold" double precision, "match_count" integer, "data_source" "text") TO "api_internal_executor";
