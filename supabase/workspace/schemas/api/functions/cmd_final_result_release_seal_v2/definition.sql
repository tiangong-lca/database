CREATE OR REPLACE FUNCTION "api"."cmd_final_result_release_seal_v2"("p_release_run_id" "uuid", "p_publish_plan_hash" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_auth jsonb:=api.assert_lca_release_manager(); v_run private.lca_release_runs%rowtype;
  v_plan private.final_result_release_plans%rowtype; v_hash text; v_count bigint;
begin
  if not coalesce((v_auth->>'ok')::boolean,false) then return v_auth; end if;
  select * into v_run from private.lca_release_runs where id=p_release_run_id for update;
  if not found or v_run.publication_format<>'final-result-pair.v2' or v_run.publish_plan_hash is distinct from p_publish_plan_hash then
    return private.lca_release_error('final_result_release_not_found',404,'Exact final Result release plan is required');
  end if;
  select * into strict v_plan from private.final_result_release_plans where release_run_id=v_run.id;
  select count(*) into v_count from private.final_result_release_members where release_run_id=v_run.id;
  if v_count<>v_plan.selection_count then raise exception using errcode='22023',message='Final Result selection is incomplete'; end if;
  with selected as (
    select (row_number() over(order by result_id,result_version collate "C")-1)/500 as block,
      result_id::text||'@'||result_version as key
    from private.final_result_release_members where release_run_id=v_run.id
  ), blocks as (
    select block,encode(extensions.digest(convert_to(string_agg(key||E'\n','' order by key collate "C"),'UTF8'),'sha256'),'hex') hash
    from selected group by block
  ) select encode(extensions.digest(convert_to('tiangong.final-result-selection.v1'||E'\n'||string_agg(hash||E'\n','' order by block),'UTF8'),'sha256'),'hex') into v_hash from blocks;
  if v_hash<>v_run.selection_manifest_hash then raise exception using errcode='22023',message='Final Result selection hash mismatch'; end if;
  if not exists(select 1 from private.final_result_release_selection_seals where release_run_id=v_run.id) then
    if v_run.status<>'prepared' then raise exception using errcode='55000',message='Final Result release cannot change its selection'; end if;
    insert into private.final_result_release_selection_seals(release_run_id,selection_hash,sealed_by) values(v_run.id,v_hash,auth.uid());
    insert into private.command_audit_log(command,actor_user_id,target_table,target_id,target_version,payload)
      values('cmd_final_result_release_seal_v2',auth.uid(),'lca_release_runs',v_run.id,v_run.release_version,jsonb_build_object('publishPlanHash',v_run.publish_plan_hash,'selectionHash',v_hash,'resultCount',v_count));
  end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('releaseRunId',v_run.id,'selectionHash',v_hash,'resultCount',v_count,'sealed',true,'publicationAuthorized',false));
end;
$$;

ALTER FUNCTION "api"."cmd_final_result_release_seal_v2"("p_release_run_id" "uuid", "p_publish_plan_hash" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."cmd_final_result_release_seal_v2"("p_release_run_id" "uuid", "p_publish_plan_hash" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."cmd_final_result_release_seal_v2"("p_release_run_id" "uuid", "p_publish_plan_hash" "text") TO "authenticated";
