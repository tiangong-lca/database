CREATE TABLE IF NOT EXISTS "private"."study_method_config" (
    "singleton" boolean DEFAULT true NOT NULL,
    "revision" bigint DEFAULT 1 NOT NULL,
    "execution_enabled" boolean DEFAULT false NOT NULL,
    "report_enabled" boolean DEFAULT false NOT NULL,
    "max_evidence_refs" integer,
    "max_selected_factor_records" integer,
    "qualification_evidence_ref" "text",
    CONSTRAINT "study_method_config_check" CHECK (((NOT ("execution_enabled" OR "report_enabled")) OR (("max_evidence_refs" IS NOT NULL) AND ("max_selected_factor_records" IS NOT NULL) AND ("qualification_evidence_ref" IS NOT NULL) AND COALESCE("private"."study_method_text"("to_jsonb"("qualification_evidence_ref"), 2048), false)))),
    CONSTRAINT "study_method_config_max_evidence_refs_check" CHECK ((("max_evidence_refs" >= 0) AND ("max_evidence_refs" <= 128))),
    CONSTRAINT "study_method_config_max_selected_factor_records_check" CHECK ((("max_selected_factor_records" >= 1) AND ("max_selected_factor_records" <= 8192))),
    CONSTRAINT "study_method_config_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "study_method_config_singleton_check" CHECK ("singleton")
);

ALTER TABLE ONLY "private"."study_method_config" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_method_config" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_method_config"
    ADD CONSTRAINT "study_method_config_pkey" PRIMARY KEY ("singleton");

ALTER TABLE "private"."study_method_config" ENABLE ROW LEVEL SECURITY;
