CREATE INDEX "final_result_publication_history_idx" ON "private"."lca_release_publications" USING "btree" ("published_at" DESC, "id" DESC) WHERE (NOT "is_current");
