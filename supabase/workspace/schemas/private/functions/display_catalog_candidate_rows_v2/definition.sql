CREATE OR REPLACE FUNCTION "private"."display_catalog_candidate_rows_v2"("p_kind" "text", "p_query" "text", "p_exact_id" "uuid", "p_like_pattern" "text") RETURNS TABLE("id" "uuid", "version" "text", "card" "jsonb", "state_code" integer, "modified_at" timestamp with time zone)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER PARALLEL RESTRICTED
    SET "search_path" TO ''
    SET "statement_timeout" TO '8s'
    SET "plan_cache_mode" TO 'force_custom_plan'
    SET "row_security" TO 'on'
    AS $_$
begin
  if p_kind not in ('process','flow') or p_kind is null then
    raise exception using errcode = '22023', message = 'invalid portal request';
  end if;
  if p_query = '' then
    return query
    select p.id, p.version, p.card, p.state_code, p.modified_at
    from private.display_catalog_search_current_v2 as p
    where p.dataset_kind = p_kind and true;
    return;
  end if;
  if p_kind = 'flow' and private.display_catalog_summary_valid_cas_v1(p_query) then
    return query
    select p.id, p.version, p.card, p.state_code, p.modified_at
    from private.display_catalog_search_current_v2 as p
    where p.dataset_kind = 'flow' and true
      and pg_catalog.jsonb_typeof(p.card -> 'casNumber') = 'string'
      and p.card ->> 'casNumber' ~ '^[0-9]{2,7}-[0-9]{2}-[0-9]$'
      and pg_catalog.length(p.card ->> 'casNumber') between 7 and 12
      and p.card ->> 'casNumber' = p_query;
    return;
  end if;
  return query
  with pattern_matches as materialized (
    select pattern.id,pattern.version
    from private.display_catalog_process_pattern_versions_v1(p_like_pattern) as pattern
    where p_kind='process'
    union all
    select pattern.id,pattern.version
    from private.display_catalog_flow_pattern_versions_v1(p_like_pattern) as pattern
    where p_kind='flow'
  ), matched as materialized (
    select pattern.id, pattern.version
    from pattern_matches as pattern
    union
    select p.id, p.version
    from private.display_catalog_search_current_v2 as p
    where p.dataset_kind = p_kind and p.id = p_exact_id and true
  ), key_count as materialized (select count(*) as n from matched)
  -- Join exact candidates to each RLS-protected relation before the UNION.
  select p.id,p.version,p.card,p.state_code,p.modified_at
    from matched k join private.display_catalog_search_rows_v2 p
      on p.dataset_kind='process' and p.id=k.id and p.version=k.version
    where p_kind='process' and (select n from key_count)<=2048
    union all
    select p.id,p.version,p.card,p.state_code,p.modified_at
    from matched k join private.display_catalog_search_rows_v1 p
      on p.dataset_kind='flow' and p.id=k.id and p.version=k.version
    where p_kind='flow' and (select n from key_count)<=2048
    union all
    select p.id,p.version,p.card,p.state_code,p.modified_at
    from matched k join private.display_catalog_search_current_v2 p
      on p.dataset_kind=p_kind and p.id=k.id and p.version=k.version
    where (select n from key_count)>2048;
end;
$_$;

ALTER FUNCTION "private"."display_catalog_candidate_rows_v2"("p_kind" "text", "p_query" "text", "p_exact_id" "uuid", "p_like_pattern" "text") OWNER TO "portal_display_executor";

REVOKE ALL ON FUNCTION "private"."display_catalog_candidate_rows_v2"("p_kind" "text", "p_query" "text", "p_exact_id" "uuid", "p_like_pattern" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."display_catalog_candidate_rows_v2"("p_kind" "text", "p_query" "text", "p_exact_id" "uuid", "p_like_pattern" "text") TO "postgres";
