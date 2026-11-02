CREATE TABLE IF NOT EXISTS "private"."study_validation_intents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "study_id" "uuid" NOT NULL,
    "revision_id" "uuid" NOT NULL,
    "actor_id" "uuid" NOT NULL,
    "client_id" "text",
    "binding" "jsonb" NOT NULL,
    "expires_at" timestamp with time zone DEFAULT ("clock_timestamp"() + '00:02:00'::interval) NOT NULL,
    "response" "jsonb",
    "consumed_at" timestamp with time zone
);

ALTER TABLE ONLY "private"."study_validation_intents" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_validation_intents" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_validation_intents"
    ADD CONSTRAINT "study_validation_intents_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."study_validation_intents"
    ADD CONSTRAINT "study_validation_intents_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "private"."study_validation_intents"
    ADD CONSTRAINT "study_validation_intents_study_id_fkey" FOREIGN KEY ("study_id") REFERENCES "private"."studies"("id");

ALTER TABLE ONLY "private"."study_validation_intents"
    ADD CONSTRAINT "study_validation_intents_study_id_revision_id_fkey" FOREIGN KEY ("study_id", "revision_id") REFERENCES "private"."study_revisions"("study_id", "id");

ALTER TABLE "private"."study_validation_intents" ENABLE ROW LEVEL SECURITY;
