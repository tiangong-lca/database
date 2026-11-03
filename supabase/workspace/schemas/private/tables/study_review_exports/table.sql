CREATE TABLE IF NOT EXISTS "private"."study_review_exports" (
    "id" "uuid" NOT NULL,
    "study_id" "uuid" NOT NULL,
    "report_id" "uuid" NOT NULL,
    "actor_id" "uuid" NOT NULL,
    "client_id" "text",
    "grant_epoch" bigint NOT NULL,
    "finalization_id" "uuid" NOT NULL,
    "record" "jsonb" NOT NULL,
    "manifest" "jsonb" NOT NULL,
    "projection_artifact_id" "uuid" NOT NULL,
    "resources_artifact_id" "uuid" NOT NULL,
    "bundle_artifact_id" "uuid" NOT NULL
);

ALTER TABLE ONLY "private"."study_review_exports" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_review_exports" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_review_exports"
    ADD CONSTRAINT "study_review_exports_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."study_review_exports"
    ADD CONSTRAINT "study_review_exports_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "private"."study_review_exports"
    ADD CONSTRAINT "study_review_exports_finalization_id_fkey" FOREIGN KEY ("finalization_id") REFERENCES "private"."study_report_finalizations"("id");

ALTER TABLE ONLY "private"."study_review_exports"
    ADD CONSTRAINT "study_review_exports_study_id_bundle_artifact_id_fkey" FOREIGN KEY ("study_id", "bundle_artifact_id") REFERENCES "private"."study_artifacts"("study_id", "id");

ALTER TABLE ONLY "private"."study_review_exports"
    ADD CONSTRAINT "study_review_exports_study_id_projection_artifact_id_fkey" FOREIGN KEY ("study_id", "projection_artifact_id") REFERENCES "private"."study_artifacts"("study_id", "id");

ALTER TABLE ONLY "private"."study_review_exports"
    ADD CONSTRAINT "study_review_exports_study_id_report_id_fkey" FOREIGN KEY ("study_id", "report_id") REFERENCES "private"."study_report_revisions"("study_id", "id");

ALTER TABLE ONLY "private"."study_review_exports"
    ADD CONSTRAINT "study_review_exports_study_id_resources_artifact_id_fkey" FOREIGN KEY ("study_id", "resources_artifact_id") REFERENCES "private"."study_artifacts"("study_id", "id");

ALTER TABLE "private"."study_review_exports" ENABLE ROW LEVEL SECURITY;
