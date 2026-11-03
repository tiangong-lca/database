CREATE OR REPLACE TRIGGER "study_report_analyses_immutable" BEFORE DELETE OR UPDATE ON "private"."study_report_analyses" FOR EACH ROW EXECUTE FUNCTION "private"."study_report_immutable"();
