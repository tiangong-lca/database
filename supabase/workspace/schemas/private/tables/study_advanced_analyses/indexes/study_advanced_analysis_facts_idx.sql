CREATE INDEX "study_advanced_analysis_facts_idx" ON "private"."study_advanced_analyses" USING "btree" ("study_id", "facts_artifact_id");
