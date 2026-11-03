CREATE OR REPLACE TRIGGER "study_report_runs_immutable" BEFORE DELETE OR UPDATE ON "private"."study_report_runs" FOR EACH ROW EXECUTE FUNCTION "private"."study_report_immutable"();
