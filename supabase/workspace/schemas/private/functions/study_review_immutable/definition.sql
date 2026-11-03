CREATE OR REPLACE FUNCTION "private"."study_review_immutable"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$begin raise exception 'FROZEN_REVISION';end$$;

ALTER FUNCTION "private"."study_review_immutable"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_review_immutable"() FROM PUBLIC;
