CREATE INDEX "study_advanced_analysis_snapshot_idx" ON "private"."study_advanced_analyses" USING "btree" ("study_id", "source_snapshot_id");
