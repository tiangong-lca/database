CREATE TABLE IF NOT EXISTS "private"."final_result_query_sources" (
    "artifact_id" "uuid" NOT NULL,
    "row_ordinal" integer NOT NULL,
    "source_id" "uuid" NOT NULL,
    "source_version" "text" NOT NULL,
    CONSTRAINT "final_result_query_sources_source_version_check" CHECK (("source_version" ~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$'::"text"))
);

ALTER TABLE "private"."final_result_query_sources" OWNER TO "postgres";

ALTER TABLE ONLY "private"."final_result_query_sources"
    ADD CONSTRAINT "final_result_query_sources_pkey" PRIMARY KEY ("artifact_id", "row_ordinal", "source_id", "source_version");

ALTER TABLE ONLY "private"."final_result_query_sources"
    ADD CONSTRAINT "final_result_query_sources_artifact_id_row_ordinal_fkey" FOREIGN KEY ("artifact_id", "row_ordinal") REFERENCES "private"."final_result_query_rows"("artifact_id", "row_ordinal");

ALTER TABLE "private"."final_result_query_sources" ENABLE ROW LEVEL SECURITY;
