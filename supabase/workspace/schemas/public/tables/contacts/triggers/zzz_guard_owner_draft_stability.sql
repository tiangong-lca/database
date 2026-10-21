CREATE OR REPLACE TRIGGER "zzz_guard_owner_draft_stability" BEFORE INSERT OR UPDATE ON "public"."contacts" FOR EACH ROW EXECUTE FUNCTION "private"."guard_stable_owner_draft"();
