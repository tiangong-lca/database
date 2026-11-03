CREATE OR REPLACE FUNCTION "private"."study_analysis_immutable"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$ begin
 if tg_op='DELETE' or tg_table_name='study_analysis_runs' then raise exception 'FROZEN_REVISION'; end if;
 if (to_jsonb(old)-'facts_artifact_id'-'comparability') is distinct from (to_jsonb(new)-'facts_artifact_id'-'comparability')
 or old.facts_artifact_id is not null then raise exception 'FROZEN_REVISION'; end if;
 return new;
end $$;

ALTER FUNCTION "private"."study_analysis_immutable"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_analysis_immutable"() FROM PUBLIC;
