CREATE INDEX "study_delegation_report_idx" ON "private"."study_review_delegations" USING "btree" ("study_id", "report_id", "id");
