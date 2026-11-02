CREATE TABLE IF NOT EXISTS "private"."study_source_acquisitions" (
    "id" "uuid" NOT NULL,
    "study_id" "uuid" NOT NULL,
    "origin_ref" "jsonb" NOT NULL,
    "requested_by" "uuid" NOT NULL,
    "job_id" "uuid" NOT NULL,
    "snapshot_id" "uuid"
);

ALTER TABLE ONLY "private"."study_source_acquisitions" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_source_acquisitions" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_source_acquisitions"
    ADD CONSTRAINT "study_source_acquisitions_job_id_key" UNIQUE ("job_id");

ALTER TABLE ONLY "private"."study_source_acquisitions"
    ADD CONSTRAINT "study_source_acquisitions_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."study_source_acquisitions"
    ADD CONSTRAINT "study_source_acquisitions_study_id_id_key" UNIQUE ("study_id", "id");

ALTER TABLE ONLY "private"."study_source_acquisitions"
    ADD CONSTRAINT "study_source_acquisitions_job_id_fkey" FOREIGN KEY ("job_id") REFERENCES "private"."worker_jobs"("id");

ALTER TABLE ONLY "private"."study_source_acquisitions"
    ADD CONSTRAINT "study_source_acquisitions_requested_by_fkey" FOREIGN KEY ("requested_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "private"."study_source_acquisitions"
    ADD CONSTRAINT "study_source_acquisitions_study_id_fkey" FOREIGN KEY ("study_id") REFERENCES "private"."studies"("id");

ALTER TABLE ONLY "private"."study_source_acquisitions"
    ADD CONSTRAINT "study_source_acquisitions_study_id_snapshot_id_fkey" FOREIGN KEY ("study_id", "snapshot_id") REFERENCES "private"."study_source_snapshots"("study_id", "id");

ALTER TABLE "private"."study_source_acquisitions" ENABLE ROW LEVEL SECURITY;
