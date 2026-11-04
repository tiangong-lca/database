CREATE TABLE IF NOT EXISTS "private"."study_advanced_config" (
    "singleton" boolean DEFAULT true NOT NULL,
    "revision" bigint DEFAULT 1 NOT NULL,
    "sensitivity_enabled" boolean DEFAULT false NOT NULL,
    "uncertainty_enabled" boolean DEFAULT false NOT NULL,
    "report_enabled" boolean DEFAULT false NOT NULL,
    "max_parameters" integer,
    "max_samples" bigint,
    "qualification_evidence_ref" "text",
    CONSTRAINT "study_advanced_config_check" CHECK (((NOT ("sensitivity_enabled" OR "uncertainty_enabled" OR "report_enabled")) OR (("max_parameters" IS NOT NULL) AND ("max_samples" IS NOT NULL) AND "private"."study_text"("to_jsonb"("qualification_evidence_ref"), 2048)))),
    CONSTRAINT "study_advanced_config_max_parameters_check" CHECK (("max_parameters" > 0)),
    CONSTRAINT "study_advanced_config_max_samples_check" CHECK ((("max_samples" >= 2) AND ("max_samples" <= '4294967295'::bigint))),
    CONSTRAINT "study_advanced_config_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "study_advanced_config_singleton_check" CHECK ("singleton")
);

ALTER TABLE ONLY "private"."study_advanced_config" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_advanced_config" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_advanced_config"
    ADD CONSTRAINT "study_advanced_config_pkey" PRIMARY KEY ("singleton");

ALTER TABLE "private"."study_advanced_config" ENABLE ROW LEVEL SECURITY;
