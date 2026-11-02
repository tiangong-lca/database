CREATE TABLE IF NOT EXISTS "private"."final_result_release_readiness" (
    "verification_id" "uuid" NOT NULL,
    "receipt" "jsonb" NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "sealed_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "final_result_release_readiness_receipt_check" CHECK (("pg_column_size"("receipt") <= 32768))
);

ALTER TABLE "private"."final_result_release_readiness" OWNER TO "postgres";

ALTER TABLE ONLY "private"."final_result_release_readiness"
    ADD CONSTRAINT "final_result_release_readiness_pkey" PRIMARY KEY ("verification_id");

ALTER TABLE ONLY "private"."final_result_release_readiness"
    ADD CONSTRAINT "final_result_release_readiness_verification_id_fkey" FOREIGN KEY ("verification_id") REFERENCES "private"."final_result_release_verifications"("id");

ALTER TABLE "private"."final_result_release_readiness" ENABLE ROW LEVEL SECURITY;
