CREATE TABLE IF NOT EXISTS "private"."final_result_candidates" (
    "candidate_hash" "text" NOT NULL,
    "input_hash" "text" NOT NULL,
    "manifest" "jsonb" NOT NULL,
    "manifest_byte_size" bigint NOT NULL,
    "catalog_hash" "text" NOT NULL,
    "catalog_byte_size" bigint NOT NULL,
    "member_count" integer NOT NULL,
    "result_count" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "final_result_candidates_candidate_hash_check" CHECK (("candidate_hash" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "final_result_candidates_catalog_byte_size_check" CHECK ((("catalog_byte_size" >= 1) AND ("catalog_byte_size" <= 134217728))),
    CONSTRAINT "final_result_candidates_catalog_hash_check" CHECK (("catalog_hash" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "final_result_candidates_input_hash_check" CHECK (("input_hash" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "final_result_candidates_manifest_byte_size_check" CHECK ((("manifest_byte_size" >= 1) AND ("manifest_byte_size" <= 134217728))),
    CONSTRAINT "final_result_candidates_member_count_check" CHECK ((("member_count" >= 1) AND ("member_count" <= 2000000))),
    CONSTRAINT "final_result_candidates_result_count_check" CHECK ((("result_count" >= 1) AND ("result_count" <= 2000000)))
);

ALTER TABLE "private"."final_result_candidates" OWNER TO "postgres";

ALTER TABLE ONLY "private"."final_result_candidates"
    ADD CONSTRAINT "final_result_candidates_pkey" PRIMARY KEY ("candidate_hash");

ALTER TABLE "private"."final_result_candidates" ENABLE ROW LEVEL SECURITY;
