CREATE TABLE IF NOT EXISTS "private"."final_result_candidate_artifacts" (
    "candidate_hash" "text" NOT NULL,
    "artifact_id" "uuid" NOT NULL
);

ALTER TABLE "private"."final_result_candidate_artifacts" OWNER TO "postgres";

ALTER TABLE ONLY "private"."final_result_candidate_artifacts"
    ADD CONSTRAINT "final_result_candidate_artifacts_pkey" PRIMARY KEY ("candidate_hash", "artifact_id");

ALTER TABLE ONLY "private"."final_result_candidate_artifacts"
    ADD CONSTRAINT "final_result_candidate_artifacts_artifact_id_fkey" FOREIGN KEY ("artifact_id") REFERENCES "private"."final_result_query_artifacts"("id");

ALTER TABLE ONLY "private"."final_result_candidate_artifacts"
    ADD CONSTRAINT "final_result_candidate_artifacts_candidate_hash_fkey" FOREIGN KEY ("candidate_hash") REFERENCES "private"."final_result_candidates"("candidate_hash");

ALTER TABLE "private"."final_result_candidate_artifacts" ENABLE ROW LEVEL SECURITY;
