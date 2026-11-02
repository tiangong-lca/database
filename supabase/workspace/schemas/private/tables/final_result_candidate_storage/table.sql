CREATE TABLE IF NOT EXISTS "private"."final_result_candidate_storage" (
    "candidate_hash" "text" NOT NULL,
    "target_hash" "text" NOT NULL,
    "readback_id" "uuid" NOT NULL,
    "receipt" "jsonb" NOT NULL,
    "verified_at" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "final_result_candidate_storage_target_hash_check" CHECK (("target_hash" ~ '^[0-9a-f]{64}$'::"text"))
);

ALTER TABLE "private"."final_result_candidate_storage" OWNER TO "postgres";

ALTER TABLE ONLY "private"."final_result_candidate_storage"
    ADD CONSTRAINT "final_result_candidate_storage_pkey" PRIMARY KEY ("candidate_hash", "target_hash");

ALTER TABLE ONLY "private"."final_result_candidate_storage"
    ADD CONSTRAINT "final_result_candidate_storage_readback_id_key" UNIQUE ("readback_id");

ALTER TABLE ONLY "private"."final_result_candidate_storage"
    ADD CONSTRAINT "final_result_candidate_storage_candidate_hash_fkey" FOREIGN KEY ("candidate_hash") REFERENCES "private"."final_result_candidates"("candidate_hash");

ALTER TABLE "private"."final_result_candidate_storage" ENABLE ROW LEVEL SECURITY;
