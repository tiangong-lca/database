CREATE INDEX "study_export_report_idx" ON "private"."study_report_exports" USING "btree" ("study_id", "report_id");
