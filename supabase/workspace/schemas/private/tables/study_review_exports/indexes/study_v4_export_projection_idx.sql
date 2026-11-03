CREATE INDEX "study_v4_export_projection_idx" ON "private"."study_review_exports" USING "btree" ("study_id", "projection_artifact_id");
