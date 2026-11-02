CREATE TABLE IF NOT EXISTS "private"."final_result_publication_bindings" (
    "publication_id" "uuid" NOT NULL,
    "verification_id" "uuid" NOT NULL,
    "previous_publication_id" "uuid",
    "rollback_of_publication_id" "uuid"
);

ALTER TABLE "private"."final_result_publication_bindings" OWNER TO "postgres";

ALTER TABLE ONLY "private"."final_result_publication_bindings"
    ADD CONSTRAINT "final_result_publication_bindings_pkey" PRIMARY KEY ("publication_id");

ALTER TABLE ONLY "private"."final_result_publication_bindings"
    ADD CONSTRAINT "final_result_publication_bindin_rollback_of_publication_id_fkey" FOREIGN KEY ("rollback_of_publication_id") REFERENCES "private"."lca_release_publications"("id");

ALTER TABLE ONLY "private"."final_result_publication_bindings"
    ADD CONSTRAINT "final_result_publication_bindings_previous_publication_id_fkey" FOREIGN KEY ("previous_publication_id") REFERENCES "private"."lca_release_publications"("id");

ALTER TABLE ONLY "private"."final_result_publication_bindings"
    ADD CONSTRAINT "final_result_publication_bindings_publication_id_fkey" FOREIGN KEY ("publication_id") REFERENCES "private"."lca_release_publications"("id");

ALTER TABLE ONLY "private"."final_result_publication_bindings"
    ADD CONSTRAINT "final_result_publication_bindings_verification_id_fkey" FOREIGN KEY ("verification_id") REFERENCES "private"."final_result_release_readiness"("verification_id");

ALTER TABLE "private"."final_result_publication_bindings" ENABLE ROW LEVEL SECURITY;
