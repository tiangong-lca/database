CREATE INDEX "final_result_query_source_lookup_idx" ON "private"."final_result_query_sources" USING "btree" ("source_id", "source_version", "artifact_id", "row_ordinal");
