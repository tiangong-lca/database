CREATE OR REPLACE TRIGGER "study_advanced_immutable" BEFORE DELETE OR UPDATE ON "private"."study_advanced_analyses" FOR EACH ROW EXECUTE FUNCTION "private"."study_advanced_immutable"();
