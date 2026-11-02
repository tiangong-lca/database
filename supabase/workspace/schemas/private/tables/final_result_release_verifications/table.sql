CREATE TABLE IF NOT EXISTS "private"."final_result_release_verifications" (
    "id" "uuid" NOT NULL,
    "release_run_id" "uuid" NOT NULL,
    "runtime_revision" "uuid" NOT NULL,
    "header" "jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "final_result_release_verifications_header_check" CHECK (("pg_column_size"("header") <= 32768))
);

ALTER TABLE "private"."final_result_release_verifications" OWNER TO "postgres";

ALTER TABLE ONLY "private"."final_result_release_verifications"
    ADD CONSTRAINT "final_result_release_verifications_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."final_result_release_verifications"
    ADD CONSTRAINT "final_result_release_verifications_release_run_id_fkey" FOREIGN KEY ("release_run_id") REFERENCES "private"."final_result_release_plans"("release_run_id");

ALTER TABLE ONLY "private"."final_result_release_verifications"
    ADD CONSTRAINT "final_result_release_verifications_runtime_revision_fkey" FOREIGN KEY ("runtime_revision") REFERENCES "private"."final_result_query_runtime_revisions"("id");

ALTER TABLE "private"."final_result_release_verifications" ENABLE ROW LEVEL SECURITY;
