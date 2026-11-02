CREATE INDEX "final_result_release_members_artifact_idx" ON "private"."final_result_release_members" USING "btree" ("release_run_id", "artifact_id", "result_id", "result_version");
