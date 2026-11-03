CREATE TABLE IF NOT EXISTS "private"."study_report_finalizations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "study_id" "uuid" NOT NULL,
    "report_id" "uuid" NOT NULL,
    "report_hash" "text" NOT NULL,
    "actor_id" "uuid" NOT NULL,
    "profile_id" "text" NOT NULL,
    "expected_review_state_hash" "text" NOT NULL,
    "accepted_review_ids" "jsonb" NOT NULL,
    "finalized_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "study_report_finalizations_expected_review_state_hash_check" CHECK (("expected_review_state_hash" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "study_report_finalizations_profile_id_check" CHECK (("profile_id" = ANY (ARRAY['lca.study-report-unreviewed.v1'::"text", 'lca.study-report-internal-review.v1'::"text"])))
);

ALTER TABLE ONLY "private"."study_report_finalizations" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_report_finalizations" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_report_finalizations"
    ADD CONSTRAINT "study_report_finalizations_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."study_report_finalizations"
    ADD CONSTRAINT "study_report_finalizations_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "private"."study_report_finalizations"
    ADD CONSTRAINT "study_report_finalizations_study_id_report_id_fkey" FOREIGN KEY ("study_id", "report_id") REFERENCES "private"."study_report_revisions"("study_id", "id");

ALTER TABLE "private"."study_report_finalizations" ENABLE ROW LEVEL SECURITY;
