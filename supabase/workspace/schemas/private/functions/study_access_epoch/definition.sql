CREATE OR REPLACE FUNCTION "private"."study_access_epoch"("p_actor" "uuid", "p_study" "uuid") RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
  select private.study_content_hash('lca.study-access-epoch.v1',coalesce(jsonb_agg(jsonb_build_object(
    'studyId',s.id,'grantEpoch',s.grant_epoch,'studyRole',m.role,'teamRole',r.role) order by s.id),'[]'::jsonb))
  from private.study_members m join private.studies s on s.id=m.study_id
  left join private.roles r on r.user_id=p_actor and r.team_id=s.team_id
  where m.actor_id=p_actor and (p_study is null or s.id=p_study)
$$;

ALTER FUNCTION "private"."study_access_epoch"("p_actor" "uuid", "p_study" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_access_epoch"("p_actor" "uuid", "p_study" "uuid") FROM PUBLIC;
