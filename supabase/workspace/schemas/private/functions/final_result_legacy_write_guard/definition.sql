CREATE OR REPLACE FUNCTION "private"."final_result_legacy_write_guard"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_old_id uuid; v_old_version text; v_new_id uuid; v_new_version text;
begin
  -- Project only the identity fields: process JSON may be large, and this
  -- trigger also runs for ordinary metadata/embedding updates.
  if tg_table_schema='public' and tg_table_name='processes' then
    if tg_op <> 'INSERT' then v_old_id:=old.id; v_old_version:=rtrim(old.version::text); end if;
    if tg_op <> 'DELETE' then v_new_id:=new.id; v_new_version:=rtrim(new.version::text); end if;
  elsif tg_table_schema='private' and tg_table_name='lca_release_dataset_versions' then
    if tg_op <> 'INSERT' and old.dataset_type='process' then
      v_old_id:=old.dataset_uuid; v_old_version:=old.dataset_version;
    end if;
    if tg_op <> 'DELETE' and new.dataset_type='process' then
      v_new_id:=new.dataset_uuid; v_new_version:=new.dataset_version;
    end if;
  elsif tg_table_schema='private' and tg_table_name='result_process_publications' then
    if tg_op <> 'INSERT' then v_old_id:=old.dataset_id; v_old_version:=old.dataset_version; end if;
    if tg_op <> 'DELETE' then v_new_id:=new.dataset_id; v_new_version:=new.dataset_version; end if;
  else
    raise exception using errcode='55000',message='Unexpected final Result identity guard target';
  end if;
  if v_old_id is not null then perform private.final_result_legacy_claim(v_old_id,v_old_version); end if;
  if v_new_id is not null and (v_new_id,v_new_version) is distinct from (v_old_id,v_old_version) then
    perform private.final_result_legacy_claim(v_new_id,v_new_version);
  end if;
  return null;
end;
$$;

ALTER FUNCTION "private"."final_result_legacy_write_guard"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."final_result_legacy_write_guard"() FROM PUBLIC;
