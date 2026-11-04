CREATE TABLE IF NOT EXISTS "private"."study_method_evidence" (
    "id" "uuid" NOT NULL,
    "study_id" "uuid" NOT NULL,
    "requirement_id" "text" NOT NULL,
    "declared_kind" "text" NOT NULL,
    "artifact_id" "uuid" NOT NULL,
    "recorded_by" "uuid" NOT NULL,
    "recorded_client_id" "text",
    "recorded_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "study_method_evidence_declared_kind_check" CHECK (("declared_kind" = ANY (ARRAY['sourceRecord'::"text", 'applicabilityRecord'::"text", 'professionalRecord'::"text"]))),
    CONSTRAINT "study_method_evidence_requirement_id_check" CHECK (("requirement_id" ~ '^PEF-(0[1-9]|1[0-9]|20)$'::"text"))
);

ALTER TABLE ONLY "private"."study_method_evidence" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_method_evidence" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_method_evidence"
    ADD CONSTRAINT "study_method_evidence_artifact_id_key" UNIQUE ("artifact_id");

ALTER TABLE ONLY "private"."study_method_evidence"
    ADD CONSTRAINT "study_method_evidence_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."study_method_evidence"
    ADD CONSTRAINT "study_method_evidence_study_id_id_key" UNIQUE ("study_id", "id");

ALTER TABLE ONLY "private"."study_method_evidence"
    ADD CONSTRAINT "study_method_evidence_recorded_by_fkey" FOREIGN KEY ("recorded_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "private"."study_method_evidence"
    ADD CONSTRAINT "study_method_evidence_study_id_artifact_id_fkey" FOREIGN KEY ("study_id", "artifact_id") REFERENCES "private"."study_artifacts"("study_id", "id");

ALTER TABLE ONLY "private"."study_method_evidence"
    ADD CONSTRAINT "study_method_evidence_study_id_fkey" FOREIGN KEY ("study_id") REFERENCES "private"."studies"("id");

ALTER TABLE "private"."study_method_evidence" ENABLE ROW LEVEL SECURITY;
