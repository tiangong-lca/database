CREATE TABLE IF NOT EXISTS "private"."study_artifacts" (
    "id" "uuid" NOT NULL,
    "study_id" "uuid" NOT NULL,
    "ref" "jsonb" NOT NULL,
    "bucket" "text" NOT NULL,
    "object_path" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "study_artifacts_bucket_check" CHECK ((("length"("bucket") >= 1) AND ("length"("bucket") <= 128))),
    CONSTRAINT "study_artifacts_check" CHECK ((("ref" ->> 'id'::"text") = ("id")::"text")),
    CONSTRAINT "study_artifacts_object_path_check" CHECK ((("length"("object_path") >= 1) AND ("length"("object_path") <= 1024))),
    CONSTRAINT "study_artifacts_ref_check" CHECK (("jsonb_typeof"("ref") = 'object'::"text")),
    CONSTRAINT "study_artifacts_ref_check1" CHECK ((("ref" ->> 'digestScope'::"text") = 'artifact_bytes_sha256'::"text")),
    CONSTRAINT "study_artifacts_ref_check2" CHECK ((("ref" ->> 'contentHash'::"text") ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "study_artifacts_ref_check3" CHECK ((((("ref" ->> 'byteSize'::"text"))::bigint >= 1) AND ((("ref" ->> 'byteSize'::"text"))::bigint <= 4194304)))
);

ALTER TABLE ONLY "private"."study_artifacts" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_artifacts" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_artifacts"
    ADD CONSTRAINT "study_artifacts_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."study_artifacts"
    ADD CONSTRAINT "study_artifacts_study_id_id_key" UNIQUE ("study_id", "id");

ALTER TABLE ONLY "private"."study_artifacts"
    ADD CONSTRAINT "study_artifacts_study_id_fkey" FOREIGN KEY ("study_id") REFERENCES "private"."studies"("id");

ALTER TABLE "private"."study_artifacts" ENABLE ROW LEVEL SECURITY;
