CREATE OR REPLACE FUNCTION "private"."final_result_candidate_support_readable"("p_candidate" "text") RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    SET "row_security" TO 'on'
    AS $$
begin
 return not exists(
   select m.dataset_kind,m.dataset_id,m.dataset_version from private.final_result_candidate_members m
     where m.candidate_hash=p_candidate and m.dataset_role<>'result_process'
   except
   (select 'process',m.dataset_id,m.dataset_version from private.final_result_candidate_members m join public.processes d on d.id=m.dataset_id and d.version=m.dataset_version::character(9)
       where m.candidate_hash=p_candidate and m.dataset_kind='process' and d.state_code<>120
    union all select 'flow',m.dataset_id,m.dataset_version from private.final_result_candidate_members m join public.flows d on d.id=m.dataset_id and d.version=m.dataset_version::character(9)
       where m.candidate_hash=p_candidate and m.dataset_kind='flow'
    union all select 'flowproperty',m.dataset_id,m.dataset_version from private.final_result_candidate_members m join public.flowproperties d on d.id=m.dataset_id and d.version=m.dataset_version::character(9)
       where m.candidate_hash=p_candidate and m.dataset_kind='flowproperty'
    union all select 'unitgroup',m.dataset_id,m.dataset_version from private.final_result_candidate_members m join public.unitgroups d on d.id=m.dataset_id and d.version=m.dataset_version::character(9)
       where m.candidate_hash=p_candidate and m.dataset_kind='unitgroup'
    union all select 'lciamethod',m.dataset_id,m.dataset_version from private.final_result_candidate_members m join public.lciamethods d on d.id=m.dataset_id and d.version=m.dataset_version::character(9)
       where m.candidate_hash=p_candidate and m.dataset_kind='lciamethod'
    union all select 'contact',m.dataset_id,m.dataset_version from private.final_result_candidate_members m join public.contacts d on d.id=m.dataset_id and d.version=m.dataset_version::character(9)
       where m.candidate_hash=p_candidate and m.dataset_kind='contact'
    union all select 'source',m.dataset_id,m.dataset_version from private.final_result_candidate_members m join public.sources d on d.id=m.dataset_id and d.version=m.dataset_version::character(9)
       where m.candidate_hash=p_candidate and m.dataset_kind='source'));
end;
$$;

ALTER FUNCTION "private"."final_result_candidate_support_readable"("p_candidate" "text") OWNER TO "api_internal_executor";

REVOKE ALL ON FUNCTION "private"."final_result_candidate_support_readable"("p_candidate" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."final_result_candidate_support_readable"("p_candidate" "text") TO "postgres";
