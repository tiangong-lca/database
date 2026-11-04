CREATE OR REPLACE TRIGGER "study_finalization_immutable" BEFORE DELETE OR UPDATE ON "private"."study_report_finalizations" FOR EACH ROW EXECUTE FUNCTION "private"."study_review_immutable"();
