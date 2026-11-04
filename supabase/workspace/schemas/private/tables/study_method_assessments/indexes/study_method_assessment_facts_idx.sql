CREATE INDEX "study_method_assessment_facts_idx" ON "private"."study_method_assessments" USING "btree" ("study_id", "facts_artifact_id");
