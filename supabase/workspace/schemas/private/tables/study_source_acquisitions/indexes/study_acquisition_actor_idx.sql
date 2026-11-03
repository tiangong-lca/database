CREATE INDEX "study_acquisition_actor_idx" ON "private"."study_source_acquisitions" USING "btree" ("requested_by");
