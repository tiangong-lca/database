CREATE OR REPLACE TRIGGER "study_analysis_immutable" BEFORE DELETE OR UPDATE ON "private"."study_analyses" FOR EACH ROW EXECUTE FUNCTION "private"."study_analysis_immutable"();
