CREATE INDEX "study_artifact_intent_artifact_idx" ON "private"."study_artifact_read_intents" USING "btree" ("study_id", "artifact_id");
