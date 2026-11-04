CREATE OR REPLACE FUNCTION "private"."study_advanced_immutable"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$begin
 if tg_op='DELETE' or (to_jsonb(old)-'facts_artifact_id') is distinct from (to_jsonb(new)-'facts_artifact_id') or old.facts_artifact_id is not null then raise exception 'FROZEN_REVISION';end if;return new;
end$$;

ALTER FUNCTION "private"."study_advanced_immutable"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_advanced_immutable"() FROM PUBLIC;
