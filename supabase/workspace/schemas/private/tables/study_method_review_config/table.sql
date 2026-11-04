CREATE TABLE IF NOT EXISTS "private"."study_method_review_config" (
    "singleton" boolean DEFAULT true NOT NULL,
    "revision" bigint DEFAULT 1 NOT NULL,
    "enabled" boolean DEFAULT false NOT NULL,
    "export_enabled" boolean DEFAULT false NOT NULL,
    "export_profile" "jsonb",
    "qualification_evidence_ref" "text",
    CONSTRAINT "study_method_review_config_check" CHECK (((NOT "export_enabled") OR ("enabled" AND ("export_profile" IS NOT NULL)))),
    CONSTRAINT "study_method_review_config_check1" CHECK (((NOT ("enabled" OR "export_enabled")) OR (("qualification_evidence_ref" IS NOT NULL) AND COALESCE("private"."study_method_text"("to_jsonb"("qualification_evidence_ref"), 512), false)))),
    CONSTRAINT "study_method_review_config_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "study_method_review_config_singleton_check" CHECK ("singleton")
);

ALTER TABLE ONLY "private"."study_method_review_config" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_method_review_config" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_method_review_config"
    ADD CONSTRAINT "study_method_review_config_pkey" PRIMARY KEY ("singleton");

ALTER TABLE "private"."study_method_review_config" ENABLE ROW LEVEL SECURITY;
