CREATE INDEX "study_method_evidence_intent_actor_idx" ON "private"."study_method_evidence_intents" USING "btree" ("actor_id", "expires_at");
