CREATE TABLE IF NOT EXISTS "private"."study_revisions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "study_id" "uuid" NOT NULL,
    "parent_revision_id" "uuid",
    "revision" bigint DEFAULT 1 NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "content_hash" "text" NOT NULL,
    "definition" "jsonb" NOT NULL,
    "preparation_id" "uuid" NOT NULL,
    "model_ref" "jsonb" NOT NULL,
    "validation" "text" DEFAULT 'not_checked'::"text" NOT NULL,
    "validation_evidence" "jsonb",
    CONSTRAINT "study_revisions_check" CHECK (("parent_revision_id" IS DISTINCT FROM "id")),
    CONSTRAINT "study_revisions_check1" CHECK ((("status" = 'frozen'::"text") = ("validation" = 'passed'::"text"))),
    CONSTRAINT "study_revisions_check2" CHECK ((("validation" = 'passed'::"text") = ("validation_evidence" IS NOT NULL))),
    CONSTRAINT "study_revisions_content_hash_check" CHECK (("content_hash" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "study_revisions_definition_check" CHECK ("private"."study_definition_valid"("definition")),
    CONSTRAINT "study_revisions_revision_check" CHECK ((("revision" >= 1) AND ("revision" <= '9007199254740991'::bigint))),
    CONSTRAINT "study_revisions_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'frozen'::"text"]))),
    CONSTRAINT "study_revisions_validation_check" CHECK (("validation" = ANY (ARRAY['not_checked'::"text", 'passed'::"text"])))
);

ALTER TABLE ONLY "private"."study_revisions" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_revisions" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_revisions"
    ADD CONSTRAINT "study_revisions_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."study_revisions"
    ADD CONSTRAINT "study_revisions_study_id_id_key" UNIQUE ("study_id", "id");

ALTER TABLE ONLY "private"."study_revisions"
    ADD CONSTRAINT "study_revisions_study_id_fkey" FOREIGN KEY ("study_id") REFERENCES "private"."studies"("id");

ALTER TABLE ONLY "private"."study_revisions"
    ADD CONSTRAINT "study_revisions_study_id_parent_revision_id_fkey" FOREIGN KEY ("study_id", "parent_revision_id") REFERENCES "private"."study_revisions"("study_id", "id");

ALTER TABLE ONLY "private"."study_revisions"
    ADD CONSTRAINT "study_revisions_study_id_preparation_id_fkey" FOREIGN KEY ("study_id", "preparation_id") REFERENCES "private"."study_model_preparations"("study_id", "id");

ALTER TABLE "private"."study_revisions" ENABLE ROW LEVEL SECURITY;
