CREATE OR REPLACE FUNCTION "private"."model_bundle_lock_key"("p_model_id" "uuid", "p_version" "text") RETURNS bigint
    LANGUAGE "sql" IMMUTABLE STRICT
    SET "search_path" TO ''
    AS $$
    select pg_catalog.hashtextextended(p_model_id::text || ':' || btrim(p_version), 880)
$$;

ALTER FUNCTION "private"."model_bundle_lock_key"("p_model_id" "uuid", "p_version" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."model_bundle_lock_key"("p_model_id" "uuid", "p_version" "text") FROM PUBLIC;
