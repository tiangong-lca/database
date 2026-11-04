CREATE TABLE IF NOT EXISTS "private"."study_report_review_heads" (
    "report_id" "uuid" NOT NULL,
    "actor_id" "uuid" NOT NULL,
    "review_class" "text" NOT NULL,
    "review_id" "uuid" NOT NULL,
    CONSTRAINT "study_report_review_heads_review_class_check" CHECK (("review_class" = 'internal'::"text"))
);

ALTER TABLE ONLY "private"."study_report_review_heads" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_report_review_heads" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_report_review_heads"
    ADD CONSTRAINT "study_report_review_heads_pkey" PRIMARY KEY ("report_id", "actor_id", "review_class");

ALTER TABLE ONLY "private"."study_report_review_heads"
    ADD CONSTRAINT "study_report_review_heads_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "private"."study_report_review_heads"
    ADD CONSTRAINT "study_report_review_heads_report_id_fkey" FOREIGN KEY ("report_id") REFERENCES "private"."study_report_revisions"("id");

ALTER TABLE ONLY "private"."study_report_review_heads"
    ADD CONSTRAINT "study_report_review_heads_review_id_fkey" FOREIGN KEY ("review_id") REFERENCES "private"."study_report_reviews"("id");

ALTER TABLE "private"."study_report_review_heads" ENABLE ROW LEVEL SECURITY;
