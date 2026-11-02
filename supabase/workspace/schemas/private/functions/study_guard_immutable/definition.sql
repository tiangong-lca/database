CREATE OR REPLACE FUNCTION "private"."study_guard_immutable"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
  if tg_op='DELETE' then raise exception 'FROZEN_REVISION'; end if;
  if tg_table_name in ('study_revisions','study_scenarios') then
    if old.status='frozen' then raise exception 'FROZEN_REVISION'; end if;
    if tg_table_name='study_revisions' then
      if old.parent_revision_id is distinct from new.parent_revision_id then raise exception 'REFERENCE_MISMATCH'; end if;
    else
      if old.parent_scenario_id is distinct from new.parent_scenario_id or old.study_revision_id<>new.study_revision_id then raise exception 'REFERENCE_MISMATCH'; end if;
    end if;
  elsif tg_table_name='study_model_preparations' then
    if (to_jsonb(old)-'model_ref'-'input_artifact_id'-'input_hash') is distinct from (to_jsonb(new)-'model_ref'-'input_artifact_id'-'input_hash') then raise exception 'REFERENCE_MISMATCH'; end if;
    if old.model_ref is not null and to_jsonb(old) is distinct from to_jsonb(new) then raise exception 'FROZEN_REVISION'; end if;
  elsif tg_table_name='study_source_acquisitions' then
    if (to_jsonb(old)-'snapshot_id') is distinct from (to_jsonb(new)-'snapshot_id') then raise exception 'REFERENCE_MISMATCH'; end if;
    if old.snapshot_id is not null and old.snapshot_id is distinct from new.snapshot_id then raise exception 'FROZEN_REVISION'; end if;
  elsif tg_table_name='study_runs' then
    if (to_jsonb(old)-'result_artifact_id') is distinct from (to_jsonb(new)-'result_artifact_id') then raise exception 'REFERENCE_MISMATCH'; end if;
    if old.result_artifact_id is not null and old.result_artifact_id is distinct from new.result_artifact_id then raise exception 'FROZEN_REVISION'; end if;
  else raise exception 'FROZEN_REVISION'; end if;
  return new;
end $$;

ALTER FUNCTION "private"."study_guard_immutable"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_guard_immutable"() FROM PUBLIC;
