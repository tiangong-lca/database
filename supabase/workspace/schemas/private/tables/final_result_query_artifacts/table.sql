CREATE TABLE IF NOT EXISTS "private"."final_result_query_artifacts" (
    "id" "uuid" NOT NULL,
    "input_hash" "text" NOT NULL,
    "artifact_ref" "jsonb" NOT NULL,
    "manifest_text" "text" NOT NULL,
    "manifest" "jsonb" NOT NULL,
    "result_count" integer NOT NULL,
    "impact_count" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "final_result_query_artifacts_impact_count_check" CHECK ((("impact_count" >= 0) AND ("impact_count" <= 4096))),
    CONSTRAINT "final_result_query_artifacts_input_hash_check" CHECK (("input_hash" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "final_result_query_artifacts_manifest_text_check" CHECK ((("octet_length"("manifest_text") >= 1) AND ("octet_length"("manifest_text") <= 1048576))),
    CONSTRAINT "final_result_query_artifacts_result_count_check" CHECK ((("result_count" >= 1) AND ("result_count" <= 2000000)))
);

ALTER TABLE "private"."final_result_query_artifacts" OWNER TO "postgres";

ALTER TABLE ONLY "private"."final_result_query_artifacts"
    ADD CONSTRAINT "final_result_query_artifacts_pkey" PRIMARY KEY ("id");

ALTER TABLE "private"."final_result_query_artifacts" ENABLE ROW LEVEL SECURITY;
