CREATE TABLE IF NOT EXISTS "private"."study_runtime_config" (
    "singleton" boolean DEFAULT true NOT NULL,
    "revision" bigint DEFAULT 1 NOT NULL,
    "source_enabled" boolean DEFAULT false NOT NULL,
    "compute_enabled" boolean DEFAULT false NOT NULL,
    "disclosure_enabled" boolean DEFAULT false NOT NULL,
    "qualification_evidence_ref" "text",
    "method_refs" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "compiler_version" "text" DEFAULT 'study.compiler.v1'::"text" NOT NULL,
    CONSTRAINT "study_runtime_config_compiler_version_check" CHECK (("compiler_version" = 'study.compiler.v1'::"text")),
    CONSTRAINT "study_runtime_config_method_refs_check" CHECK (("jsonb_typeof"("method_refs") = 'array'::"text")),
    CONSTRAINT "study_runtime_config_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "study_runtime_config_singleton_check" CHECK ("singleton")
);

ALTER TABLE ONLY "private"."study_runtime_config" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_runtime_config" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_runtime_config"
    ADD CONSTRAINT "study_runtime_config_pkey" PRIMARY KEY ("singleton");

ALTER TABLE "private"."study_runtime_config" ENABLE ROW LEVEL SECURITY;
