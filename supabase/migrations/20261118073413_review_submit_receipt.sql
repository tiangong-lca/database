begin;

create index command_audit_log_review_operation_idx
  on private.command_audit_log (actor_user_id, (payload #>> '{payload,review_operation_key}'))
  where command = 'cmd_review_submit'
    and (payload #>> '{payload,review_operation_key}') is not null;

create function api.qry_review_submit_receipt(
  p_operation_key text,
  p_target_table text,
  p_target_id uuid,
  p_target_version text
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $function$
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
$function$;

comment on function api.qry_review_submit_receipt(text, text, uuid, text) is
  'Return only the visible review ID from one exact committed submission by the current actor. Missing or ambiguous operation evidence returns NULL.';

revoke execute on function api.qry_review_submit_receipt(text, text, uuid, text) from public, anon, service_role;
grant execute on function api.qry_review_submit_receipt(text, text, uuid, text) to authenticated;

insert into private.api_capability_grants (
  routine_identity, capability_id, allow_anon, allow_authenticated, allow_service_role
) values (
  'api.qry_review_submit_receipt(text, text, uuid, text)',
  'CLI-REVIEW-AUTHOR-01', false, true, false
);

notify pgrst, 'reload schema';

commit;
