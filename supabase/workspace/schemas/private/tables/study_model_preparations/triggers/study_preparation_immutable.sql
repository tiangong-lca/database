CREATE OR REPLACE TRIGGER "study_preparation_immutable" BEFORE DELETE OR UPDATE ON "private"."study_model_preparations" FOR EACH ROW EXECUTE FUNCTION "private"."study_guard_immutable"();
