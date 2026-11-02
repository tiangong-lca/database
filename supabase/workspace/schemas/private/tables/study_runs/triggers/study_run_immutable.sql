CREATE OR REPLACE TRIGGER "study_run_immutable" BEFORE DELETE OR UPDATE ON "private"."study_runs" FOR EACH ROW EXECUTE FUNCTION "private"."study_guard_immutable"();
