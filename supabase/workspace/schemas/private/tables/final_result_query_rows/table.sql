CREATE TABLE IF NOT EXISTS "private"."final_result_query_rows" (
    "artifact_id" "uuid" NOT NULL,
    "row_ordinal" integer NOT NULL,
    "result_id" "uuid" NOT NULL,
    "result_version" "text" NOT NULL,
    "content_hash" "text" NOT NULL,
    "relation_kind" "text" NOT NULL,
    "row_data" "jsonb" NOT NULL,
    "row_hash" "text" NOT NULL,
    "canonical_content_hash" "text" NOT NULL,
    CONSTRAINT "final_result_query_rows_canonical_content_hash_check" CHECK (("canonical_content_hash" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "final_result_query_rows_content_hash_check" CHECK (("content_hash" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "final_result_query_rows_relation_kind_check" CHECK (("relation_kind" = ANY (ARRAY['direct'::"text", 'derived'::"text"]))),
    CONSTRAINT "final_result_query_rows_row_hash_check" CHECK (("row_hash" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "final_result_query_rows_row_ordinal_check" CHECK ((("row_ordinal" >= 0) AND ("row_ordinal" <= 1999999)))
);

ALTER TABLE "private"."final_result_query_rows" OWNER TO "postgres";

ALTER TABLE ONLY "private"."final_result_query_rows"
    ADD CONSTRAINT "final_result_query_rows_artifact_id_result_id_result_versio_key" UNIQUE ("artifact_id", "result_id", "result_version");

ALTER TABLE ONLY "private"."final_result_query_rows"
    ADD CONSTRAINT "final_result_query_rows_pkey" PRIMARY KEY ("artifact_id", "row_ordinal");

ALTER TABLE ONLY "private"."final_result_query_rows"
    ADD CONSTRAINT "final_result_query_rows_artifact_id_fkey" FOREIGN KEY ("artifact_id") REFERENCES "private"."final_result_query_artifacts"("id");

ALTER TABLE "private"."final_result_query_rows" ENABLE ROW LEVEL SECURITY;
