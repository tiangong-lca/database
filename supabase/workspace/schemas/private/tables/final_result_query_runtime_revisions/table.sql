CREATE TABLE IF NOT EXISTS "private"."final_result_query_runtime_revisions" (
    "id" "uuid" NOT NULL,
    "previous_revision_id" "uuid",
    "target_hash" "text" NOT NULL,
    "reader_sha256" "text" NOT NULL,
    "enabled" boolean NOT NULL,
    "reason" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "final_result_query_runtime_revisions_reader_sha256_check" CHECK (("reader_sha256" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "final_result_query_runtime_revisions_reason_check" CHECK (((("length"("reason") >= 1) AND ("length"("reason") <= 2000)) AND ("length"("btrim"("reason")) > 0))),
    CONSTRAINT "final_result_query_runtime_revisions_target_hash_check" CHECK (("target_hash" ~ '^[0-9a-f]{64}$'::"text"))
);

ALTER TABLE "private"."final_result_query_runtime_revisions" OWNER TO "postgres";

ALTER TABLE ONLY "private"."final_result_query_runtime_revisions"
    ADD CONSTRAINT "final_result_query_runtime_revisions_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."final_result_query_runtime_revisions"
    ADD CONSTRAINT "final_result_query_runtime_revisions_previous_revision_id_fkey" FOREIGN KEY ("previous_revision_id") REFERENCES "private"."final_result_query_runtime_revisions"("id");

ALTER TABLE "private"."final_result_query_runtime_revisions" ENABLE ROW LEVEL SECURITY;
