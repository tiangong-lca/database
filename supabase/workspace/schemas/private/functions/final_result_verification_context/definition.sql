CREATE OR REPLACE FUNCTION "private"."final_result_verification_context"("p_run" "uuid", "p_plan_hash" "text", "p_actor" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_run private.lca_release_runs%rowtype; v_plan private.final_result_release_plans%rowtype;
 v_runtime private.final_result_query_runtime_revisions%rowtype; v_current uuid; v_permission text;
begin
 select * into v_run from private.lca_release_runs where id=p_run;
 if not found or v_run.publication_format<>'final-result-pair.v2' or v_run.publish_plan_hash is distinct from p_plan_hash
   or v_run.status not in ('prepared','ready_for_approval','approved') then
   raise exception using errcode='55000',message='Final Result verification context is no longer eligible'; end if;
 select * into strict v_plan from private.final_result_release_plans where release_run_id=p_run;
 if not exists(select 1 from private.final_result_release_selection_seals where release_run_id=p_run and selection_hash=v_run.selection_manifest_hash) then
   raise exception using errcode='55000',message='Final Result verification context is no longer eligible'; end if;
 select r.* into v_runtime from private.final_result_query_runtime_head h join private.final_result_query_runtime_revisions r on r.id=h.revision_id where h.singleton;
 select id into v_current from private.lca_release_publications where publication_series_key='global' and publication_channel='public'
   and visibility_scope='public' and is_current and status='current';
 select encode(extensions.digest(convert_to('tiangong.final-result-manager-precondition.v1'||E'\n'||r.user_id::text||E'\n'||
   coalesce(extract(epoch from r.created_at)::text,'')||E'\n'||coalesce(extract(epoch from r.modified_at)::text,'')||E'\n','UTF8'),'sha256'),'hex')
   into v_permission from private.roles r where r.user_id=p_actor and r.team_id='00000000-0000-0000-0000-000000000000' and r.role='data_product_manager';
 if v_permission is null or v_runtime.id is null or not v_runtime.enabled or v_runtime.target_hash<>v_plan.target_hash
   or v_current is distinct from v_plan.expected_current_publication_id then
   raise exception using errcode='55000',message='Final Result verification context is no longer eligible'; end if;
 return jsonb_build_object('releaseRunId',p_run,'publishPlanHash',p_plan_hash,'candidateHash',v_plan.candidate_hash,'targetHash',v_plan.target_hash,
   'selectionHash',v_run.selection_manifest_hash,'selectionCount',v_plan.selection_count,'runtimeRevision',v_runtime.id,'readerSha256',v_runtime.reader_sha256,
   'actorId',p_actor,'permissionHash',v_permission,'scope',jsonb_build_object('kind','readiness','releaseRunId',p_run,'selectionHash',v_run.selection_manifest_hash),
   'publicationAuthorized',false);
end;
$$;

ALTER FUNCTION "private"."final_result_verification_context"("p_run" "uuid", "p_plan_hash" "text", "p_actor" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."final_result_verification_context"("p_run" "uuid", "p_plan_hash" "text", "p_actor" "uuid") FROM PUBLIC;
