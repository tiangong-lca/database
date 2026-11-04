CREATE INDEX "study_review_report_idx" ON "private"."study_report_reviews" USING "btree" ("study_id", "report_id", "id");
