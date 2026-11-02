CREATE TABLE IF NOT EXISTS "private"."study_service_receipts" (
    "operation" "text" NOT NULL,
    "study_id" "uuid" NOT NULL,
    "idempotency_key" "text" NOT NULL,
    "job_id" "uuid" NOT NULL,
    "lease_token" "uuid" NOT NULL,
    "request" "jsonb" NOT NULL,
    "response" "jsonb" NOT NULL,
    CONSTRAINT "study_service_receipts_idempotency_key_check" CHECK ((("length"("idempotency_key") >= 1) AND ("length"("idempotency_key") <= 128)))
);

ALTER TABLE ONLY "private"."study_service_receipts" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_service_receipts" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_service_receipts"
    ADD CONSTRAINT "study_service_receipts_pkey" PRIMARY KEY ("operation", "study_id", "idempotency_key");

ALTER TABLE ONLY "private"."study_service_receipts"
    ADD CONSTRAINT "study_service_receipts_job_id_fkey" FOREIGN KEY ("job_id") REFERENCES "private"."worker_jobs"("id");

ALTER TABLE ONLY "private"."study_service_receipts"
    ADD CONSTRAINT "study_service_receipts_study_id_fkey" FOREIGN KEY ("study_id") REFERENCES "private"."studies"("id");

ALTER TABLE "private"."study_service_receipts" ENABLE ROW LEVEL SECURITY;
