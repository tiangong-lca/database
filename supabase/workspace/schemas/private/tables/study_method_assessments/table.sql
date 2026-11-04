CREATE TABLE IF NOT EXISTS "private"."study_method_assessments" (
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
    "admitted_max_evidence_refs" integer NOT NULL,
    "admitted_max_selected_factor_records" integer NOT NULL,
    "facts_artifact_id" "uuid",
    "selected_factor_record_count" integer,
    CONSTRAINT "study_method_assessments_admitted_max_evidence_refs_check" CHECK ((("admitted_max_evidence_refs" >= 0) AND ("admitted_max_evidence_refs" <= 128))),
    CONSTRAINT "study_method_assessments_admitted_max_selected_factor_rec_check" CHECK ((("admitted_max_selected_factor_records" >= 1) AND ("admitted_max_selected_factor_records" <= 8192))),
    CONSTRAINT "study_method_assessments_check" CHECK ((("selected_factor_record_count" >= 0) AND ("selected_factor_record_count" <= "admitted_max_selected_factor_records"))),
    CONSTRAINT "study_method_assessments_check1" CHECK (("config_hash" = "private"."study_method_config_hash"("config"))),
    CONSTRAINT "study_method_assessments_check2" CHECK ((("config" ->> 'baselineRunId'::"text") = ("baseline_run_id")::"text")),
    CONSTRAINT "study_method_assessments_check3" CHECK ((("facts_artifact_id" IS NULL) = ("selected_factor_record_count" IS NULL))),
    CONSTRAINT "study_method_assessments_config_check" CHECK ("private"."study_method_config_valid"("config")),
    CONSTRAINT "study_method_assessments_config_hash_check" CHECK (("config_hash" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "study_method_assessments_profile_id_check" CHECK (("profile_id" = 'lca.study-method-pef-2021-ef31-cement-intermediate.v1'::"text"))
);

ALTER TABLE ONLY "private"."study_method_assessments" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_method_assessments" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_method_assessments"
    ADD CONSTRAINT "study_method_assessments_job_id_key" UNIQUE ("job_id");

ALTER TABLE ONLY "private"."study_method_assessments"
    ADD CONSTRAINT "study_method_assessments_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."study_method_assessments"
    ADD CONSTRAINT "study_method_assessments_study_id_id_key" UNIQUE ("study_id", "id");

ALTER TABLE ONLY "private"."study_method_assessments"
    ADD CONSTRAINT "study_method_assessments_job_id_fkey" FOREIGN KEY ("job_id") REFERENCES "private"."worker_jobs"("id");

ALTER TABLE ONLY "private"."study_method_assessments"
    ADD CONSTRAINT "study_method_assessments_requested_by_fkey" FOREIGN KEY ("requested_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "private"."study_method_assessments"
    ADD CONSTRAINT "study_method_assessments_study_id_baseline_run_id_fkey" FOREIGN KEY ("study_id", "baseline_run_id") REFERENCES "private"."study_runs"("study_id", "id");

ALTER TABLE ONLY "private"."study_method_assessments"
    ADD CONSTRAINT "study_method_assessments_study_id_facts_artifact_id_fkey" FOREIGN KEY ("study_id", "facts_artifact_id") REFERENCES "private"."study_artifacts"("study_id", "id");

ALTER TABLE ONLY "private"."study_method_assessments"
    ADD CONSTRAINT "study_method_assessments_study_id_fkey" FOREIGN KEY ("study_id") REFERENCES "private"."studies"("id");

ALTER TABLE ONLY "private"."study_method_assessments"
    ADD CONSTRAINT "study_method_assessments_study_id_source_snapshot_id_fkey" FOREIGN KEY ("study_id", "source_snapshot_id") REFERENCES "private"."study_source_snapshots"("study_id", "id");

ALTER TABLE "private"."study_method_assessments" ENABLE ROW LEVEL SECURITY;
