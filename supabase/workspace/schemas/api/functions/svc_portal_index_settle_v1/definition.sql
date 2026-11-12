CREATE OR REPLACE FUNCTION "api"."svc_portal_index_settle_v1"("p_provider" "text", "p_event_id" "text", "p_lease_token" "uuid", "p_outcome" "text", "p_reason" "text", "p_retry_after_seconds" integer, "p_accepted" "jsonb") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "statement_timeout" TO '5s'
    AS $_$
declare
  v_event private.portal_index_outbox%rowtype;
  v_accepted jsonb;
  v_now timestamptz;
  v_requires_delay boolean;
  v_hold_provider boolean;
begin
  if not util.is_service_request() then
    raise insufficient_privilege using message = 'service role required';
  end if;
  if p_provider is null or p_provider not in ('indexnow', 'baidu', 'baidu_withdrawal')
    or p_event_id is null or p_event_id !~ '^[1-9][0-9]{0,18}$'
    or p_lease_token is null or p_outcome is null or p_reason is null
    or p_accepted is null or jsonb_typeof(p_accepted) <> 'array'
    or octet_length(p_accepted::text) > 2048 then
    raise invalid_parameter_value using message = 'invalid Portal index settlement';
  end if;
  v_hold_provider := p_provider <> 'baidu_withdrawal' and p_reason in (
    'provider_rate_limited', 'provider_quota_exhausted', 'baidu_accepted_quota_exhausted',
    'provider_rejected_urls_quota_exhausted', 'baidu_success_unattributed_quota_exhausted'
  );
  v_requires_delay := p_outcome = 'retry' or v_hold_provider;
  if jsonb_array_length(p_accepted) > 8
    or (p_reason in ('baidu_success_unattributed', 'baidu_success_unattributed_quota_exhausted')
      and p_accepted <> '[]'::jsonb)
    or not coalesce(case p_outcome
      when 'accepted' then case p_provider
        when 'indexnow' then p_reason in ('indexnow_accepted', 'indexnow_validation_pending')
        when 'baidu' then p_reason in ('baidu_accepted', 'baidu_accepted_quota_exhausted')
      end
      when 'retry' then case when p_provider = 'baidu_withdrawal'
        then p_reason = 'withdrawal_http_unconfirmed'
        else p_reason in (
        'provider_rate_limited', 'provider_temporary_failure', 'provider_timeout',
        'provider_response_unconfirmed', 'provider_quota_exhausted'
      ) end
      when 'blocked' then p_provider <> 'baidu_withdrawal' and (p_reason in (
        'provider_invalid_request', 'provider_auth_failed', 'provider_endpoint_invalid',
        'provider_rejected_urls', 'provider_disabled', 'provider_endpoint_unverified'
      ) or (p_provider = 'baidu' and p_reason in (
        'provider_rejected_urls_quota_exhausted', 'baidu_success_unattributed',
        'baidu_success_unattributed_quota_exhausted'
      )))
      when 'skipped' then p_reason = 'no_current_urls'
        or (p_provider = 'baidu' and p_reason = 'withdrawal_unsupported')
      when 'manifest_ready' then p_provider = 'baidu_withdrawal' and p_reason = 'manual_registration_pending'
      else false
    end, false)
    or (not v_requires_delay and p_retry_after_seconds is not null)
    or (v_requires_delay and (p_retry_after_seconds is null
      or p_retry_after_seconds not between 15 and 86400)) then
    raise invalid_parameter_value using message = 'invalid Portal index outcome';
  end if;

  select * into v_event from private.portal_index_outbox
  where event_id = p_event_id::bigint and provider = p_provider for update;
  if not found then return false; end if;
  if v_event.lease_token is null and v_event.last_settlement_token = p_lease_token then
    return (v_event.last_outcome, v_event.last_reason, v_event.last_retry_after_seconds)
        is not distinct from (p_outcome, p_reason, p_retry_after_seconds)
      and v_event.accepted_keys @> p_accepted;
  end if;
  v_now := clock_timestamp();
  if v_event.lease_token is distinct from p_lease_token or v_event.lease_expires_at <= v_now then
    return false;
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_accepted) as accepted(key)
    where (p_provider = 'baidu' and accepted.key->>'operation' = 'withdrawal')
      or not exists (
        select 1 from private.portal_index_receipt_keys_v1(v_event.lease_candidates) as candidate(key)
        where candidate.key = accepted.key
      )
  ) then
    raise invalid_parameter_value using message = 'Portal index receipt is outside the lease';
  end if;
  select coalesce(jsonb_agg(key order by key), '[]'::jsonb) into v_accepted
  from private.portal_index_receipt_keys_v1(v_event.lease_candidates) as candidates(key)
  where (v_event.accepted_keys || p_accepted) @> jsonb_build_array(key);

  if (p_outcome in ('accepted', 'manifest_ready') and exists (
    select 1 from private.portal_index_receipt_keys_v1(v_event.lease_candidates) as candidates(key)
    where (p_provider <> 'baidu' or key->>'operation' = 'upsert')
      and not (v_accepted @> jsonb_build_array(key))
  )) or (p_outcome = 'manifest_ready' and v_event.lease_candidates->'withdrawals' = '[]'::jsonb)
  or (p_outcome = 'accepted' and v_event.lease_candidates->'upserts' = '[]'::jsonb
    and (p_provider = 'baidu' or v_event.lease_candidates->'withdrawals' = '[]'::jsonb))
  or (p_outcome = 'skipped' and (
    v_event.lease_candidates->'upserts' <> '[]'::jsonb
    or (p_reason = 'no_current_urls' and v_event.lease_candidates->'withdrawals' <> '[]'::jsonb)
    or (p_reason = 'withdrawal_unsupported' and v_event.lease_candidates->'withdrawals' = '[]'::jsonb)
  )) then
    raise invalid_parameter_value using message = 'Portal index outcome leaves work unaccounted for';
  end if;

  update private.portal_index_outbox
  set state = case when p_outcome = 'retry' then 'pending' else p_outcome end,
      available_at = case when p_outcome = 'retry'
        then v_now + make_interval(secs => p_retry_after_seconds) else available_at end,
      lease_token = null, lease_expires_at = null, lease_candidates = null,
      accepted_keys = v_accepted, last_settlement_token = p_lease_token,
      last_outcome = p_outcome, last_reason = p_reason,
      last_retry_after_seconds = p_retry_after_seconds, settled_at = v_now
  where event_id = v_event.event_id;
  if v_hold_provider then
    update private.portal_index_config
    set indexnow_not_before = case when p_provider = 'indexnow'
          then greatest(indexnow_not_before, v_now + make_interval(secs => p_retry_after_seconds))
          else indexnow_not_before end,
        baidu_not_before = case when p_provider = 'baidu'
          then greatest(baidu_not_before, v_now + make_interval(secs => p_retry_after_seconds))
          else baidu_not_before end
    where singleton;
  end if;
  return true;
end;
$_$;

ALTER FUNCTION "api"."svc_portal_index_settle_v1"("p_provider" "text", "p_event_id" "text", "p_lease_token" "uuid", "p_outcome" "text", "p_reason" "text", "p_retry_after_seconds" integer, "p_accepted" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_portal_index_settle_v1"("p_provider" "text", "p_event_id" "text", "p_lease_token" "uuid", "p_outcome" "text", "p_reason" "text", "p_retry_after_seconds" integer, "p_accepted" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_portal_index_settle_v1"("p_provider" "text", "p_event_id" "text", "p_lease_token" "uuid", "p_outcome" "text", "p_reason" "text", "p_retry_after_seconds" integer, "p_accepted" "jsonb") TO "service_role";
