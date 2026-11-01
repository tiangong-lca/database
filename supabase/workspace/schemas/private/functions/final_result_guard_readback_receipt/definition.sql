CREATE OR REPLACE FUNCTION "private"."final_result_guard_readback_receipt"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
begin
 if old.publication_format='final-result-pair.v2' and old.readback_receipt is not null
   and (new.readback_receipt is distinct from old.readback_receipt or new.readback_verified_at is distinct from old.readback_verified_at) then
   raise exception using errcode='23514',message='Final Result public readback is immutable'; end if;
 return new;
end;
$$;

ALTER FUNCTION "private"."final_result_guard_readback_receipt"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."final_result_guard_readback_receipt"() FROM PUBLIC;
