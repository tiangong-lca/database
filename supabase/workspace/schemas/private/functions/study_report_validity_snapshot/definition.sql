CREATE OR REPLACE FUNCTION "private"."study_report_validity_snapshot"("p_study" "uuid", "p_runs" "jsonb", "p_bound_at" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
 select jsonb_build_object('status',case when bool_or(r.validity='withdrawn') then 'withdrawn'
  when bool_or(r.validity='superseded') then 'superseded'
  when count(r.id)=0 or count(r.id)<>jsonb_array_length(p_runs) or bool_or(r.validity='unknown') then 'unknown' else 'current' end,
  'checkedAt',coalesce(min(r.validity_checked_at),p_bound_at),
  'reasonCodes',to_jsonb(array_remove(array[
   case when bool_or(r.validity='withdrawn') then 'run_withdrawn' end,
   case when bool_or(r.validity='superseded') then 'run_superseded' end,
   case when bool_or(r.validity='unknown') then 'run_validity_unknown' end,
   case when count(r.id)=0 or count(r.id)<>jsonb_array_length(p_runs) then 'run_missing' end],null)))
 from jsonb_array_elements_text(p_runs)e(id) left join private.study_runs r on r.study_id=p_study and r.id=e.id::uuid
$$;

ALTER FUNCTION "private"."study_report_validity_snapshot"("p_study" "uuid", "p_runs" "jsonb", "p_bound_at" timestamp with time zone) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_report_validity_snapshot"("p_study" "uuid", "p_runs" "jsonb", "p_bound_at" timestamp with time zone) FROM PUBLIC;
