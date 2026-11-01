CREATE TABLE IF NOT EXISTS "private"."final_result_candidate_members" (
    "candidate_hash" "text" NOT NULL,
    "dataset_kind" "text" NOT NULL,
    "dataset_id" "uuid" NOT NULL,
    "dataset_version" "text" NOT NULL,
    "dataset_key" "text" NOT NULL,
    "dataset_role" "text" NOT NULL,
    "canonical_content_hash" "text" NOT NULL,
    CONSTRAINT "final_result_candidate_members_canonical_content_hash_check" CHECK (("canonical_content_hash" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "final_result_candidate_members_dataset_kind_check" CHECK (("dataset_kind" = ANY (ARRAY['process'::"text", 'flow'::"text", 'flowproperty'::"text", 'unitgroup'::"text", 'lciamethod'::"text", 'contact'::"text", 'source'::"text"]))),
    CONSTRAINT "final_result_candidate_members_dataset_version_check" CHECK (("dataset_version" ~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$'::"text"))
);

ALTER TABLE "private"."final_result_candidate_members" OWNER TO "postgres";

ALTER TABLE ONLY "private"."final_result_candidate_members"
    ADD CONSTRAINT "final_result_candidate_members_candidate_hash_dataset_key_key" UNIQUE ("candidate_hash", "dataset_key");

ALTER TABLE ONLY "private"."final_result_candidate_members"
    ADD CONSTRAINT "final_result_candidate_members_pkey" PRIMARY KEY ("candidate_hash", "dataset_kind", "dataset_id", "dataset_version");

ALTER TABLE ONLY "private"."final_result_candidate_members"
    ADD CONSTRAINT "final_result_candidate_members_candidate_hash_fkey" FOREIGN KEY ("candidate_hash") REFERENCES "private"."final_result_candidates"("candidate_hash");

ALTER TABLE "private"."final_result_candidate_members" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON TABLE "private"."final_result_candidate_members" TO "api_internal_executor";
