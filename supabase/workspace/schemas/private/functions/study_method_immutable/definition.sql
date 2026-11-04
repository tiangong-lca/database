CREATE OR REPLACE FUNCTION "private"."study_method_immutable"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$begin
 if tg_op='DELETE' or(to_jsonb(old)-'facts_artifact_id'-'selected_factor_record_count') is distinct from(to_jsonb(new)-'facts_artifact_id'-'selected_factor_record_count')
 or old.facts_artifact_id is not null or new.facts_artifact_id is null or new.selected_factor_record_count is null then raise exception 'FROZEN_REVISION';end if;return new;end$$;

ALTER FUNCTION "private"."study_method_immutable"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_method_immutable"() FROM PUBLIC;
