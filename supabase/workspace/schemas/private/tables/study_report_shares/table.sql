CREATE TABLE IF NOT EXISTS "private"."study_report_shares" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "study_id" "uuid" NOT NULL,
    "report_id" "uuid" NOT NULL,
    "report_hash" "text" NOT NULL,
    "export_id" "uuid" NOT NULL,
    "finalization_id" "uuid" NOT NULL,
    "issuer_id" "uuid" NOT NULL,
    "issuer_client_id" "text",
    "recipient_id" "uuid" NOT NULL,
    "grant_epoch" bigint NOT NULL,
    "disclosure_context_hash" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "revoked_at" timestamp with time zone,
    "revocation_reason" "text",
    CONSTRAINT "study_report_shares_check" CHECK (("expires_at" > "created_at"))
);

ALTER TABLE ONLY "private"."study_report_shares" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_report_shares" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_report_shares"
    ADD CONSTRAINT "study_report_shares_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."study_report_shares"
    ADD CONSTRAINT "study_report_shares_export_id_fkey" FOREIGN KEY ("export_id") REFERENCES "private"."study_review_exports"("id");

ALTER TABLE ONLY "private"."study_report_shares"
    ADD CONSTRAINT "study_report_shares_finalization_id_fkey" FOREIGN KEY ("finalization_id") REFERENCES "private"."study_report_finalizations"("id");

ALTER TABLE ONLY "private"."study_report_shares"
    ADD CONSTRAINT "study_report_shares_issuer_id_fkey" FOREIGN KEY ("issuer_id") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "private"."study_report_shares"
    ADD CONSTRAINT "study_report_shares_recipient_id_fkey" FOREIGN KEY ("recipient_id") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "private"."study_report_shares"
    ADD CONSTRAINT "study_report_shares_study_id_report_id_fkey" FOREIGN KEY ("study_id", "report_id") REFERENCES "private"."study_report_revisions"("study_id", "id");

ALTER TABLE "private"."study_report_shares" ENABLE ROW LEVEL SECURITY;
