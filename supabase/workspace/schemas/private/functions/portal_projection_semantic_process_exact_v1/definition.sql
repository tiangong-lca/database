CREATE OR REPLACE FUNCTION "private"."portal_projection_semantic_process_exact_v1"("p_query_embedding" "extensions"."vector") RETURNS TABLE("id" "uuid", "version" "text", "semantic_distance" double precision)
    LANGUAGE "sql" STABLE SECURITY DEFINER PARALLEL RESTRICTED
    SET "search_path" TO ''
    SET "statement_timeout" TO '20s'
    SET "plan_cache_mode" TO 'force_custom_plan'
    SET "work_mem" TO '32MB'
    SET "enable_hashjoin" TO 'on'
    SET "enable_nestloop" TO 'off'
    SET "enable_mergejoin" TO 'off'
    SET "enable_sort" TO 'on'
    SET "max_parallel_workers_per_gather" TO '0'
    SET "jit" TO 'off'
    SET "row_security" TO 'on'
    AS $$
  select * from private.portal_projection_semantic_process_exact_cn1(p_query_embedding)
$$;

ALTER FUNCTION "private"."portal_projection_semantic_process_exact_v1"("p_query_embedding" "extensions"."vector") OWNER TO "api_internal_executor";

REVOKE ALL ON FUNCTION "private"."portal_projection_semantic_process_exact_v1"("p_query_embedding" "extensions"."vector") FROM PUBLIC;
