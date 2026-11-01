CREATE TABLE IF NOT EXISTS "private"."final_result_release_selection_seals" (
    "release_run_id" "uuid" NOT NULL,
    "selection_hash" "text" NOT NULL,
    "sealed_by" "uuid" NOT NULL,
    "sealed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "final_result_release_selection_seals_selection_hash_check" CHECK (("selection_hash" ~ '^[0-9a-f]{64}$'::"text"))
);

ALTER TABLE "private"."final_result_release_selection_seals" OWNER TO "postgres";

ALTER TABLE ONLY "private"."final_result_release_selection_seals"
    ADD CONSTRAINT "final_result_release_selection_seals_pkey" PRIMARY KEY ("release_run_id");

ALTER TABLE ONLY "private"."final_result_release_selection_seals"
    ADD CONSTRAINT "final_result_release_selection_seals_release_run_id_fkey" FOREIGN KEY ("release_run_id") REFERENCES "private"."final_result_release_plans"("release_run_id");

ALTER TABLE "private"."final_result_release_selection_seals" ENABLE ROW LEVEL SECURITY;
