CREATE INDEX "portal_index_outbox_held_idx" ON "private"."portal_index_outbox" USING "btree" ("event_id") WHERE ("state" = 'held'::"text");
