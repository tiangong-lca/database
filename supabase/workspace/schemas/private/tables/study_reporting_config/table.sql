CREATE TABLE IF NOT EXISTS "private"."study_reporting_config" (
    "singleton" boolean DEFAULT true NOT NULL,
    "revision" bigint DEFAULT 1 NOT NULL,
    "analysis_enabled" boolean DEFAULT false NOT NULL,
    "report_enabled" boolean DEFAULT false NOT NULL,
    "export_enabled" boolean DEFAULT false NOT NULL,
    "qualification_evidence_ref" "text",
    "export_profile" "jsonb",
    CONSTRAINT "study_reporting_config_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "study_reporting_config_singleton_check" CHECK ("singleton")
);

ALTER TABLE ONLY "private"."study_reporting_config" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_reporting_config" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_reporting_config"
    ADD CONSTRAINT "study_reporting_config_pkey" PRIMARY KEY ("singleton");

ALTER TABLE "private"."study_reporting_config" ENABLE ROW LEVEL SECURITY;
