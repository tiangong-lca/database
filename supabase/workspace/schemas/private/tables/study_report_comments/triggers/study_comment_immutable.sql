CREATE OR REPLACE TRIGGER "study_comment_immutable" BEFORE DELETE OR UPDATE ON "private"."study_report_comments" FOR EACH ROW EXECUTE FUNCTION "private"."study_review_immutable"();
