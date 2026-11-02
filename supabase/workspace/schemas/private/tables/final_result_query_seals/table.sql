CREATE TABLE IF NOT EXISTS "private"."final_result_query_seals" (
    "artifact_id" "uuid" NOT NULL,
    "target_hash" "text" NOT NULL,
    "row_bindings_hash" "text" NOT NULL,
    "readback_id" "uuid" NOT NULL,
    "receipt" "jsonb" NOT NULL,
    "sealed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "final_result_query_seals_row_bindings_hash_check" CHECK (("row_bindings_hash" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "final_result_query_seals_target_hash_check" CHECK (("target_hash" ~ '^[0-9a-f]{64}$'::"text"))
);

ALTER TABLE "private"."final_result_query_seals" OWNER TO "postgres";

ALTER TABLE ONLY "private"."final_result_query_seals"
    ADD CONSTRAINT "final_result_query_seals_pkey" PRIMARY KEY ("artifact_id", "target_hash");

ALTER TABLE ONLY "private"."final_result_query_seals"
    ADD CONSTRAINT "final_result_query_seals_readback_id_key" UNIQUE ("readback_id");

ALTER TABLE ONLY "private"."final_result_query_seals"
    ADD CONSTRAINT "final_result_query_seals_artifact_id_fkey" FOREIGN KEY ("artifact_id") REFERENCES "private"."final_result_query_artifacts"("id");

ALTER TABLE "private"."final_result_query_seals" ENABLE ROW LEVEL SECURITY;
