CREATE OR REPLACE FUNCTION "private"."final_result_replacement_target_guard"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  if not exists(select 1 from private.lca_release_runs r join private.final_result_release_plans p on p.release_run_id=r.id
    where r.id=new.replaced_by_run_id and r.release_version=new.release_version and r.publication_format='final-result-pair.v2' and r.replaced_by_run_id is null) then
    raise exception using errcode='23514',message='Replacement must create an exact same-version Final Result draft';
  end if;
  return null;
end;
$$;

ALTER FUNCTION "private"."final_result_replacement_target_guard"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."final_result_replacement_target_guard"() FROM PUBLIC;
