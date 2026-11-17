CREATE OR REPLACE TRIGGER "zz_model_bundle_write_fence" BEFORE INSERT OR DELETE OR UPDATE ON "public"."lifecyclemodels" FOR EACH ROW EXECUTE FUNCTION "private"."fence_model_bundle_write_v1"();
