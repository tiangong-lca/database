CREATE TABLE IF NOT EXISTS "private"."lca_release_runs" (
    "id" "uuid" NOT NULL,
    "release_version" "text" NOT NULL,
    "scope_mode" "text" DEFAULT 'global_eligible'::"text" NOT NULL,
    "selection_manifest_hash" "text" NOT NULL,
    "input_manifest_hash" "text" NOT NULL,
    "calculation_bundle_hash" "text",
    "calculation_bundle_ref" "jsonb",
    "profile_lock_hash" "text" NOT NULL,
    "publish_plan_hash" "text" NOT NULL,
    "publish_plan" "jsonb" NOT NULL,
    "artifact_set_hash" "text" NOT NULL,
    "release_manifest_hash" "text",
    "release_manifest" "jsonb",
    "status" "text" DEFAULT 'prepared'::"text" NOT NULL,
    "idempotency_key" "text" NOT NULL,
    "request_hash" "text" NOT NULL,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "artifacts_finalized_at" timestamp with time zone,
    "approved_at" timestamp with time zone,
    "published_at" timestamp with time zone,
    "readback_verified_at" timestamp with time zone,
    "readback_receipt" "jsonb",
    "publication_format" "text" DEFAULT 'legacy-four-zip.v1'::"text" NOT NULL,
    CONSTRAINT "lca_release_runs_bundle_format_chk" CHECK (((("publication_format" = 'legacy-four-zip.v1'::"text") AND ("calculation_bundle_hash" IS NOT NULL) AND ("calculation_bundle_ref" IS NOT NULL)) OR (("publication_format" = 'final-result-pair.v2'::"text") AND ("calculation_bundle_hash" IS NULL) AND ("calculation_bundle_ref" IS NULL)))),
    CONSTRAINT "lca_release_runs_format_chk" CHECK (("publication_format" = ANY (ARRAY['legacy-four-zip.v1'::"text", 'final-result-pair.v2'::"text"]))),
    CONSTRAINT "lca_release_runs_hashes_chk" CHECK ((("selection_manifest_hash" ~ '^[0-9a-f]{64}$'::"text") AND ("input_manifest_hash" ~ '^[0-9a-f]{64}$'::"text") AND ("calculation_bundle_hash" ~ '^[0-9a-f]{64}$'::"text") AND ("profile_lock_hash" ~ '^[0-9a-f]{64}$'::"text") AND ("publish_plan_hash" ~ '^[0-9a-f]{64}$'::"text") AND ("artifact_set_hash" ~ '^[0-9a-f]{64}$'::"text") AND ("request_hash" ~ '^[0-9a-f]{64}$'::"text") AND (("release_manifest_hash" IS NULL) OR ("release_manifest_hash" ~ '^[0-9a-f]{64}$'::"text")))),
    CONSTRAINT "lca_release_runs_json_chk" CHECK ((("jsonb_typeof"("calculation_bundle_ref") = 'object'::"text") AND ("jsonb_typeof"("publish_plan") = 'object'::"text") AND (("release_manifest" IS NULL) OR ("jsonb_typeof"("release_manifest") = 'object'::"text")) AND (("readback_receipt" IS NULL) OR ("jsonb_typeof"("readback_receipt") = 'object'::"text")))),
    CONSTRAINT "lca_release_runs_release_version_chk" CHECK (((("publication_format" = 'legacy-four-zip.v1'::"text") AND ("release_version" ~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$'::"text")) OR (("publication_format" = 'final-result-pair.v2'::"text") AND ("length"("release_version") <= 64) AND ("release_version" ~ '^[0-9]{4}\.[0-9]{2}\.[0-9]+$'::"text")))),
    CONSTRAINT "lca_release_runs_scope_chk" CHECK (((("publication_format" = 'legacy-four-zip.v1'::"text") AND ("scope_mode" = 'global_eligible'::"text")) OR (("publication_format" = 'final-result-pair.v2'::"text") AND ("scope_mode" = 'selected_final_results'::"text")))),
    CONSTRAINT "lca_release_runs_status_chk" CHECK (("status" = ANY (ARRAY['prepared'::"text", 'ready_for_approval'::"text", 'approved'::"text", 'published'::"text", 'readback_verified'::"text", 'unpublished'::"text", 'failed'::"text", 'abandoned'::"text"])))
);

ALTER TABLE "private"."lca_release_runs" OWNER TO "postgres";

COMMENT ON TABLE "private"."lca_release_runs" IS 'Durable release control-plane facts. Canonical TIDAS datasets and ZIP bytes remain immutable object artifacts, not editable authoring rows.';

ALTER TABLE ONLY "private"."lca_release_runs"
    ADD CONSTRAINT "lca_release_runs_pkey" PRIMARY KEY ("id");

ALTER TABLE "private"."lca_release_runs" ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON TABLE "private"."lca_release_runs" TO "api_internal_executor";
