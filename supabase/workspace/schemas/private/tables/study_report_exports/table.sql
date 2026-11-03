CREATE TABLE IF NOT EXISTS "private"."study_report_exports" (
    "id" "uuid" NOT NULL,
    "study_id" "uuid" NOT NULL,
    "report_id" "uuid" NOT NULL,
    "actor_id" "uuid" NOT NULL,
    "client_id" "text",
    "grant_epoch" bigint NOT NULL,
    "record" "jsonb" NOT NULL,
    "manifest" "jsonb" NOT NULL,
    "projection_artifact_id" "uuid" NOT NULL,
    "resources_artifact_id" "uuid" NOT NULL,
    "bundle_artifact_id" "uuid" NOT NULL,
    CONSTRAINT "study_report_exports_check" CHECK ((("record" ->> 'exportId'::"text") = ("id")::"text")),
    CONSTRAINT "study_report_exports_check1" CHECK ((("record" ->> 'studyId'::"text") = ("study_id")::"text")),
    CONSTRAINT "study_report_exports_check2" CHECK ((("record" ->> 'reportRevisionId'::"text") = ("report_id")::"text")),
    CONSTRAINT "study_report_exports_check3" CHECK ((("record" ->> 'actorId'::"text") = ("actor_id")::"text")),
    CONSTRAINT "study_report_exports_check4" CHECK (((("record" ->> 'grantEpoch'::"text"))::bigint = "grant_epoch"))
);

ALTER TABLE ONLY "private"."study_report_exports" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_report_exports" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_report_exports"
    ADD CONSTRAINT "study_report_exports_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."study_report_exports"
    ADD CONSTRAINT "study_report_exports_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "private"."study_report_exports"
    ADD CONSTRAINT "study_report_exports_study_id_bundle_artifact_id_fkey" FOREIGN KEY ("study_id", "bundle_artifact_id") REFERENCES "private"."study_artifacts"("study_id", "id");

ALTER TABLE ONLY "private"."study_report_exports"
    ADD CONSTRAINT "study_report_exports_study_id_fkey" FOREIGN KEY ("study_id") REFERENCES "private"."studies"("id");

ALTER TABLE ONLY "private"."study_report_exports"
    ADD CONSTRAINT "study_report_exports_study_id_projection_artifact_id_fkey" FOREIGN KEY ("study_id", "projection_artifact_id") REFERENCES "private"."study_artifacts"("study_id", "id");

ALTER TABLE ONLY "private"."study_report_exports"
    ADD CONSTRAINT "study_report_exports_study_id_report_id_fkey" FOREIGN KEY ("study_id", "report_id") REFERENCES "private"."study_report_revisions"("study_id", "id");

ALTER TABLE ONLY "private"."study_report_exports"
    ADD CONSTRAINT "study_report_exports_study_id_resources_artifact_id_fkey" FOREIGN KEY ("study_id", "resources_artifact_id") REFERENCES "private"."study_artifacts"("study_id", "id");

ALTER TABLE "private"."study_report_exports" ENABLE ROW LEVEL SECURITY;
