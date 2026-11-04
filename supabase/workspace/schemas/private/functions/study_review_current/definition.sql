CREATE OR REPLACE FUNCTION "private"."study_review_current"("p_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$declare r private.study_report_reviews%rowtype;s private.studies%rowtype;d private.study_review_delegations%rowtype;begin
 select * into r from private.study_report_reviews where id=p_id;if not found then return false;end if;
 select * into s from private.studies where id=r.study_id;
 if not exists(select 1 from private.study_report_review_heads where report_id=r.report_id and actor_id=r.actor_id and review_class=r.review_class and review_id=r.id)
  or not exists(select 1 from private.study_members where study_id=r.study_id and actor_id=r.actor_id and role='reviewer') or not private.study_team_member(r.actor_id,s.team_id) then return false;end if;
 if s.team_id is not null then perform 1 from private.roles where user_id=r.actor_id and team_id=s.team_id and role in ('owner','admin','member') for share;if not found then return false;end if;end if;
 if not private.study_client_allowed(r.client_id,'STUDY-WRITE-01') then return false;end if;
 if r.client_id is not null then
  select * into d from private.study_review_delegations where id=r.delegation_id;
  if not found or d.revoked_at is not null or d.consumed_review_id is distinct from r.id or d.actor_id<>r.actor_id or d.client_id<>r.client_id
   or d.report_id<>r.report_id or d.report_hash<>r.report_hash or d.review_class<>r.review_class or d.decision<>r.decision or d.predecessor_id is distinct from r.predecessor_id then return false;end if;
 end if;return true;
end$$;

ALTER FUNCTION "private"."study_review_current"("p_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_review_current"("p_id" "uuid") FROM PUBLIC;
