CREATE OR REPLACE TRIGGER "study_method_assessment_immutable" BEFORE DELETE OR UPDATE ON "private"."study_method_assessments" FOR EACH ROW EXECUTE FUNCTION "private"."study_method_immutable"();
