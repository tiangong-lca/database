CREATE TABLE IF NOT EXISTS "private"."portal_catalog_search_rows_v1" (
    "dataset_kind" "text" NOT NULL,
    "id" "uuid" NOT NULL,
    "version" "text" NOT NULL,
    "state_code" integer NOT NULL,
    "modified_at" timestamp with time zone NOT NULL,
    "card" "jsonb" NOT NULL,
    "document" "text" NOT NULL,
    "projection_contract_version" smallint NOT NULL,
    CONSTRAINT "portal_catalog_search_rows_contract_version_v1_chk" CHECK (("projection_contract_version" = 1)),
    CONSTRAINT "portal_catalog_search_rows_v1_card_check" CHECK (("jsonb_typeof"("card") = 'object'::"text")),
    CONSTRAINT "portal_catalog_search_rows_v1_check" CHECK ((COALESCE(("card" ->> 'document'::"text"), ''::"text") = "document")),
    CONSTRAINT "portal_catalog_search_rows_v1_dataset_kind_check" CHECK (("dataset_kind" = 'flow'::"text")),
    CONSTRAINT "portal_catalog_search_rows_v1_state_code_check" CHECK (("state_code" = ANY (ARRAY[100, 200]))),
    CONSTRAINT "portal_catalog_search_rows_v1_version_check" CHECK (("version" ~ '^\d{2}\.\d{2}\.\d{3}$'::"text"))
);

ALTER TABLE ONLY "private"."portal_catalog_search_rows_v1" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."portal_catalog_search_rows_v1" OWNER TO "postgres";

COMMENT ON TABLE "private"."portal_catalog_search_rows_v1" IS 'Private synchronized, public-safe Portal card/document projection. Source embeddings and HNSW indexes remain authoritative and are not duplicated.';

ALTER TABLE ONLY "private"."portal_catalog_search_rows_v1"
    ADD CONSTRAINT "portal_catalog_search_rows_v1_pkey" PRIMARY KEY ("dataset_kind", "id", "version");

ALTER TABLE ONLY "private"."portal_catalog_search_rows_v1"
    ADD CONSTRAINT "portal_catalog_search_rows_contract_version_v1_fk" FOREIGN KEY ("projection_contract_version") REFERENCES "private"."portal_catalog_projection_contract_v1"("contract_version") ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE "private"."portal_catalog_search_rows_v1" ENABLE ROW LEVEL SECURITY;

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "private"."portal_catalog_search_rows_v1" TO "api_internal_executor";

GRANT SELECT("dataset_kind") ON TABLE "private"."portal_catalog_search_rows_v1" TO "portal_public_executor";

GRANT SELECT("id") ON TABLE "private"."portal_catalog_search_rows_v1" TO "portal_public_executor";

GRANT SELECT("version") ON TABLE "private"."portal_catalog_search_rows_v1" TO "portal_public_executor";

GRANT SELECT("state_code") ON TABLE "private"."portal_catalog_search_rows_v1" TO "portal_public_executor";

GRANT SELECT("modified_at") ON TABLE "private"."portal_catalog_search_rows_v1" TO "portal_public_executor";

GRANT SELECT("card") ON TABLE "private"."portal_catalog_search_rows_v1" TO "portal_public_executor";

GRANT SELECT("document") ON TABLE "private"."portal_catalog_search_rows_v1" TO "portal_public_executor";
