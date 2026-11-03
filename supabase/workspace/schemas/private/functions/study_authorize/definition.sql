CREATE OR REPLACE FUNCTION "private"."study_authorize"("p_study" "uuid", "p_actor" "uuid", "p_client" "text", "p_action" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare s private.studies%rowtype; r text;
begin
  perform private.study_require(p_actor is not null,'AUTH_REQUIRED');
  perform private.study_require(private.study_client_allowed(p_client,case when p_action='read' then 'STUDY-READ-01' else 'STUDY-WRITE-01' end),'FORBIDDEN');
  select * into s from private.studies where id=p_study for update;
  perform private.study_require(found,'FORBIDDEN');
  select role into r from private.study_members where study_id=p_study and actor_id=p_actor;
  if s.team_id is not null then
    -- SHARE also fences non-key role demotions/deletion until this transaction
    -- commits. KEY SHARE would not fence an UPDATE of the role column.
    perform 1 from private.roles where user_id=p_actor and team_id=s.team_id and role in ('owner','admin','member') for share;
    perform private.study_require(found,'FORBIDDEN');
  end if;
  perform private.study_require(
    case p_action when 'read' then r in ('owner','editor','viewer') when 'write' then r in ('owner','editor') when 'manage' then r='owner' else false end,'FORBIDDEN');
end $$;

ALTER FUNCTION "private"."study_authorize"("p_study" "uuid", "p_actor" "uuid", "p_client" "text", "p_action" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_authorize"("p_study" "uuid", "p_actor" "uuid", "p_client" "text", "p_action" "text") FROM PUBLIC;
