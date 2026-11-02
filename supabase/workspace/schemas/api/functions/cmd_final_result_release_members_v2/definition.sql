CREATE OR REPLACE FUNCTION "api"."cmd_final_result_release_members_v2"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_rows" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare v_auth jsonb:=api.assert_lca_release_manager(); v_run private.lca_release_runs%rowtype;
  v_plan private.final_result_release_plans%rowtype; v_row jsonb; v_query private.final_result_query_rows%rowtype;
  v_old private.final_result_release_members%rowtype; v_count bigint;
begin
  if not coalesce((v_auth->>'ok')::boolean,false) then return v_auth; end if;
  if jsonb_typeof(p_rows) is distinct from 'array' or pg_column_size(p_rows)>1048576 or octet_length(p_rows::text)>1048576 then
    raise exception using errcode='22023',message='Invalid final Result release membership batch';
  end if;
  if jsonb_array_length(p_rows) not between 1 and 500 then raise exception using errcode='22023',message='Invalid final Result release membership batch'; end if;
  select * into v_run from private.lca_release_runs where id=p_release_run_id for update;
  if not found or v_run.publication_format<>'final-result-pair.v2' or v_run.publish_plan_hash is distinct from p_publish_plan_hash then
    return private.lca_release_error('final_result_release_not_found',404,'Exact final Result release plan is required');
  end if;
  select * into strict v_plan from private.final_result_release_plans where release_run_id=v_run.id;
  for v_row in select value from jsonb_array_elements(p_rows) loop
    if jsonb_typeof(v_row) is distinct from 'object' then raise exception using errcode='22023',message='Invalid final Result selection identity'; end if;
    if (select count(*) from jsonb_object_keys(v_row))<>2
      or coalesce(v_row->>'uuid','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      or coalesce(v_row->>'version','') !~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$' then
      raise exception using errcode='22023',message='Invalid final Result selection identity';
    end if;
    select q.* into v_query from private.final_result_query_rows q
      join private.final_result_candidate_artifacts a on a.artifact_id=q.artifact_id
      where a.candidate_hash=v_plan.candidate_hash and q.result_id=(v_row->>'uuid')::uuid and q.result_version=v_row->>'version';
    if not found then raise exception using errcode='22023',message='Selected Result is absent from the exact Candidate'; end if;
    select * into v_old from private.final_result_release_members where release_run_id=v_run.id and result_id=v_query.result_id and result_version=v_query.result_version;
    if found then
      if v_old.artifact_id<>v_query.artifact_id or v_old.row_ordinal<>v_query.row_ordinal then
        raise exception using errcode='23505',message='Final Result selection binding conflict';
      end if;
    else
      if v_run.status<>'prepared' or exists(select 1 from private.final_result_release_selection_seals where release_run_id=v_run.id) then
        raise exception using errcode='55000',message='Sealed final Result release selection is immutable';
      end if;
      insert into private.final_result_release_members values(v_run.id,v_query.result_id,v_query.result_version,v_query.artifact_id,v_query.row_ordinal);
    end if;
  end loop;
  select count(*) into v_count from private.final_result_release_members where release_run_id=v_run.id;
  if v_count>v_plan.selection_count then raise exception using errcode='22023',message='Final Result selection exceeds the frozen count'; end if;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('releaseRunId',v_run.id,'registeredResultCount',v_count,'publicationAuthorized',false));
end;
$_$;

ALTER FUNCTION "api"."cmd_final_result_release_members_v2"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_rows" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."cmd_final_result_release_members_v2"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_rows" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."cmd_final_result_release_members_v2"("p_release_run_id" "uuid", "p_publish_plan_hash" "text", "p_rows" "jsonb") TO "authenticated";
