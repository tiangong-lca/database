CREATE TABLE IF NOT EXISTS "private"."study_review_delegations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "study_id" "uuid" NOT NULL,
    "report_id" "uuid" NOT NULL,
    "report_hash" "text" NOT NULL,
    "actor_id" "uuid" NOT NULL,
    "client_id" "text" NOT NULL,
    "review_class" "text" NOT NULL,
    "decision" "text" NOT NULL,
    "predecessor_id" "uuid",
    "issued_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "revoked_at" timestamp with time zone,
    "consumed_review_id" "uuid",
    CONSTRAINT "study_review_delegations_check" CHECK ((("expires_at" > "issued_at") AND ("expires_at" <= ("issued_at" + '00:15:00'::interval)))),
    CONSTRAINT "study_review_delegations_decision_check" CHECK (("decision" = ANY (ARRAY['approve'::"text", 'reject'::"text", 'withdraw'::"text"]))),
    CONSTRAINT "study_review_delegations_review_class_check" CHECK (("review_class" = 'internal'::"text"))
);

ALTER TABLE ONLY "private"."study_review_delegations" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_review_delegations" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_review_delegations"
    ADD CONSTRAINT "study_review_delegations_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."study_review_delegations"
    ADD CONSTRAINT "study_review_delegations_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "private"."study_review_delegations"
    ADD CONSTRAINT "study_review_delegations_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "private"."oauth_client_registry"("client_id");

ALTER TABLE ONLY "private"."study_review_delegations"
    ADD CONSTRAINT "study_review_delegations_consumed_review_id_fkey" FOREIGN KEY ("consumed_review_id") REFERENCES "private"."study_report_reviews"("id");

ALTER TABLE ONLY "private"."study_review_delegations"
    ADD CONSTRAINT "study_review_delegations_predecessor_id_fkey" FOREIGN KEY ("predecessor_id") REFERENCES "private"."study_report_reviews"("id");

ALTER TABLE ONLY "private"."study_review_delegations"
    ADD CONSTRAINT "study_review_delegations_study_id_report_id_fkey" FOREIGN KEY ("study_id", "report_id") REFERENCES "private"."study_report_revisions"("study_id", "id");

ALTER TABLE "private"."study_review_delegations" ENABLE ROW LEVEL SECURITY;
