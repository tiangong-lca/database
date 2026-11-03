CREATE TABLE IF NOT EXISTS "private"."study_analyses" (
    "id" "uuid" NOT NULL,
    "study_id" "uuid" NOT NULL,
    "profile_id" "text" NOT NULL,
    "config" "jsonb" NOT NULL,
    "config_hash" "text" NOT NULL,
    "job_id" "uuid" NOT NULL,
    "requested_by" "uuid" NOT NULL,
    "requested_client_id" "text",
    "comparability" "jsonb" DEFAULT '{"status": "not_assessed", "reasonCodes": []}'::"jsonb" NOT NULL,
    "facts_artifact_id" "uuid",
    CONSTRAINT "study_analyses_check" CHECK (("config_hash" = "private"."study_analysis_config_hash"("config"))),
    CONSTRAINT "study_analyses_comparability_check" CHECK ("private"."study_comparability_valid"("comparability")),
    CONSTRAINT "study_analyses_config_check" CHECK ("private"."study_analysis_config_valid"("config")),
    CONSTRAINT "study_analyses_profile_id_check" CHECK (("profile_id" = 'lca.study-analysis-explicit-v1'::"text"))
);

ALTER TABLE ONLY "private"."study_analyses" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_analyses" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_analyses"
    ADD CONSTRAINT "study_analyses_job_id_key" UNIQUE ("job_id");

ALTER TABLE ONLY "private"."study_analyses"
    ADD CONSTRAINT "study_analyses_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."study_analyses"
    ADD CONSTRAINT "study_analyses_study_id_id_key" UNIQUE ("study_id", "id");

ALTER TABLE ONLY "private"."study_analyses"
    ADD CONSTRAINT "study_analyses_job_id_fkey" FOREIGN KEY ("job_id") REFERENCES "private"."worker_jobs"("id");

ALTER TABLE ONLY "private"."study_analyses"
    ADD CONSTRAINT "study_analyses_requested_by_fkey" FOREIGN KEY ("requested_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "private"."study_analyses"
    ADD CONSTRAINT "study_analyses_study_id_facts_artifact_id_fkey" FOREIGN KEY ("study_id", "facts_artifact_id") REFERENCES "private"."study_artifacts"("study_id", "id");

ALTER TABLE ONLY "private"."study_analyses"
    ADD CONSTRAINT "study_analyses_study_id_fkey" FOREIGN KEY ("study_id") REFERENCES "private"."studies"("id");

ALTER TABLE "private"."study_analyses" ENABLE ROW LEVEL SECURITY;
