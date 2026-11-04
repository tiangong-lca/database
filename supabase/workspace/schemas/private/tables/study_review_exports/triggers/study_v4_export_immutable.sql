CREATE OR REPLACE TRIGGER "study_v4_export_immutable" BEFORE DELETE OR UPDATE ON "private"."study_review_exports" FOR EACH ROW EXECUTE FUNCTION "private"."study_review_immutable"();
