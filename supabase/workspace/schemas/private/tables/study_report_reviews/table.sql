CREATE TABLE IF NOT EXISTS "private"."study_report_reviews" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "study_id" "uuid" NOT NULL,
    "report_id" "uuid" NOT NULL,
    "report_hash" "text" NOT NULL,
    "actor_id" "uuid" NOT NULL,
    "client_id" "text",
    "review_class" "text" NOT NULL,
    "decision" "text" NOT NULL,
    "body" "text" NOT NULL,
    "predecessor_id" "uuid",
    "delegation_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "study_report_reviews_body_check" CHECK ((("length"("body") >= 1) AND ("length"("body") <= 4096))),
    CONSTRAINT "study_report_reviews_check" CHECK ((("client_id" IS NULL) = ("delegation_id" IS NULL))),
    CONSTRAINT "study_report_reviews_decision_check" CHECK (("decision" = ANY (ARRAY['approve'::"text", 'reject'::"text", 'withdraw'::"text"]))),
    CONSTRAINT "study_report_reviews_review_class_check" CHECK (("review_class" = 'internal'::"text"))
);

ALTER TABLE ONLY "private"."study_report_reviews" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_report_reviews" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_report_reviews"
    ADD CONSTRAINT "study_report_reviews_delegation_id_key" UNIQUE ("delegation_id");

ALTER TABLE ONLY "private"."study_report_reviews"
    ADD CONSTRAINT "study_report_reviews_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."study_report_reviews"
    ADD CONSTRAINT "study_report_reviews_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "private"."study_report_reviews"
    ADD CONSTRAINT "study_report_reviews_delegation_id_fkey" FOREIGN KEY ("delegation_id") REFERENCES "private"."study_review_delegations"("id");

ALTER TABLE ONLY "private"."study_report_reviews"
    ADD CONSTRAINT "study_report_reviews_predecessor_id_fkey" FOREIGN KEY ("predecessor_id") REFERENCES "private"."study_report_reviews"("id");

ALTER TABLE ONLY "private"."study_report_reviews"
    ADD CONSTRAINT "study_report_reviews_study_id_report_id_fkey" FOREIGN KEY ("study_id", "report_id") REFERENCES "private"."study_report_revisions"("study_id", "id");

ALTER TABLE "private"."study_report_reviews" ENABLE ROW LEVEL SECURITY;
