CREATE TABLE IF NOT EXISTS "private"."final_result_release_plans" (
    "release_run_id" "uuid" NOT NULL,
    "candidate_hash" "text" NOT NULL,
    "target_hash" "text" NOT NULL,
    "selection_count" integer NOT NULL,
    "expected_current_publication_id" "uuid",
    "rollback_of_publication_id" "uuid",
    "plan_text" "text" NOT NULL,
    CONSTRAINT "final_result_release_plans_plan_text_check" CHECK ((("octet_length"("plan_text") >= 1) AND ("octet_length"("plan_text") <= 16384))),
    CONSTRAINT "final_result_release_plans_selection_count_check" CHECK ((("selection_count" >= 1) AND ("selection_count" <= 2000000)))
);

ALTER TABLE "private"."final_result_release_plans" OWNER TO "postgres";

ALTER TABLE ONLY "private"."final_result_release_plans"
    ADD CONSTRAINT "final_result_release_plans_pkey" PRIMARY KEY ("release_run_id");

ALTER TABLE ONLY "private"."final_result_release_plans"
    ADD CONSTRAINT "final_result_release_plans_candidate_hash_fkey" FOREIGN KEY ("candidate_hash") REFERENCES "private"."final_result_candidates"("candidate_hash");

ALTER TABLE ONLY "private"."final_result_release_plans"
    ADD CONSTRAINT "final_result_release_plans_candidate_hash_target_hash_fkey" FOREIGN KEY ("candidate_hash", "target_hash") REFERENCES "private"."final_result_candidate_storage"("candidate_hash", "target_hash");

ALTER TABLE ONLY "private"."final_result_release_plans"
    ADD CONSTRAINT "final_result_release_plans_expected_current_publication_id_fkey" FOREIGN KEY ("expected_current_publication_id") REFERENCES "private"."lca_release_publications"("id");

ALTER TABLE ONLY "private"."final_result_release_plans"
    ADD CONSTRAINT "final_result_release_plans_release_run_id_fkey" FOREIGN KEY ("release_run_id") REFERENCES "private"."lca_release_runs"("id");

ALTER TABLE ONLY "private"."final_result_release_plans"
    ADD CONSTRAINT "final_result_release_plans_rollback_of_publication_id_fkey" FOREIGN KEY ("rollback_of_publication_id") REFERENCES "private"."lca_release_publications"("id");

ALTER TABLE "private"."final_result_release_plans" ENABLE ROW LEVEL SECURITY;
