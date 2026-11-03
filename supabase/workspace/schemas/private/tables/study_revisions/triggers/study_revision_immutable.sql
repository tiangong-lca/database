CREATE OR REPLACE TRIGGER "study_revision_immutable" BEFORE DELETE OR UPDATE ON "private"."study_revisions" FOR EACH ROW EXECUTE FUNCTION "private"."study_guard_immutable"();
