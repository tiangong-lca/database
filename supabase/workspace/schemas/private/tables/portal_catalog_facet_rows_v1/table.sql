CREATE TABLE IF NOT EXISTS "private"."portal_catalog_facet_rows_v1" (
    "dataset_kind" "text" NOT NULL,
    "id" "uuid" NOT NULL,
    "version" "text" NOT NULL,
    "state_code" integer NOT NULL,
    "modified_at" timestamp with time zone NOT NULL,
    "facet_access_level" "text",
    "facet_geography" "text",
    "facet_reference_year" "text",
    "facet_process_subtype" "text",
    "facet_source" "text",
    "facet_contract_version" smallint NOT NULL,
    "flow_version" "text" GENERATED ALWAYS AS (
CASE
    WHEN ("dataset_kind" = 'flow'::"text") THEN "version"
    ELSE NULL::"text"
END) STORED,
    "process_version" "text" GENERATED ALWAYS AS (
CASE
    WHEN ("dataset_kind" = 'process'::"text") THEN "version"
    ELSE NULL::"text"
END) STORED,
    CONSTRAINT "portal_catalog_facet_rows_contract_version_v1_chk" CHECK (("facet_contract_version" = 1)),
    CONSTRAINT "portal_catalog_facet_rows_process_subtype_v1_chk" CHECK ((("dataset_kind" = 'process'::"text") OR ("facet_process_subtype" IS NULL))),
    CONSTRAINT "portal_catalog_facet_rows_v1_dataset_kind_check" CHECK (("dataset_kind" = ANY (ARRAY['process'::"text", 'flow'::"text"]))),
    CONSTRAINT "portal_catalog_facet_rows_v1_state_code_check" CHECK (("state_code" = ANY (ARRAY[100, 200]))),
    CONSTRAINT "portal_catalog_facet_rows_v1_version_check" CHECK (("version" ~ '^\d{2}\.\d{2}\.\d{3}$'::"text"))
);

ALTER TABLE ONLY "private"."portal_catalog_facet_rows_v1" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."portal_catalog_facet_rows_v1" OWNER TO "postgres";

ALTER TABLE ONLY "private"."portal_catalog_facet_rows_v1"
    ADD CONSTRAINT "portal_catalog_facet_rows_v1_pkey" PRIMARY KEY ("dataset_kind", "id", "version");

ALTER TABLE ONLY "private"."portal_catalog_facet_rows_v1"
    ADD CONSTRAINT "portal_catalog_facet_rows_contract_version_v1_fk" FOREIGN KEY ("facet_contract_version") REFERENCES "private"."portal_catalog_facet_contract_v1"("contract_version") ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE ONLY "private"."portal_catalog_facet_rows_v1"
    ADD CONSTRAINT "portal_facet_flow_parent_fk" FOREIGN KEY ("dataset_kind", "id", "flow_version") REFERENCES "private"."portal_catalog_search_rows_v1"("dataset_kind", "id", "version") ON UPDATE RESTRICT ON DELETE CASCADE;

ALTER TABLE ONLY "private"."portal_catalog_facet_rows_v1"
    ADD CONSTRAINT "portal_facet_process_parent_fk" FOREIGN KEY ("dataset_kind", "id", "process_version") REFERENCES "private"."portal_catalog_search_rows_v2"("dataset_kind", "id", "version") ON UPDATE RESTRICT ON DELETE CASCADE;

ALTER TABLE "private"."portal_catalog_facet_rows_v1" ENABLE ROW LEVEL SECURITY;

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "private"."portal_catalog_facet_rows_v1" TO "api_internal_executor";

GRANT SELECT("dataset_kind") ON TABLE "private"."portal_catalog_facet_rows_v1" TO "portal_public_executor";

GRANT SELECT("id") ON TABLE "private"."portal_catalog_facet_rows_v1" TO "portal_public_executor";

GRANT SELECT("version") ON TABLE "private"."portal_catalog_facet_rows_v1" TO "portal_public_executor";

GRANT SELECT("state_code") ON TABLE "private"."portal_catalog_facet_rows_v1" TO "portal_public_executor";

GRANT SELECT("modified_at") ON TABLE "private"."portal_catalog_facet_rows_v1" TO "portal_public_executor";

GRANT SELECT("facet_access_level") ON TABLE "private"."portal_catalog_facet_rows_v1" TO "portal_public_executor";

GRANT SELECT("facet_geography") ON TABLE "private"."portal_catalog_facet_rows_v1" TO "portal_public_executor";

GRANT SELECT("facet_reference_year") ON TABLE "private"."portal_catalog_facet_rows_v1" TO "portal_public_executor";

GRANT SELECT("facet_process_subtype") ON TABLE "private"."portal_catalog_facet_rows_v1" TO "portal_public_executor";

GRANT SELECT("facet_source") ON TABLE "private"."portal_catalog_facet_rows_v1" TO "portal_public_executor";

GRANT SELECT("facet_contract_version") ON TABLE "private"."portal_catalog_facet_rows_v1" TO "portal_public_executor";
