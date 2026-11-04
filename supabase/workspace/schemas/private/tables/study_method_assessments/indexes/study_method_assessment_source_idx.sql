CREATE INDEX "study_method_assessment_source_idx" ON "private"."study_method_assessments" USING "btree" ("study_id", "source_snapshot_id");
