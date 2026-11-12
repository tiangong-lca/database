CREATE INDEX "portal_index_outbox_due_idx" ON "private"."portal_index_outbox" USING "btree" ("provider", "available_at", "event_id") WHERE ("state" = 'pending'::"text");
