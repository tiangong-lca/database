CREATE INDEX "study_share_report_idx" ON "private"."study_report_shares" USING "btree" ("study_id", "report_id", "id");
