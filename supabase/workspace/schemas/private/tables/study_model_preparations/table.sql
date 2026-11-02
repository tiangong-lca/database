CREATE TABLE IF NOT EXISTS "private"."study_model_preparations" (
    "id" "uuid" NOT NULL,
    "study_id" "uuid" NOT NULL,
    "source" "jsonb" NOT NULL,
    "source_document" "jsonb" NOT NULL,
    "source_snapshot_id" "uuid",
    "source_scenario_id" "uuid",
    "source_study_revision_id" "uuid",
    "source_parent_scenario_id" "uuid",
    "method_refs" "jsonb" NOT NULL,
    "profile_id" "text" NOT NULL,
    "calculation_contract_ref" "jsonb" NOT NULL,
    "job_id" "uuid" NOT NULL,
    "model_ref" "jsonb",
    "input_artifact_id" "uuid",
    "input_hash" "text",
    CONSTRAINT "study_model_preparations_calculation_contract_ref_check" CHECK (((("calculation_contract_ref" ->> 'kind'::"text") = 'calculation_contract'::"text") AND (("calculation_contract_ref" ->> 'schema'::"text") = 'lca.calculation-contract.v1'::"text") AND (("calculation_contract_ref" ->> 'sha256'::"text") ~ '^[0-9a-f]{64}$'::"text"))),
    CONSTRAINT "study_model_preparations_check" CHECK ((("model_ref" IS NULL) = ("input_artifact_id" IS NULL))),
    CONSTRAINT "study_model_preparations_check1" CHECK ((("model_ref" IS NOT NULL) OR ("input_hash" IS NULL))),
    CONSTRAINT "study_model_preparations_check2" CHECK (COALESCE((((("source" ->> 'type'::"text") = 'modelSourceSnapshot'::"text") AND ("source_snapshot_id" IS NOT NULL) AND ("source_scenario_id" IS NULL) AND (("source" ->> 'snapshotId'::"text") = ("source_snapshot_id")::"text")) OR ((("source" ->> 'type'::"text") = 'scenarioRevision'::"text") AND ("source_scenario_id" IS NOT NULL) AND ("source_snapshot_id" IS NULL) AND ("source_study_revision_id" IS NOT NULL) AND (("source" ->> 'scenarioRevisionId'::"text") = ("source_scenario_id")::"text"))), false)),
    CONSTRAINT "study_model_preparations_input_hash_check" CHECK (("input_hash" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "study_model_preparations_method_refs_check" CHECK (("jsonb_typeof"("method_refs") = 'array'::"text")),
    CONSTRAINT "study_model_preparations_method_refs_check1" CHECK ("private"."study_method_refs_valid"("method_refs"))
);

ALTER TABLE ONLY "private"."study_model_preparations" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_model_preparations" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_model_preparations"
    ADD CONSTRAINT "study_model_preparations_job_id_key" UNIQUE ("job_id");

ALTER TABLE ONLY "private"."study_model_preparations"
    ADD CONSTRAINT "study_model_preparations_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."study_model_preparations"
    ADD CONSTRAINT "study_model_preparations_study_id_id_key" UNIQUE ("study_id", "id");

ALTER TABLE ONLY "private"."study_model_preparations"
    ADD CONSTRAINT "study_model_preparations_job_id_fkey" FOREIGN KEY ("job_id") REFERENCES "private"."worker_jobs"("id");

ALTER TABLE ONLY "private"."study_model_preparations"
    ADD CONSTRAINT "study_model_preparations_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "private"."study_profiles"("profile_id");

ALTER TABLE ONLY "private"."study_model_preparations"
    ADD CONSTRAINT "study_model_preparations_study_id_fkey" FOREIGN KEY ("study_id") REFERENCES "private"."studies"("id");

ALTER TABLE ONLY "private"."study_model_preparations"
    ADD CONSTRAINT "study_model_preparations_study_id_input_artifact_id_fkey" FOREIGN KEY ("study_id", "input_artifact_id") REFERENCES "private"."study_artifacts"("study_id", "id");

ALTER TABLE ONLY "private"."study_model_preparations"
    ADD CONSTRAINT "study_model_preparations_study_id_source_parent_scenario_i_fkey" FOREIGN KEY ("study_id", "source_parent_scenario_id") REFERENCES "private"."study_scenarios"("study_id", "id");

ALTER TABLE ONLY "private"."study_model_preparations"
    ADD CONSTRAINT "study_model_preparations_study_id_source_scenario_id_fkey" FOREIGN KEY ("study_id", "source_scenario_id") REFERENCES "private"."study_scenarios"("study_id", "id");

ALTER TABLE ONLY "private"."study_model_preparations"
    ADD CONSTRAINT "study_model_preparations_study_id_source_snapshot_id_fkey" FOREIGN KEY ("study_id", "source_snapshot_id") REFERENCES "private"."study_source_snapshots"("study_id", "id");

ALTER TABLE ONLY "private"."study_model_preparations"
    ADD CONSTRAINT "study_model_preparations_study_id_source_study_revision_id_fkey" FOREIGN KEY ("study_id", "source_study_revision_id") REFERENCES "private"."study_revisions"("study_id", "id");

ALTER TABLE "private"."study_model_preparations" ENABLE ROW LEVEL SECURITY;
