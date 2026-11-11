CREATE OR REPLACE FUNCTION "private"."final_result_replacement_guard"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  if tg_op='INSERT' then
    if new.replaced_by_run_id is not null then raise exception using errcode='23514',message='Replacement history cannot be fabricated'; end if;
    return new;
  end if;
  if new.replaced_by_run_id is distinct from old.replaced_by_run_id then
    if old.replaced_by_run_id is not null or new.replaced_by_run_id is null
      or old.publication_format<>'final-result-pair.v2' or old.status not in ('prepared','ready_for_approval','failed')
      or new.status<>'abandoned' or exists(select 1 from private.lca_release_approvals where release_run_id=old.id)
      or exists(select 1 from private.lca_release_publications where release_run_id=old.id) then
      raise exception using errcode='23514',message='Only an unpublished unapproved draft may be replaced once';
    end if;
  end if;
  return new;
end;
$$;

ALTER FUNCTION "private"."final_result_replacement_guard"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."final_result_replacement_guard"() FROM PUBLIC;
