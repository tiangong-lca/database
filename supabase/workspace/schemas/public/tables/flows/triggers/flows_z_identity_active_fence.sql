CREATE OR REPLACE TRIGGER "flows_z_identity_active_fence" BEFORE UPDATE ON "public"."flows" FOR EACH ROW EXECUTE FUNCTION "private"."dataset_flow_identity_active_fence"();
