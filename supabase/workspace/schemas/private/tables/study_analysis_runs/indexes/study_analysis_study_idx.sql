CREATE INDEX "study_analysis_study_idx" ON "private"."study_analysis_runs" USING "btree" ("study_id", "analysis_id");
