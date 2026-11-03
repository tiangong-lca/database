CREATE INDEX "study_report_analysis_study_idx" ON "private"."study_report_analyses" USING "btree" ("study_id", "report_id");
