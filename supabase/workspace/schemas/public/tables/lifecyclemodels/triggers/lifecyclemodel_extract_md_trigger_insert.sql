CREATE OR REPLACE TRIGGER "lifecyclemodel_extract_md_trigger_insert" AFTER INSERT ON "public"."lifecyclemodels" FOR EACH ROW EXECUTE FUNCTION "util"."queue_dataset_extraction_jobs"();
