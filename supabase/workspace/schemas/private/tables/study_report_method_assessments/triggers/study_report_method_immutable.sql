CREATE OR REPLACE TRIGGER "study_report_method_immutable" BEFORE DELETE OR UPDATE ON "private"."study_report_method_assessments" FOR EACH ROW EXECUTE FUNCTION "private"."study_report_immutable"();
