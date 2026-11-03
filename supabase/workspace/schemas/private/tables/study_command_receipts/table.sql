CREATE TABLE IF NOT EXISTS "private"."study_command_receipts" (
    "actor_id" "uuid" NOT NULL,
    "operation" "text" NOT NULL,
    "scope" "text" NOT NULL,
    "idempotency_key" "text" NOT NULL,
    "request" "jsonb" NOT NULL,
    "response" "jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "study_command_receipts_idempotency_key_check" CHECK ((("length"("idempotency_key") >= 1) AND ("length"("idempotency_key") <= 128)))
);

ALTER TABLE ONLY "private"."study_command_receipts" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_command_receipts" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_command_receipts"
    ADD CONSTRAINT "study_command_receipts_pkey" PRIMARY KEY ("actor_id", "operation", "scope", "idempotency_key");

ALTER TABLE ONLY "private"."study_command_receipts"
    ADD CONSTRAINT "study_command_receipts_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "auth"."users"("id");

ALTER TABLE "private"."study_command_receipts" ENABLE ROW LEVEL SECURITY;
