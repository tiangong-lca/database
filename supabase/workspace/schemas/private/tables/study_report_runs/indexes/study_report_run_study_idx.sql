CREATE INDEX "study_report_run_study_idx" ON "private"."study_report_runs" USING "btree" ("study_id", "report_id");
