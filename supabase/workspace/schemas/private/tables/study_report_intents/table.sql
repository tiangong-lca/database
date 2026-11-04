CREATE TABLE IF NOT EXISTS "private"."study_report_intents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "study_id" "uuid" NOT NULL,
    "actor_id" "uuid" NOT NULL,
    "client_id" "text",
    "operation" "text" NOT NULL,
    "request" "jsonb" NOT NULL,
    "report_id" "uuid" NOT NULL,
    "content_artifact_id" "uuid",
    "export_id" "uuid",
    "projection_artifact_id" "uuid",
    "resources_artifact_id" "uuid",
    "bundle_artifact_id" "uuid",
    "grant_epoch" bigint NOT NULL,
    "config_revision" bigint NOT NULL,
    "report_snapshot" "jsonb",
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "expires_at" timestamp with time zone DEFAULT ("clock_timestamp"() + '00:02:00'::interval) NOT NULL,
    "response" "jsonb",
    "family" "text" DEFAULT 'legacy'::"text" NOT NULL,
    CONSTRAINT "study_report_intents_family_check" CHECK (("family" = ANY (ARRAY['legacy'::"text", 'advanced'::"text", 'method'::"text"]))),
    CONSTRAINT "study_report_intents_operation_check" CHECK (("operation" = ANY (ARRAY['report.create'::"text", 'report.save'::"text", 'report.freeze'::"text", 'export.request'::"text"])))
);

ALTER TABLE ONLY "private"."study_report_intents" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_report_intents" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_report_intents"
    ADD CONSTRAINT "study_report_intents_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."study_report_intents"
    ADD CONSTRAINT "study_report_intents_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "private"."study_report_intents"
    ADD CONSTRAINT "study_report_intents_study_id_fkey" FOREIGN KEY ("study_id") REFERENCES "private"."studies"("id");

ALTER TABLE "private"."study_report_intents" ENABLE ROW LEVEL SECURITY;
