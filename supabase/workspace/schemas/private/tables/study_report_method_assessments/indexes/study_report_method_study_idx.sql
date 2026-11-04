CREATE INDEX "study_report_method_study_idx" ON "private"."study_report_method_assessments" USING "btree" ("study_id", "report_id");
