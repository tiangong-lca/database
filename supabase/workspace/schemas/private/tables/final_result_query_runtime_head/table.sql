CREATE TABLE IF NOT EXISTS "private"."final_result_query_runtime_head" (
    "singleton" boolean DEFAULT true NOT NULL,
    "revision_id" "uuid" NOT NULL,
    CONSTRAINT "final_result_query_runtime_head_singleton_check" CHECK ("singleton")
);

ALTER TABLE "private"."final_result_query_runtime_head" OWNER TO "postgres";

ALTER TABLE ONLY "private"."final_result_query_runtime_head"
    ADD CONSTRAINT "final_result_query_runtime_head_pkey" PRIMARY KEY ("singleton");

ALTER TABLE ONLY "private"."final_result_query_runtime_head"
    ADD CONSTRAINT "final_result_query_runtime_head_revision_id_fkey" FOREIGN KEY ("revision_id") REFERENCES "private"."final_result_query_runtime_revisions"("id");

ALTER TABLE "private"."final_result_query_runtime_head" ENABLE ROW LEVEL SECURITY;
