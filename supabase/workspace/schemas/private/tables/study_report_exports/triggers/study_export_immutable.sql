CREATE OR REPLACE TRIGGER "study_export_immutable" BEFORE DELETE OR UPDATE ON "private"."study_report_exports" FOR EACH ROW EXECUTE FUNCTION "private"."study_report_immutable"();
