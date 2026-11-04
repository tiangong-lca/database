CREATE TABLE IF NOT EXISTS "private"."study_advanced_analyses" (
    "id" "uuid" NOT NULL,
    "study_id" "uuid" NOT NULL,
    "profile_id" "text" NOT NULL,
    "config" "jsonb" NOT NULL,
    "config_hash" "text" NOT NULL,
    "baseline_run_id" "uuid" NOT NULL,
    "source_snapshot_id" "uuid" NOT NULL,
    "job_id" "uuid" NOT NULL,
    "requested_by" "uuid" NOT NULL,
    "requested_client_id" "text",
    "facts_artifact_id" "uuid",
    CONSTRAINT "study_advanced_analyses_check" CHECK (("config_hash" = "private"."study_advanced_config_hash"("config"))),
    CONSTRAINT "study_advanced_analyses_check1" CHECK ((("config" ->> 'baselineRunId'::"text") = ("baseline_run_id")::"text")),
    CONSTRAINT "study_advanced_analyses_check2" CHECK (((("profile_id" = 'lca.study-sensitivity-oat.v1'::"text") AND (("config" ->> 'kind'::"text") = 'sensitivityOat'::"text")) OR (("profile_id" = 'lca.study-uncertainty-bounded.v1'::"text") AND (("config" ->> 'kind'::"text") = 'uncertainty'::"text")))),
    CONSTRAINT "study_advanced_analyses_config_check" CHECK ("private"."study_advanced_config_valid"("config"))
);

ALTER TABLE ONLY "private"."study_advanced_analyses" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_advanced_analyses" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_advanced_analyses"
    ADD CONSTRAINT "study_advanced_analyses_job_id_key" UNIQUE ("job_id");

ALTER TABLE ONLY "private"."study_advanced_analyses"
    ADD CONSTRAINT "study_advanced_analyses_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."study_advanced_analyses"
    ADD CONSTRAINT "study_advanced_analyses_study_id_id_key" UNIQUE ("study_id", "id");

ALTER TABLE ONLY "private"."study_advanced_analyses"
    ADD CONSTRAINT "study_advanced_analyses_job_id_fkey" FOREIGN KEY ("job_id") REFERENCES "private"."worker_jobs"("id");

ALTER TABLE ONLY "private"."study_advanced_analyses"
    ADD CONSTRAINT "study_advanced_analyses_requested_by_fkey" FOREIGN KEY ("requested_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "private"."study_advanced_analyses"
    ADD CONSTRAINT "study_advanced_analyses_study_id_baseline_run_id_fkey" FOREIGN KEY ("study_id", "baseline_run_id") REFERENCES "private"."study_runs"("study_id", "id");

ALTER TABLE ONLY "private"."study_advanced_analyses"
    ADD CONSTRAINT "study_advanced_analyses_study_id_facts_artifact_id_fkey" FOREIGN KEY ("study_id", "facts_artifact_id") REFERENCES "private"."study_artifacts"("study_id", "id");

ALTER TABLE ONLY "private"."study_advanced_analyses"
    ADD CONSTRAINT "study_advanced_analyses_study_id_fkey" FOREIGN KEY ("study_id") REFERENCES "private"."studies"("id");

ALTER TABLE ONLY "private"."study_advanced_analyses"
    ADD CONSTRAINT "study_advanced_analyses_study_id_source_snapshot_id_fkey" FOREIGN KEY ("study_id", "source_snapshot_id") REFERENCES "private"."study_source_snapshots"("study_id", "id");

ALTER TABLE "private"."study_advanced_analyses" ENABLE ROW LEVEL SECURITY;
