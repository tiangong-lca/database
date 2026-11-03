CREATE INDEX "study_artifact_intent_expiry_idx" ON "private"."study_artifact_read_intents" USING "btree" ("expires_at", "id");
