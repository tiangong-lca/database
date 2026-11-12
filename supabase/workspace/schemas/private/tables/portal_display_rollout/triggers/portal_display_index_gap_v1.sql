CREATE OR REPLACE TRIGGER "portal_display_index_gap_v1" BEFORE UPDATE OF "mode" ON "private"."portal_display_rollout" FOR EACH ROW EXECUTE FUNCTION "private"."portal_display_index_gap_v1"();
