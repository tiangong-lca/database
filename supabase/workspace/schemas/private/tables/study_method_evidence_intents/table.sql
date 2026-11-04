CREATE TABLE IF NOT EXISTS "private"."study_method_evidence_intents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "study_id" "uuid" NOT NULL,
    "actor_id" "uuid" NOT NULL,
    "client_id" "text",
    "request" "jsonb" NOT NULL,
    "evidence_id" "uuid" NOT NULL,
    "artifact_id" "uuid" NOT NULL,
    "grant_epoch" bigint NOT NULL,
    "config_revision" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "expires_at" timestamp with time zone DEFAULT ("clock_timestamp"() + '00:02:00'::interval) NOT NULL,
    "response" "jsonb"
);

ALTER TABLE ONLY "private"."study_method_evidence_intents" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_method_evidence_intents" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_method_evidence_intents"
    ADD CONSTRAINT "study_method_evidence_intents_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."study_method_evidence_intents"
    ADD CONSTRAINT "study_method_evidence_intents_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "private"."study_method_evidence_intents"
    ADD CONSTRAINT "study_method_evidence_intents_study_id_fkey" FOREIGN KEY ("study_id") REFERENCES "private"."studies"("id");

ALTER TABLE "private"."study_method_evidence_intents" ENABLE ROW LEVEL SECURITY;
