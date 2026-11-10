CREATE OR REPLACE FUNCTION "api"."qry_final_result_release_version_v2"("p_release_version" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare v_auth jsonb:=api.assert_lca_release_manager();
begin
  if not coalesce((v_auth->>'ok')::boolean,false) then return v_auth; end if;
  if p_release_version is null or length(p_release_version)>64 or p_release_version !~ '^[0-9]{4}\.[0-9]{2}\.[0-9]+$' then
    return private.lca_release_error('final_result_prepare_invalid',400,'Invalid Final Result release version');
  end if;
  return jsonb_build_object('ok',true,'data',private.final_result_version_state(p_release_version));
end;
$_$;

ALTER FUNCTION "api"."qry_final_result_release_version_v2"("p_release_version" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."qry_final_result_release_version_v2"("p_release_version" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."qry_final_result_release_version_v2"("p_release_version" "text") TO "authenticated";
