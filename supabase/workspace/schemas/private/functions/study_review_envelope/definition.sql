CREATE OR REPLACE FUNCTION "private"."study_review_envelope"("p_request" "jsonb", "p_write" boolean) RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $_$begin
 perform private.study_require(auth.uid() is not null and not coalesce(util.is_service_request(),false),'AUTH_REQUIRED');
 perform private.study_require(p_request->>'schemaVersion'='lca.study-api.v4' and octet_length(p_request::text)<=262144
  and private.study_text(p_request->'requestId',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');
 if p_write then perform private.study_require(private.study_text(p_request->'idempotencyKey',128,'^[A-Za-z0-9][A-Za-z0-9._:-]*$'),'INVALID_REQUEST');end if;
end$_$;

ALTER FUNCTION "private"."study_review_envelope"("p_request" "jsonb", "p_write" boolean) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_review_envelope"("p_request" "jsonb", "p_write" boolean) FROM PUBLIC;
