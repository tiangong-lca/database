CREATE TABLE IF NOT EXISTS "private"."study_report_revisions" (
    "id" "uuid" NOT NULL,
    "study_id" "uuid" NOT NULL,
    "parent_report_id" "uuid",
    "author_id" "uuid" NOT NULL,
    "revision" bigint DEFAULT 1 NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "content_hash" "text" NOT NULL,
    "content_artifact_id" "uuid" NOT NULL,
    "template_id" "text" NOT NULL,
    "run_ids" "jsonb" NOT NULL,
    "analysis_ids" "jsonb" NOT NULL,
    "facts_refs" "jsonb" NOT NULL,
    "validity_snapshot" "jsonb" NOT NULL,
    "validation_evidence" "jsonb" NOT NULL,
    "method_assessment_ids" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    CONSTRAINT "study_method_report_selection_check" CHECK (
CASE
    WHEN ("template_id" = 'lca.study-method-report.v1'::"text") THEN ("private"."study_report_ids"("run_ids", 1, 1) AND ("analysis_ids" = '[]'::"jsonb") AND "private"."study_report_ids"("method_assessment_ids", 1, 1))
    ELSE ("method_assessment_ids" = '[]'::"jsonb")
END),
    CONSTRAINT "study_report_revisions_check" CHECK (("parent_report_id" IS DISTINCT FROM "id")),
    CONSTRAINT "study_report_revisions_content_hash_check" CHECK (("content_hash" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "study_report_revisions_revision_check" CHECK ((("revision" >= 1) AND ("revision" <= '9007199254740991'::bigint))),
    CONSTRAINT "study_report_revisions_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'frozen'::"text"]))),
    CONSTRAINT "study_report_revisions_template_id_check" CHECK (("template_id" = ANY (ARRAY['lca.study-report.v1'::"text", 'lca.study-report.v2'::"text", 'lca.study-method-report.v1'::"text"])))
);

ALTER TABLE ONLY "private"."study_report_revisions" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_report_revisions" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_report_revisions"
    ADD CONSTRAINT "study_report_revisions_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."study_report_revisions"
    ADD CONSTRAINT "study_report_revisions_study_id_id_key" UNIQUE ("study_id", "id");

ALTER TABLE ONLY "private"."study_report_revisions"
    ADD CONSTRAINT "study_report_revisions_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "private"."study_report_revisions"
    ADD CONSTRAINT "study_report_revisions_study_id_content_artifact_id_fkey" FOREIGN KEY ("study_id", "content_artifact_id") REFERENCES "private"."study_artifacts"("study_id", "id");

ALTER TABLE ONLY "private"."study_report_revisions"
    ADD CONSTRAINT "study_report_revisions_study_id_fkey" FOREIGN KEY ("study_id") REFERENCES "private"."studies"("id");

ALTER TABLE ONLY "private"."study_report_revisions"
    ADD CONSTRAINT "study_report_revisions_study_id_parent_report_id_fkey" FOREIGN KEY ("study_id", "parent_report_id") REFERENCES "private"."study_report_revisions"("study_id", "id");

ALTER TABLE "private"."study_report_revisions" ENABLE ROW LEVEL SECURITY;
