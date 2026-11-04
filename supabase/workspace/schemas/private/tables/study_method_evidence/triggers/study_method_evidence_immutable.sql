CREATE OR REPLACE TRIGGER "study_method_evidence_immutable" BEFORE DELETE OR UPDATE ON "private"."study_method_evidence" FOR EACH ROW EXECUTE FUNCTION "private"."study_report_immutable"();
