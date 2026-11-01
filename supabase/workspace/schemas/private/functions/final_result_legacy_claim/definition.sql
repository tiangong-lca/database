CREATE OR REPLACE FUNCTION "private"."final_result_legacy_claim"("p_id" "uuid", "p_version" "text") RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
declare v_kind text;
begin
  insert into private.final_result_identities(result_id,result_version,registration_kind,producer)
    values(p_id,p_version,'legacy','legacy-process-namespace') on conflict(result_id,result_version) do nothing;
  select registration_kind into strict v_kind from private.final_result_identities where result_id=p_id and result_version=p_version;
  if v_kind <> 'legacy' then
    raise exception using errcode='23505',message='Final Result identity is registered; legacy writes require explicit equivalence migration';
  end if;
end;
$$;

ALTER FUNCTION "private"."final_result_legacy_claim"("p_id" "uuid", "p_version" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."final_result_legacy_claim"("p_id" "uuid", "p_version" "text") FROM PUBLIC;
