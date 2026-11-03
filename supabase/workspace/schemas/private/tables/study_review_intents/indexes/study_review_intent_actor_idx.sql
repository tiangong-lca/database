CREATE INDEX "study_review_intent_actor_idx" ON "private"."study_review_intents" USING "btree" ("actor_id", "expires_at");
