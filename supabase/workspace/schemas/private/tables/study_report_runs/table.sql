CREATE TABLE IF NOT EXISTS "private"."study_report_runs" (
    "study_id" "uuid" NOT NULL,
    "report_id" "uuid" NOT NULL,
    "ordinal" integer NOT NULL,
    "run_id" "uuid" NOT NULL,
    CONSTRAINT "study_report_runs_ordinal_check" CHECK ((("ordinal" >= 1) AND ("ordinal" <= 2)))
);

ALTER TABLE ONLY "private"."study_report_runs" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_report_runs" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_report_runs"
    ADD CONSTRAINT "study_report_runs_pkey" PRIMARY KEY ("report_id", "ordinal");

ALTER TABLE ONLY "private"."study_report_runs"
    ADD CONSTRAINT "study_report_runs_report_id_run_id_key" UNIQUE ("report_id", "run_id");

ALTER TABLE ONLY "private"."study_report_runs"
    ADD CONSTRAINT "study_report_runs_study_id_report_id_fkey" FOREIGN KEY ("study_id", "report_id") REFERENCES "private"."study_report_revisions"("study_id", "id");

ALTER TABLE ONLY "private"."study_report_runs"
    ADD CONSTRAINT "study_report_runs_study_id_run_id_fkey" FOREIGN KEY ("study_id", "run_id") REFERENCES "private"."study_runs"("study_id", "id");

ALTER TABLE "private"."study_report_runs" ENABLE ROW LEVEL SECURITY;
