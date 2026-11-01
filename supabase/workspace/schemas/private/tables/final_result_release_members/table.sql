CREATE TABLE IF NOT EXISTS "private"."final_result_release_members" (
    "release_run_id" "uuid" NOT NULL,
    "result_id" "uuid" NOT NULL,
    "result_version" "text" NOT NULL,
    "artifact_id" "uuid" NOT NULL,
    "row_ordinal" integer NOT NULL,
    CONSTRAINT "final_result_release_members_result_version_check" CHECK (("result_version" ~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$'::"text"))
);

ALTER TABLE "private"."final_result_release_members" OWNER TO "postgres";

ALTER TABLE ONLY "private"."final_result_release_members"
    ADD CONSTRAINT "final_result_release_members_pkey" PRIMARY KEY ("release_run_id", "result_id", "result_version");

ALTER TABLE ONLY "private"."final_result_release_members"
    ADD CONSTRAINT "final_result_release_members_artifact_id_row_ordinal_fkey" FOREIGN KEY ("artifact_id", "row_ordinal") REFERENCES "private"."final_result_query_rows"("artifact_id", "row_ordinal");

ALTER TABLE ONLY "private"."final_result_release_members"
    ADD CONSTRAINT "final_result_release_members_release_run_id_fkey" FOREIGN KEY ("release_run_id") REFERENCES "private"."final_result_release_plans"("release_run_id");

ALTER TABLE "private"."final_result_release_members" ENABLE ROW LEVEL SECURITY;
