CREATE TABLE IF NOT EXISTS "private"."study_advanced_parameter_intents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "study_id" "uuid" NOT NULL,
    "baseline_run_id" "uuid" NOT NULL,
    "source_snapshot_id" "uuid" NOT NULL,
    "actor_id" "uuid" NOT NULL,
    "client_id" "text",
    "expires_at" timestamp with time zone DEFAULT ("clock_timestamp"() + '00:02:00'::interval) NOT NULL
);

ALTER TABLE ONLY "private"."study_advanced_parameter_intents" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_advanced_parameter_intents" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_advanced_parameter_intents"
    ADD CONSTRAINT "study_advanced_parameter_intents_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."study_advanced_parameter_intents"
    ADD CONSTRAINT "study_advanced_parameter_inten_study_id_source_snapshot_id_fkey" FOREIGN KEY ("study_id", "source_snapshot_id") REFERENCES "private"."study_source_snapshots"("study_id", "id");

ALTER TABLE ONLY "private"."study_advanced_parameter_intents"
    ADD CONSTRAINT "study_advanced_parameter_intents_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "private"."study_advanced_parameter_intents"
    ADD CONSTRAINT "study_advanced_parameter_intents_study_id_baseline_run_id_fkey" FOREIGN KEY ("study_id", "baseline_run_id") REFERENCES "private"."study_runs"("study_id", "id");

ALTER TABLE "private"."study_advanced_parameter_intents" ENABLE ROW LEVEL SECURITY;
