CREATE TABLE IF NOT EXISTS "private"."study_scenarios" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "scenario_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "study_id" "uuid" NOT NULL,
    "study_revision_id" "uuid" NOT NULL,
    "parent_scenario_id" "uuid",
    "revision" bigint DEFAULT 1 NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "content_hash" "text" NOT NULL,
    "overrides" "jsonb" NOT NULL,
    "preparation_id" "uuid",
    "effective_model_ref" "jsonb",
    CONSTRAINT "study_scenarios_check" CHECK (("parent_scenario_id" IS DISTINCT FROM "id")),
    CONSTRAINT "study_scenarios_check1" CHECK ((("status" = 'frozen'::"text") = (("preparation_id" IS NOT NULL) AND ("effective_model_ref" IS NOT NULL)))),
    CONSTRAINT "study_scenarios_content_hash_check" CHECK (("content_hash" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "study_scenarios_overrides_check" CHECK ((("jsonb_typeof"("overrides") = 'array'::"text") AND ("jsonb_array_length"("overrides") <= 256))),
    CONSTRAINT "study_scenarios_overrides_check1" CHECK ("private"."study_overrides_valid"("overrides")),
    CONSTRAINT "study_scenarios_revision_check" CHECK ((("revision" >= 1) AND ("revision" <= '9007199254740991'::bigint))),
    CONSTRAINT "study_scenarios_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'frozen'::"text"])))
);

ALTER TABLE ONLY "private"."study_scenarios" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_scenarios" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_scenarios"
    ADD CONSTRAINT "study_scenarios_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."study_scenarios"
    ADD CONSTRAINT "study_scenarios_study_id_id_key" UNIQUE ("study_id", "id");

ALTER TABLE ONLY "private"."study_scenarios"
    ADD CONSTRAINT "study_scenarios_study_id_fkey" FOREIGN KEY ("study_id") REFERENCES "private"."studies"("id");

ALTER TABLE ONLY "private"."study_scenarios"
    ADD CONSTRAINT "study_scenarios_study_id_parent_scenario_id_fkey" FOREIGN KEY ("study_id", "parent_scenario_id") REFERENCES "private"."study_scenarios"("study_id", "id");

ALTER TABLE ONLY "private"."study_scenarios"
    ADD CONSTRAINT "study_scenarios_study_id_preparation_id_fkey" FOREIGN KEY ("study_id", "preparation_id") REFERENCES "private"."study_model_preparations"("study_id", "id");

ALTER TABLE ONLY "private"."study_scenarios"
    ADD CONSTRAINT "study_scenarios_study_id_study_revision_id_fkey" FOREIGN KEY ("study_id", "study_revision_id") REFERENCES "private"."study_revisions"("study_id", "id");

ALTER TABLE "private"."study_scenarios" ENABLE ROW LEVEL SECURITY;
