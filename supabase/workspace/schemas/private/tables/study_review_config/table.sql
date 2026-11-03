CREATE TABLE IF NOT EXISTS "private"."study_review_config" (
    "singleton" boolean DEFAULT true NOT NULL,
    "revision" bigint DEFAULT 1 NOT NULL,
    "enabled" boolean DEFAULT false NOT NULL,
    "qualification_evidence_ref" "text",
    CONSTRAINT "study_review_config_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "study_review_config_singleton_check" CHECK ("singleton")
);

ALTER TABLE ONLY "private"."study_review_config" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_review_config" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_review_config"
    ADD CONSTRAINT "study_review_config_pkey" PRIMARY KEY ("singleton");

ALTER TABLE "private"."study_review_config" ENABLE ROW LEVEL SECURITY;
