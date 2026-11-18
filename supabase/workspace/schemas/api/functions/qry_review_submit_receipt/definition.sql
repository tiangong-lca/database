CREATE OR REPLACE FUNCTION "api"."qry_review_submit_receipt"("p_operation_key" "text", "p_target_table" "text", "p_target_id" "uuid", "p_target_version" "text") RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
  with actor as materialized (
    select auth.uid() as id
    where private.oauth_client_has_capability('CLI-REVIEW-AUTHOR-01')
  ),
  matches as (
    select audit.payload ->> 'review_id' as review_id
    from private.command_audit_log as audit
    join actor on actor.id = audit.actor_user_id
    where p_operation_key ~ '^[0-9a-f]{64}$'
      and audit.command = 'cmd_review_submit'
      and audit.payload #>> '{payload,review_operation_key}' = p_operation_key
      and audit.target_table = p_target_table
      and audit.target_id = p_target_id
      and audit.target_version = p_target_version
    limit 2
  ),
  unique_match as (
    select (array_agg(review_id))[1] as review_id
    from matches
    having count(*) = 1
  )
  select review.id
  from unique_match
  join private.reviews as review on review.id = case
    when unique_match.review_id ~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
      then unique_match.review_id::uuid
  end
  cross join actor
  where review.target_table = p_target_table
    and review.data_id = p_target_id
    and btrim(review.data_version::text) = p_target_version
    and review.json -> 'user' ->> 'id' = actor.id::text
    and (review.target_owner_id is null or review.target_owner_id = actor.id)
    and api.policy_review_can_read(review.id, actor.id);
$_$;

ALTER FUNCTION "api"."qry_review_submit_receipt"("p_operation_key" "text", "p_target_table" "text", "p_target_id" "uuid", "p_target_version" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."qry_review_submit_receipt"("p_operation_key" "text", "p_target_table" "text", "p_target_id" "uuid", "p_target_version" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."qry_review_submit_receipt"("p_operation_key" "text", "p_target_table" "text", "p_target_id" "uuid", "p_target_version" "text") TO "authenticated";
