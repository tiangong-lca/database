CREATE INDEX "study_report_intent_expiry_idx" ON "private"."study_report_intents" USING "btree" ("expires_at", "id");
