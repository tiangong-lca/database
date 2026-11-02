CREATE OR REPLACE TRIGGER "study_acquisition_immutable" BEFORE DELETE OR UPDATE ON "private"."study_source_acquisitions" FOR EACH ROW EXECUTE FUNCTION "private"."study_guard_immutable"();
