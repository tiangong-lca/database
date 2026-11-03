CREATE TABLE IF NOT EXISTS "private"."study_review_intents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "study_id" "uuid" NOT NULL,
    "report_id" "uuid" NOT NULL,
    "actor_id" "uuid" NOT NULL,
    "client_id" "text",
    "operation" "text" NOT NULL,
    "request" "jsonb" NOT NULL,
    "share_id" "uuid",
    "finalization_id" "uuid",
    "grant_epoch" bigint NOT NULL,
    "config_revision" bigint NOT NULL,
    "reporting_config_revision" bigint NOT NULL,
    "review_state_hash" "text" NOT NULL,
    "export_id" "uuid",
    "projection_artifact_id" "uuid",
    "resources_artifact_id" "uuid",
    "bundle_artifact_id" "uuid",
    "disclosure_context_hash" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "expires_at" timestamp with time zone DEFAULT ("clock_timestamp"() + '00:02:00'::interval) NOT NULL,
    "response" "jsonb",
    CONSTRAINT "study_review_intents_operation_check" CHECK (("operation" = ANY (ARRAY['report.view'::"text", 'export.request'::"text", 'export.download'::"text", 'share.view'::"text", 'share.download'::"text"])))
);

ALTER TABLE ONLY "private"."study_review_intents" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_review_intents" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_review_intents"
    ADD CONSTRAINT "study_review_intents_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."study_review_intents"
    ADD CONSTRAINT "study_review_intents_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "private"."study_review_intents"
    ADD CONSTRAINT "study_review_intents_finalization_id_fkey" FOREIGN KEY ("finalization_id") REFERENCES "private"."study_report_finalizations"("id");

ALTER TABLE ONLY "private"."study_review_intents"
    ADD CONSTRAINT "study_review_intents_share_id_fkey" FOREIGN KEY ("share_id") REFERENCES "private"."study_report_shares"("id");

ALTER TABLE ONLY "private"."study_review_intents"
    ADD CONSTRAINT "study_review_intents_study_id_report_id_fkey" FOREIGN KEY ("study_id", "report_id") REFERENCES "private"."study_report_revisions"("study_id", "id");

ALTER TABLE "private"."study_review_intents" ENABLE ROW LEVEL SECURITY;
