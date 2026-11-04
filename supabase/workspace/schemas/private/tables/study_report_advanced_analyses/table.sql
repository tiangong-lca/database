CREATE TABLE IF NOT EXISTS "private"."study_report_advanced_analyses" (
    "study_id" "uuid" NOT NULL,
    "report_id" "uuid" NOT NULL,
    "ordinal" integer NOT NULL,
    "analysis_id" "uuid" NOT NULL,
    CONSTRAINT "study_report_advanced_analyses_ordinal_check" CHECK ((("ordinal" >= 1) AND ("ordinal" <= 2)))
);

ALTER TABLE ONLY "private"."study_report_advanced_analyses" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_report_advanced_analyses" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_report_advanced_analyses"
    ADD CONSTRAINT "study_report_advanced_analyses_pkey" PRIMARY KEY ("report_id", "ordinal");

ALTER TABLE ONLY "private"."study_report_advanced_analyses"
    ADD CONSTRAINT "study_report_advanced_analyses_report_id_analysis_id_key" UNIQUE ("report_id", "analysis_id");

ALTER TABLE ONLY "private"."study_report_advanced_analyses"
    ADD CONSTRAINT "study_report_advanced_analyses_study_id_analysis_id_fkey" FOREIGN KEY ("study_id", "analysis_id") REFERENCES "private"."study_advanced_analyses"("study_id", "id");

ALTER TABLE ONLY "private"."study_report_advanced_analyses"
    ADD CONSTRAINT "study_report_advanced_analyses_study_id_report_id_fkey" FOREIGN KEY ("study_id", "report_id") REFERENCES "private"."study_report_revisions"("study_id", "id");

ALTER TABLE "private"."study_report_advanced_analyses" ENABLE ROW LEVEL SECURITY;
