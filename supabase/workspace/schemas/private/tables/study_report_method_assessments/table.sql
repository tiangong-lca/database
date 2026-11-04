CREATE TABLE IF NOT EXISTS "private"."study_report_method_assessments" (
    "study_id" "uuid" NOT NULL,
    "report_id" "uuid" NOT NULL,
    "assessment_id" "uuid" NOT NULL
);

ALTER TABLE ONLY "private"."study_report_method_assessments" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_report_method_assessments" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_report_method_assessments"
    ADD CONSTRAINT "study_report_method_assessments_pkey" PRIMARY KEY ("report_id");

ALTER TABLE ONLY "private"."study_report_method_assessments"
    ADD CONSTRAINT "study_report_method_assessments_study_id_assessment_id_fkey" FOREIGN KEY ("study_id", "assessment_id") REFERENCES "private"."study_method_assessments"("study_id", "id");

ALTER TABLE ONLY "private"."study_report_method_assessments"
    ADD CONSTRAINT "study_report_method_assessments_study_id_report_id_fkey" FOREIGN KEY ("study_id", "report_id") REFERENCES "private"."study_report_revisions"("study_id", "id");

ALTER TABLE "private"."study_report_method_assessments" ENABLE ROW LEVEL SECURITY;
