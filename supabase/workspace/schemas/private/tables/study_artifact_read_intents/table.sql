CREATE TABLE IF NOT EXISTS "private"."study_artifact_read_intents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "study_id" "uuid" NOT NULL,
    "artifact_id" "uuid" NOT NULL,
    "artifact_ref" "jsonb" NOT NULL,
    "actor_id" "uuid" NOT NULL,
    "client_id" "text",
    "expires_at" timestamp with time zone DEFAULT ("clock_timestamp"() + '00:02:00'::interval) NOT NULL,
    "family" "text" DEFAULT 'legacy'::"text" NOT NULL,
    CONSTRAINT "study_artifact_read_intents_family_check" CHECK (("family" = ANY (ARRAY['legacy'::"text", 'advanced'::"text"])))
);

ALTER TABLE ONLY "private"."study_artifact_read_intents" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_artifact_read_intents" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_artifact_read_intents"
    ADD CONSTRAINT "study_artifact_read_intents_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."study_artifact_read_intents"
    ADD CONSTRAINT "study_artifact_read_intents_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "private"."study_artifact_read_intents"
    ADD CONSTRAINT "study_artifact_read_intents_study_id_artifact_id_fkey" FOREIGN KEY ("study_id", "artifact_id") REFERENCES "private"."study_artifacts"("study_id", "id");

ALTER TABLE ONLY "private"."study_artifact_read_intents"
    ADD CONSTRAINT "study_artifact_read_intents_study_id_fkey" FOREIGN KEY ("study_id") REFERENCES "private"."studies"("id");

ALTER TABLE "private"."study_artifact_read_intents" ENABLE ROW LEVEL SECURITY;
