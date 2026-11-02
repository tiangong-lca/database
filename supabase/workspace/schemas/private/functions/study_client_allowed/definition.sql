CREATE OR REPLACE FUNCTION "private"."study_client_allowed"("p_client" "text", "p_capability" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$ begin
  if p_client is null then return true; end if;
  perform 1 from private.oauth_client_registry where client_id=p_client and enabled for share;
  if not found then return false; end if;
  perform 1 from private.oauth_client_capability_grants where client_id=p_client and allowed and capability_id=p_capability for share;
  return found;
end $$;

ALTER FUNCTION "private"."study_client_allowed"("p_client" "text", "p_capability" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_client_allowed"("p_client" "text", "p_capability" "text") FROM PUBLIC;
