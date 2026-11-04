CREATE INDEX "study_method_assessment_baseline_idx" ON "private"."study_method_assessments" USING "btree" ("study_id", "baseline_run_id");
