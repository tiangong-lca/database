CREATE TABLE IF NOT EXISTS "private"."study_source_snapshots" (
    "id" "uuid" NOT NULL,
    "study_id" "uuid" NOT NULL,
    "acquisition_id" "uuid" NOT NULL,
    "origin_ref" "jsonb" NOT NULL,
    "artifact_id" "uuid" NOT NULL,
    "license_ref" "text" NOT NULL,
    "issuer_id" "text" NOT NULL,
    "observed_at" timestamp with time zone NOT NULL,
    "source_authorization" "jsonb" NOT NULL,
    CONSTRAINT "study_source_snapshots_source_authorization_check" CHECK (("jsonb_typeof"("source_authorization") = 'object'::"text"))
);

ALTER TABLE ONLY "private"."study_source_snapshots" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_source_snapshots" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_source_snapshots"
    ADD CONSTRAINT "study_source_snapshots_acquisition_id_key" UNIQUE ("acquisition_id");

ALTER TABLE ONLY "private"."study_source_snapshots"
    ADD CONSTRAINT "study_source_snapshots_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."study_source_snapshots"
    ADD CONSTRAINT "study_source_snapshots_study_id_id_key" UNIQUE ("study_id", "id");

ALTER TABLE ONLY "private"."study_source_snapshots"
    ADD CONSTRAINT "study_source_snapshots_study_id_acquisition_id_fkey" FOREIGN KEY ("study_id", "acquisition_id") REFERENCES "private"."study_source_acquisitions"("study_id", "id");

ALTER TABLE ONLY "private"."study_source_snapshots"
    ADD CONSTRAINT "study_source_snapshots_study_id_artifact_id_fkey" FOREIGN KEY ("study_id", "artifact_id") REFERENCES "private"."study_artifacts"("study_id", "id");

ALTER TABLE ONLY "private"."study_source_snapshots"
    ADD CONSTRAINT "study_source_snapshots_study_id_fkey" FOREIGN KEY ("study_id") REFERENCES "private"."studies"("id");

ALTER TABLE "private"."study_source_snapshots" ENABLE ROW LEVEL SECURITY;
