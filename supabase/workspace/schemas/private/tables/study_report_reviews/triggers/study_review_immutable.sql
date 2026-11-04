CREATE OR REPLACE TRIGGER "study_review_immutable" BEFORE DELETE OR UPDATE ON "private"."study_report_reviews" FOR EACH ROW EXECUTE FUNCTION "private"."study_review_immutable"();
