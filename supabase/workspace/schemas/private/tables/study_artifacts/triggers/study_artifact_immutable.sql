CREATE OR REPLACE TRIGGER "study_artifact_immutable" BEFORE DELETE OR UPDATE ON "private"."study_artifacts" FOR EACH ROW EXECUTE FUNCTION "private"."study_guard_immutable"();
