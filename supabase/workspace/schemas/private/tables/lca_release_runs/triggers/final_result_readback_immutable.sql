CREATE OR REPLACE TRIGGER "final_result_readback_immutable" BEFORE UPDATE ON "private"."lca_release_runs" FOR EACH ROW EXECUTE FUNCTION "private"."final_result_guard_readback_receipt"();
