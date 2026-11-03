CREATE OR REPLACE TRIGGER "study_analysis_runs_immutable" BEFORE DELETE OR UPDATE ON "private"."study_analysis_runs" FOR EACH ROW EXECUTE FUNCTION "private"."study_analysis_immutable"();
