CREATE TABLE IF NOT EXISTS "private"."study_report_comments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "study_id" "uuid" NOT NULL,
    "report_id" "uuid" NOT NULL,
    "report_hash" "text" NOT NULL,
    "actor_id" "uuid" NOT NULL,
    "client_id" "text",
    "body" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "study_report_comments_body_check" CHECK ((("length"("body") >= 1) AND ("length"("body") <= 4096)))
);

ALTER TABLE ONLY "private"."study_report_comments" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_report_comments" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_report_comments"
    ADD CONSTRAINT "study_report_comments_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."study_report_comments"
    ADD CONSTRAINT "study_report_comments_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "private"."study_report_comments"
    ADD CONSTRAINT "study_report_comments_study_id_report_id_fkey" FOREIGN KEY ("study_id", "report_id") REFERENCES "private"."study_report_revisions"("study_id", "id");

ALTER TABLE "private"."study_report_comments" ENABLE ROW LEVEL SECURITY;
