CREATE OR REPLACE TRIGGER "portal_index_capture_v1" AFTER INSERT OR DELETE OR UPDATE ON "private"."display_catalog_search_rows_v1" FOR EACH ROW EXECUTE FUNCTION "private"."portal_index_capture_v1"();
