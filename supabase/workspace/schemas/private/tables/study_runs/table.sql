CREATE TABLE IF NOT EXISTS "private"."study_runs" (
    "id" "uuid" NOT NULL,
    "study_id" "uuid" NOT NULL,
    "study_revision_id" "uuid" NOT NULL,
    "scenario_id" "uuid" NOT NULL,
    "preparation_id" "uuid" NOT NULL,
    "input_hash" "text" NOT NULL,
    "model_ref" "jsonb" NOT NULL,
    "profile_id" "text" NOT NULL,
    "calculation_contract_ref" "jsonb" NOT NULL,
    "job_id" "uuid" NOT NULL,
    "result_artifact_id" "uuid",
    "validity" "text" DEFAULT 'current'::"text" NOT NULL,
    "validity_checked_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "requested_client_id" "text",
    CONSTRAINT "study_runs_input_hash_check" CHECK (("input_hash" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "study_runs_validity_check" CHECK (("validity" = ANY (ARRAY['current'::"text", 'superseded'::"text", 'withdrawn'::"text", 'unknown'::"text"])))
);

ALTER TABLE ONLY "private"."study_runs" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_runs" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_runs"
    ADD CONSTRAINT "study_runs_job_id_key" UNIQUE ("job_id");

ALTER TABLE ONLY "private"."study_runs"
    ADD CONSTRAINT "study_runs_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."study_runs"
    ADD CONSTRAINT "study_runs_study_id_id_key" UNIQUE ("study_id", "id");

ALTER TABLE ONLY "private"."study_runs"
    ADD CONSTRAINT "study_runs_job_id_fkey" FOREIGN KEY ("job_id") REFERENCES "private"."worker_jobs"("id");

ALTER TABLE ONLY "private"."study_runs"
    ADD CONSTRAINT "study_runs_study_id_fkey" FOREIGN KEY ("study_id") REFERENCES "private"."studies"("id");

ALTER TABLE ONLY "private"."study_runs"
    ADD CONSTRAINT "study_runs_study_id_preparation_id_fkey" FOREIGN KEY ("study_id", "preparation_id") REFERENCES "private"."study_model_preparations"("study_id", "id");

ALTER TABLE ONLY "private"."study_runs"
    ADD CONSTRAINT "study_runs_study_id_result_artifact_id_fkey" FOREIGN KEY ("study_id", "result_artifact_id") REFERENCES "private"."study_artifacts"("study_id", "id");

ALTER TABLE ONLY "private"."study_runs"
    ADD CONSTRAINT "study_runs_study_id_scenario_id_fkey" FOREIGN KEY ("study_id", "scenario_id") REFERENCES "private"."study_scenarios"("study_id", "id");

ALTER TABLE ONLY "private"."study_runs"
    ADD CONSTRAINT "study_runs_study_id_study_revision_id_fkey" FOREIGN KEY ("study_id", "study_revision_id") REFERENCES "private"."study_revisions"("study_id", "id");

ALTER TABLE "private"."study_runs" ENABLE ROW LEVEL SECURITY;
