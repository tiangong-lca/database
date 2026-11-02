CREATE TABLE IF NOT EXISTS "private"."final_result_identities" (
    "result_id" "uuid" NOT NULL,
    "result_version" "text" NOT NULL,
    "registration_kind" "text" DEFAULT 'registered'::"text" NOT NULL,
    "registration_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "hash_domain" "text",
    "canonical_content_hash" "text",
    "content_hash" "text",
    "content_ref" "text",
    "producer" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "final_result_identities_canonical_content_hash_check" CHECK (("canonical_content_hash" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "final_result_identities_check" CHECK (((("registration_kind" = 'registered'::"text") AND ("result_version" ~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$'::"text") AND ("hash_domain" IS NOT NULL) AND ("canonical_content_hash" IS NOT NULL) AND ("content_hash" IS NOT NULL) AND ("content_ref" IS NOT NULL) AND ("content_ref" = ('urn:sha256:'::"text" || "canonical_content_hash"))) OR (("registration_kind" = 'legacy'::"text") AND ("hash_domain" IS NULL) AND ("canonical_content_hash" IS NULL) AND ("content_hash" IS NULL) AND ("content_ref" IS NULL)))),
    CONSTRAINT "final_result_identities_content_hash_check" CHECK (("content_hash" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "final_result_identities_hash_domain_check" CHECK (("hash_domain" = 'tiangong.final-result-content.jcs.v1'::"text")),
    CONSTRAINT "final_result_identities_producer_check" CHECK ((("length"("producer") >= 1) AND ("length"("producer") <= 64))),
    CONSTRAINT "final_result_identities_registration_kind_check" CHECK (("registration_kind" = ANY (ARRAY['registered'::"text", 'legacy'::"text"])))
);

ALTER TABLE "private"."final_result_identities" OWNER TO "postgres";

ALTER TABLE ONLY "private"."final_result_identities"
    ADD CONSTRAINT "final_result_identities_pkey" PRIMARY KEY ("result_id", "result_version");

ALTER TABLE ONLY "private"."final_result_identities"
    ADD CONSTRAINT "final_result_identities_registration_id_key" UNIQUE ("registration_id");

ALTER TABLE "private"."final_result_identities" ENABLE ROW LEVEL SECURITY;
