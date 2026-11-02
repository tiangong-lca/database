CREATE OR REPLACE TRIGGER "final_result_identity_guard" AFTER INSERT OR DELETE OR UPDATE ON "public"."processes" FOR EACH ROW EXECUTE FUNCTION "private"."final_result_legacy_write_guard"();
