CREATE INDEX "portal_index_outbox_blocked_idx" ON "private"."portal_index_outbox" USING "btree" ("provider", "last_reason", "event_id") WHERE ("state" = 'blocked'::"text");
