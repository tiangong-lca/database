CREATE OR REPLACE TRIGGER "study_report_immutable" BEFORE DELETE OR UPDATE ON "private"."study_report_revisions" FOR EACH ROW EXECUTE FUNCTION "private"."study_report_immutable"();
