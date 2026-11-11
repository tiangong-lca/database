begin;

-- An activated, complete Candidate is the distribution unit. Sealed selection
-- members are unique and drawn from the exact Candidate, so equality of the
-- registered counts proves full coverage without walking the archive closure.
create function api.qry_final_result_download(p_publication_id uuid, p_format text)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_candidate text;
  v_target text;
  v_file jsonb;
begin
  if auth.uid() is null then
    return private.lca_release_error('auth_required', 401, 'Authentication required');
  end if;
  if p_publication_id is null or p_format is null or p_format not in ('tidas', 'ilcd') then
    raise exception using errcode = '22023', message = 'Exact publication and supported archive format are required';
  end if;

  select plan.candidate_hash, plan.target_hash, file.value
    into v_candidate, v_target, v_file
  from private.lca_release_publications p
  join private.final_result_publication_bindings binding on binding.publication_id = p.id
  join private.final_result_release_plans plan on plan.release_run_id = p.release_run_id
  join private.final_result_release_selection_seals seal on seal.release_run_id = plan.release_run_id
  join private.final_result_candidates candidate on candidate.candidate_hash = plan.candidate_hash
    and candidate.result_count = plan.selection_count
  join private.final_result_candidate_storage storage on storage.candidate_hash = plan.candidate_hash
    and storage.target_hash = plan.target_hash
  cross join lateral jsonb_array_elements(storage.receipt->'files') file
  where p.id = p_publication_id and p.is_current and p.status = 'current'
    and file.value->>'name' = 'result.' || p_format || '.7z';

  if not found then
    return private.lca_release_error('result_package_not_available', 404, 'No complete prebuilt archive is available for this publication');
  end if;
  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'publicationId', p_publication_id, 'candidateHash', v_candidate,
    'targetHash', v_target, 'file', v_file));
end;
$$;

revoke all on function api.qry_final_result_download(uuid, text) from public, anon, authenticated, service_role;
grant execute on function api.qry_final_result_download(uuid, text) to authenticated;
insert into private.api_capability_grants(routine_identity, capability_id, allow_anon, allow_authenticated, allow_service_role)
values ('api.qry_final_result_download(uuid, text)', 'DB-CORE-READ-01', false, true, false);

-- Keep the deployed Edge name usable until both download formats are verified
-- against the new name. Both names share the same authority and implementation.
create or replace function api.qry_final_result_download_v2(p_publication_id uuid, p_format text)
returns jsonb
language sql stable security invoker
set search_path = ''
as $$
  select api.qry_final_result_download(p_publication_id, p_format);
$$;

