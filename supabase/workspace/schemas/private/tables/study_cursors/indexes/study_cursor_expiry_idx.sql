CREATE INDEX "study_cursor_expiry_idx" ON "private"."study_cursors" USING "btree" ("expires_at");
