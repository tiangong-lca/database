CREATE TABLE IF NOT EXISTS "private"."study_analysis_runs" (
    "study_id" "uuid" NOT NULL,
    "analysis_id" "uuid" NOT NULL,
    "ordinal" integer NOT NULL,
    "run_id" "uuid" NOT NULL,
    CONSTRAINT "study_analysis_runs_ordinal_check" CHECK ((("ordinal" >= 1) AND ("ordinal" <= 2)))
);

ALTER TABLE ONLY "private"."study_analysis_runs" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_analysis_runs" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_analysis_runs"
    ADD CONSTRAINT "study_analysis_runs_analysis_id_run_id_key" UNIQUE ("analysis_id", "run_id");

ALTER TABLE ONLY "private"."study_analysis_runs"
    ADD CONSTRAINT "study_analysis_runs_pkey" PRIMARY KEY ("analysis_id", "ordinal");

ALTER TABLE ONLY "private"."study_analysis_runs"
    ADD CONSTRAINT "study_analysis_runs_study_id_analysis_id_fkey" FOREIGN KEY ("study_id", "analysis_id") REFERENCES "private"."study_analyses"("study_id", "id");

ALTER TABLE ONLY "private"."study_analysis_runs"
    ADD CONSTRAINT "study_analysis_runs_study_id_run_id_fkey" FOREIGN KEY ("study_id", "run_id") REFERENCES "private"."study_runs"("study_id", "id");

ALTER TABLE "private"."study_analysis_runs" ENABLE ROW LEVEL SECURITY;
