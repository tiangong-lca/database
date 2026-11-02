CREATE OR REPLACE FUNCTION "api"."svc_result_identity_versions"("p_result_id" "uuid", "p_before_version" "text" DEFAULT NULL::"text", "p_limit" integer DEFAULT 100) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare v_rows jsonb;
begin
  if p_result_id is null or p_limit is null or p_limit not between 1 and 256
    or (p_before_version is not null and p_before_version !~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$') then
    raise exception using errcode='22023',message='Invalid final Result version lookup';
  end if;
  with occupied as (
    select result_version as version from private.final_result_identities where result_id=p_result_id
    union select version::text from public.processes where id=p_result_id
    union select dataset_version from private.result_process_publications where dataset_id=p_result_id
    union select dataset_version from private.lca_release_dataset_versions where dataset_type='process' and dataset_uuid=p_result_id
  ), page as (
    select version from occupied where version ~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$'
      and (p_before_version is null or version collate "C" < p_before_version collate "C")
    order by version collate "C" desc limit p_limit
  )
  select coalesce(jsonb_agg(jsonb_build_object('version',page.version,'registrationId',case when identity.registration_kind='registered' then identity.registration_id else null end,
    'status',case when identity.registration_kind='registered' then 'registered' else 'legacy_requires_equivalence' end,
    'hashDomain',identity.hash_domain,'contentHash',identity.content_hash)
    order by page.version collate "C" desc),'[]'::jsonb) into v_rows
  from page left join private.final_result_identities identity on identity.result_id=p_result_id and identity.result_version=page.version;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('resultId',p_result_id,'versions',v_rows,
    'nextBeforeVersion',case when jsonb_array_length(v_rows)=p_limit then v_rows->(p_limit-1)->>'version' else null end));
end;
$_$;

ALTER FUNCTION "api"."svc_result_identity_versions"("p_result_id" "uuid", "p_before_version" "text", "p_limit" integer) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."svc_result_identity_versions"("p_result_id" "uuid", "p_before_version" "text", "p_limit" integer) FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."svc_result_identity_versions"("p_result_id" "uuid", "p_before_version" "text", "p_limit" integer) TO "service_role";