create or replace function api.cmd_final_result_release_readback_v2(p_release_run_id uuid,p_publish_plan_hash text,p_observation_text text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_auth jsonb:=api.assert_lca_release_manager(); v_run private.lca_release_runs%rowtype;
 v_plan private.final_result_release_plans%rowtype; v_pub private.lca_release_publications%rowtype;
 v_runtime private.final_result_query_runtime_revisions%rowtype; v_observation jsonb; v_receipt jsonb; v_hash text;
 v_format text; v_download jsonb; v_expected jsonb; v_now timestamptz;
begin
 if not coalesce((v_auth->>'ok')::boolean,false) then return v_auth; end if;
 if p_release_run_id is null or coalesce(p_publish_plan_hash,'') !~ '^[0-9a-f]{64}$'
   or p_observation_text is null or octet_length(p_observation_text)>16384 then
   raise exception using errcode='22023',message='Exact bounded public Result observation is required'; end if;
 v_observation:=p_observation_text::jsonb;
 if jsonb_typeof(v_observation) is distinct from 'object' or
   (select array_agg(key order by key) from jsonb_object_keys(v_observation) key) is distinct from
   array['actorId','candidateHash','downloads','observationsSha256','publicationId','publishPlanHash','readerSha256','releaseRunId','resultCount','runtimeRevision','schemaVersion','selectionHash','startedAt','targetHash','verifiedAt']::text[]
   or v_observation->>'schemaVersion' is distinct from 'tiangong.final-result-public-observation.v1'
   or (v_observation->>'actorId')::uuid is distinct from auth.uid()
   or (v_observation->>'releaseRunId')::uuid is distinct from p_release_run_id
   or v_observation->>'publishPlanHash' is distinct from p_publish_plan_hash
   or coalesce(v_observation->>'observationsSha256','') !~ '^[0-9a-f]{64}$'
   or jsonb_typeof(v_observation->'resultCount') is distinct from 'number'
   or coalesce(v_observation->>'resultCount','') !~ '^[1-9][0-9]{0,6}$' then
   raise exception using errcode='22023',message='Invalid public Result observation binding'; end if;
 v_hash:=encode(extensions.digest(convert_to(p_observation_text,'UTF8'),'sha256'),'hex');
 select * into v_run from private.lca_release_runs where id=p_release_run_id for update;
 if not found or v_run.publication_format<>'final-result-pair.v2' or v_run.publish_plan_hash<>p_publish_plan_hash then
   return private.lca_release_error('final_result_release_not_found',404,'Exact final Result run is unavailable'); end if;
 -- Retry recovers immutable historical evidence, even after withdrawal; never
 -- changes visibility or rewrites the old verification timestamp.
 if v_run.readback_receipt is not null then
   if v_run.readback_receipt->>'observationSha256'<>v_hash then
     return private.lca_release_error('final_result_readback_conflict',409,'Public observation already recorded'); end if;
   return jsonb_build_object('ok',true,'data',v_run.readback_receipt);
 end if;
 select * into v_plan from private.final_result_release_plans where release_run_id=v_run.id;
 select rev.* into v_runtime from private.final_result_query_runtime_head h
   join private.final_result_query_runtime_revisions rev on rev.id=h.revision_id where h.singleton for share of h;
 -- Lock live role with the same post-wait recheck used by activation.
 perform 1 from private.roles where user_id=auth.uid() and team_id='00000000-0000-0000-0000-000000000000' and role='data_product_manager' for share;
 v_auth:=api.assert_lca_release_manager();
 if not coalesce((v_auth->>'ok')::boolean,false) then return v_auth; end if;
 select * into v_pub from private.lca_release_publications where release_run_id=v_run.id for share;
 v_now:=clock_timestamp();
 if v_run.status<>'published' or v_pub.id is null or not v_pub.is_current or v_pub.status<>'current'
   or (v_observation->>'publicationId')::uuid is distinct from v_pub.id
   or v_observation->>'candidateHash' is distinct from v_plan.candidate_hash
   or v_observation->>'targetHash' is distinct from v_plan.target_hash
   or v_observation->>'selectionHash' is distinct from v_run.selection_manifest_hash
   or (v_observation->>'resultCount')::bigint is distinct from v_plan.selection_count
   or v_runtime.id is null or not v_runtime.enabled or v_runtime.target_hash<>v_plan.target_hash
   or (v_observation->>'runtimeRevision')::uuid is distinct from v_runtime.id
   or v_observation->>'readerSha256' is distinct from v_runtime.reader_sha256 then
   return private.lca_release_error('final_result_readback_changed',409,'Publication or reader changed during public observation'); end if;
 if (v_observation->>'startedAt')::timestamptz is null or (v_observation->>'verifiedAt')::timestamptz is null
   or (v_observation->>'startedAt')::timestamptz<v_pub.published_at
   or (v_observation->>'startedAt')::timestamptz>(v_observation->>'verifiedAt')::timestamptz
   or (v_observation->>'verifiedAt')::timestamptz>v_now+interval '30 seconds'
   or (v_observation->>'verifiedAt')::timestamptz<v_now-interval '5 minutes' then
   return private.lca_release_error('final_result_readback_expired',409,'Fresh post-activation observations are required'); end if;
 if jsonb_typeof(v_observation->'downloads') is distinct from 'object' or
   (select array_agg(key order by key) from jsonb_object_keys(v_observation->'downloads') key) is distinct from array['ilcd','tidas'] then
   raise exception using errcode='22023',message='Both public ZIP outcomes are required'; end if;
 foreach v_format in array array['tidas','ilcd'] loop
   v_download:=v_observation->'downloads'->v_format;
   v_expected:=api.qry_final_result_download(v_pub.id,v_format);
   if (v_expected->>'ok')::boolean then
     if v_download is distinct from jsonb_build_object('status','verified','file',v_expected#>'{data,file}') then
       return private.lca_release_error('final_result_readback_changed',409,'Authorized ZIP bytes must be independently verified'); end if;
   elsif v_expected->>'code'='result_package_not_available' then
     if v_download is distinct from '{"status":"unavailable"}'::jsonb then
       return private.lca_release_error('final_result_readback_changed',409,'ZIP access changed during observation'); end if;
   else return v_expected;
   end if;
 end loop;
 v_receipt:=jsonb_build_object('schemaVersion','tiangong.final-result-public-readback.v1','observationSha256',v_hash,
   'observation',v_observation,'recordedAt',v_now);
 update private.lca_release_runs set status='readback_verified',readback_verified_at=v_now,readback_receipt=v_receipt where id=v_run.id;
 return jsonb_build_object('ok',true,'data',v_receipt);
end;
$$;

drop function private.final_result_candidate_support_readable(text);

notify pgrst, 'reload schema';
commit;
