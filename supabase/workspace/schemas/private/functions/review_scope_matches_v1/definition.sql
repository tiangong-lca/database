CREATE OR REPLACE FUNCTION "private"."review_scope_matches_v1"("p_expected_digest" "text", "p_expected_targets" "jsonb", "p_actual_digest" "text", "p_actual_targets" "jsonb") RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $_$
declare
  v_elem jsonb;
  v_proposed_text text;
  v_actual jsonb;
  v_matched_actual jsonb;
begin
  if p_expected_digest is not null and p_expected_digest <> p_actual_digest then
    return false;
  end if;

  if p_expected_targets is not null then
    if pg_catalog.jsonb_typeof(p_expected_targets) <> 'array' then
      return false;
    end if;

    for v_elem in
      select value
      from pg_catalog.jsonb_array_elements(p_expected_targets)
    loop
      if pg_catalog.jsonb_typeof(v_elem) <> 'object' then
        return false;
      end if;

      v_proposed_text := nullif(
        pg_catalog.btrim(coalesce(v_elem->>'proposed_state_code', v_elem->>'proposedStateCode', '')),
        ''
      );

      select a.value
      into v_matched_actual
      from pg_catalog.jsonb_array_elements(coalesce(p_actual_targets, '[]'::jsonb)) as a(value)
      where a.value->>'table' = lower(coalesce(v_elem->>'table', ''))
        and a.value->>'id' = coalesce(v_elem->>'id', '')
        and a.value->>'version' = coalesce(v_elem->>'version', '')
      limit 1;

      if v_matched_actual is null then
        return false;
      end if;

      if v_proposed_text is not null then
        if not (v_proposed_text ~ '^-?\d+$')
           or v_proposed_text::integer <> (v_matched_actual->>'proposed_state_code')::integer then
          return false;
        end if;
      end if;
    end loop;

    for v_actual in
      select value
      from pg_catalog.jsonb_array_elements(coalesce(p_actual_targets, '[]'::jsonb))
    loop
      if coalesce((v_actual->>'is_root')::boolean, false)
         or coalesce((v_actual->>'previous_state_code')::integer, 0) < 20 then
        if not exists (
          select 1
          from pg_catalog.jsonb_array_elements(p_expected_targets) as e(value)
          where lower(coalesce(e.value->>'table', '')) = v_actual->>'table'
            and coalesce(e.value->>'id', '') = v_actual->>'id'
            and coalesce(e.value->>'version', '') = v_actual->>'version'
            and (
              nullif(pg_catalog.btrim(coalesce(e.value->>'proposed_state_code', e.value->>'proposedStateCode', '')), '') is null
              or (
                pg_catalog.btrim(coalesce(e.value->>'proposed_state_code', e.value->>'proposedStateCode', '')) ~ '^-?\d+$'
                and pg_catalog.btrim(coalesce(e.value->>'proposed_state_code', e.value->>'proposedStateCode', ''))::integer = (v_actual->>'proposed_state_code')::integer
              )
            )
        ) then
          return false;
        end if;
      end if;
    end loop;
  end if;

  return true;
end;
$_$;

ALTER FUNCTION "private"."review_scope_matches_v1"("p_expected_digest" "text", "p_expected_targets" "jsonb", "p_actual_digest" "text", "p_actual_targets" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."review_scope_matches_v1"("p_expected_digest" "text", "p_expected_targets" "jsonb", "p_actual_digest" "text", "p_actual_targets" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."review_scope_matches_v1"("p_expected_digest" "text", "p_expected_targets" "jsonb", "p_actual_digest" "text", "p_actual_targets" "jsonb") TO "api_internal_executor";
