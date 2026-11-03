CREATE OR REPLACE FUNCTION "private"."study_review_refresh"("p_response" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare kind text:=p_response->'data'->>'type';rid uuid;value jsonb;begin
 if kind='review' then
  rid:=(p_response->'data'->'value'->>'reportRevisionId')::uuid;
  return jsonb_set(p_response,'{data,state}',private.study_review_state(rid),true);
 elsif kind='finalization' then
  rid:=(p_response->'data'->'value'->>'reportRevisionId')::uuid;
  return jsonb_set(p_response,'{data,state}',private.study_review_state(rid),true);
 elsif kind='share' then
  value:=private.study_review_share_record((p_response->'data'->'value'->>'shareId')::uuid);
  return jsonb_set(p_response,'{data,value}',value);
 elsif kind='delegation' then
  value:=private.study_delegation_record((p_response->'data'->'value'->>'delegationId')::uuid);
  return jsonb_set(p_response,'{data,value}',value);
 end if;return p_response;
end$$;

ALTER FUNCTION "private"."study_review_refresh"("p_response" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_review_refresh"("p_response" "jsonb") FROM PUBLIC;
