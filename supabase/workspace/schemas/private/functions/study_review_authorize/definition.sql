CREATE OR REPLACE FUNCTION "private"."study_review_authorize"("p_study" "uuid", "p_actor" "uuid", "p_client" "text", "p_action" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare s private.studies%rowtype;r text;begin
 perform private.study_require(p_actor is not null,'AUTH_REQUIRED');
 select * into s from private.studies where id=p_study for update;perform private.study_require(found,'FORBIDDEN');
 perform private.study_require(private.study_client_allowed(p_client,case when p_action='read' then 'STUDY-READ-01' else 'STUDY-WRITE-01' end),'FORBIDDEN');
 select role into r from private.study_members where study_id=p_study and actor_id=p_actor;
 if s.team_id is not null then
  perform 1 from private.roles where user_id=p_actor and team_id=s.team_id and role in ('owner','admin','member') for share;
  perform private.study_require(found,'FORBIDDEN');
 end if;
 perform private.study_require(case p_action when 'read' then r in ('owner','editor','reviewer','viewer')
  when 'comment' then r in ('owner','editor','reviewer') when 'review' then r='reviewer' when 'manage' then r='owner' else false end,'FORBIDDEN');return r;
end$$;

ALTER FUNCTION "private"."study_review_authorize"("p_study" "uuid", "p_actor" "uuid", "p_client" "text", "p_action" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_review_authorize"("p_study" "uuid", "p_actor" "uuid", "p_client" "text", "p_action" "text") FROM PUBLIC;
