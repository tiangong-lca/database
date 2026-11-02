CREATE TABLE IF NOT EXISTS "private"."final_result_release_artifact_proofs" (
    "verification_id" "uuid" NOT NULL,
    "artifact_id" "uuid" NOT NULL,
    "proof" "jsonb" NOT NULL,
    "proof_sha256" "text" NOT NULL,
    CONSTRAINT "final_result_release_artifact_proofs_proof_check" CHECK (("pg_column_size"("proof") <= 65536)),
    CONSTRAINT "final_result_release_artifact_proofs_proof_sha256_check" CHECK (("proof_sha256" ~ '^[0-9a-f]{64}$'::"text"))
);

ALTER TABLE "private"."final_result_release_artifact_proofs" OWNER TO "postgres";

ALTER TABLE ONLY "private"."final_result_release_artifact_proofs"
    ADD CONSTRAINT "final_result_release_artifact_proofs_pkey" PRIMARY KEY ("verification_id", "artifact_id");

ALTER TABLE ONLY "private"."final_result_release_artifact_proofs"
    ADD CONSTRAINT "final_result_release_artifact_proofs_artifact_id_fkey" FOREIGN KEY ("artifact_id") REFERENCES "private"."final_result_query_artifacts"("id");

ALTER TABLE ONLY "private"."final_result_release_artifact_proofs"
    ADD CONSTRAINT "final_result_release_artifact_proofs_verification_id_fkey" FOREIGN KEY ("verification_id") REFERENCES "private"."final_result_release_verifications"("id");

ALTER TABLE "private"."final_result_release_artifact_proofs" ENABLE ROW LEVEL SECURITY;
