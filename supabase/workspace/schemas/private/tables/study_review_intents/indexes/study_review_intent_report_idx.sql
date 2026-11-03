CREATE INDEX "study_review_intent_report_idx" ON "private"."study_review_intents" USING "btree" ("study_id", "report_id");
