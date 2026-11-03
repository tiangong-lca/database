CREATE OR REPLACE FUNCTION "private"."study_report_immutable"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$begin
 if tg_op='DELETE' or tg_table_name<>'study_report_revisions' then raise exception 'FROZEN_REVISION';end if;
 if old.status='frozen' then raise exception 'FROZEN_REVISION';end if;
 if (to_jsonb(old)-'revision'-'status'-'content_hash'-'content_artifact_id'-'validation_evidence') is distinct from (to_jsonb(new)-'revision'-'status'-'content_hash'-'content_artifact_id'-'validation_evidence') then raise exception 'REFERENCE_MISMATCH';end if;return new;
end$$;

ALTER FUNCTION "private"."study_report_immutable"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_report_immutable"() FROM PUBLIC;
