CREATE INDEX "study_comment_report_idx" ON "private"."study_report_comments" USING "btree" ("study_id", "report_id", "id");
