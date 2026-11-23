CREATE OR REPLACE TRIGGER "process_extract_md_trigger_insert" AFTER INSERT ON "public"."processes" FOR EACH ROW EXECUTE FUNCTION "util"."queue_dataset_extraction_jobs"();
