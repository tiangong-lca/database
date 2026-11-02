CREATE INDEX "study_member_actor_idx" ON "private"."study_members" USING "btree" ("actor_id", "study_id");
