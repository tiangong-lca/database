CREATE OR REPLACE FUNCTION "private"."study_source_visible_row"("p_kind" "text", "p_id" "uuid", "p_version" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare t text; v jsonb;
begin
  t:=case p_kind when 'lifecyclemodel' then 'lifecyclemodels' when 'process' then 'processes'
    when 'flow' then 'flows' when 'flowproperty' then 'flowproperties' when 'unitgroup' then 'unitgroups' end;
  if t is null then return null; end if;
  execute format('select jsonb_build_object(''text'',json_ordered::text,''stateCode'',state_code,''ownerActorId'',user_id) from public.%I where id=$1 and version=$2',t)
    into v using p_id,p_version;
  return v;
end $_$;

ALTER FUNCTION "private"."study_source_visible_row"("p_kind" "text", "p_id" "uuid", "p_version" "text") OWNER TO "api_internal_executor";

REVOKE ALL ON FUNCTION "private"."study_source_visible_row"("p_kind" "text", "p_id" "uuid", "p_version" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."study_source_visible_row"("p_kind" "text", "p_id" "uuid", "p_version" "text") TO "postgres";
