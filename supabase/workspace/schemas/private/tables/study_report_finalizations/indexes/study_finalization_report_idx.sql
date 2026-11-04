CREATE INDEX "study_finalization_report_idx" ON "private"."study_report_finalizations" USING "btree" ("study_id", "report_id", "finalized_at", "id");
