CREATE OR REPLACE TRIGGER "final_result_replacement_guard" BEFORE INSERT OR UPDATE ON "private"."lca_release_runs" FOR EACH ROW EXECUTE FUNCTION "private"."final_result_replacement_guard"();
