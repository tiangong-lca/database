CREATE OR REPLACE FUNCTION "private"."study_team_member"("p_actor" "uuid", "p_team" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select p_team is null or exists(select 1 from private.roles r where r.user_id=p_actor
    and r.team_id=p_team and r.role in ('owner','admin','member'))
$$;

ALTER FUNCTION "private"."study_team_member"("p_actor" "uuid", "p_team" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_team_member"("p_actor" "uuid", "p_team" "uuid") FROM PUBLIC;
