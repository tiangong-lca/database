CREATE TABLE IF NOT EXISTS "private"."model_bundle_save_receipts" (
    "actor_id" "uuid" NOT NULL,
    "operation_id" "uuid" NOT NULL,
    "request_hash" "bytea" NOT NULL,
    "model_id" "uuid" NOT NULL,
    "model_version" "text" NOT NULL,
    "revision" "text" NOT NULL,
    "members" "jsonb" NOT NULL,
    "saved_at" timestamp with time zone DEFAULT "transaction_timestamp"() NOT NULL
);

ALTER TABLE "private"."model_bundle_save_receipts" OWNER TO "postgres";

ALTER TABLE ONLY "private"."model_bundle_save_receipts"
    ADD CONSTRAINT "model_bundle_save_receipts_pkey" PRIMARY KEY ("actor_id", "operation_id");

ALTER TABLE "private"."model_bundle_save_receipts" ENABLE ROW LEVEL SECURITY;
