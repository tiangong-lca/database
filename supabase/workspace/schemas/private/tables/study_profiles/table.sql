CREATE TABLE IF NOT EXISTS "private"."study_profiles" (
    "profile_id" "text" NOT NULL,
    "calculation_fingerprint" "text" NOT NULL,
    "enabled" boolean DEFAULT false NOT NULL,
    CONSTRAINT "study_profiles_profile_id_check" CHECK (("profile_id" = 'lca.study-explicit-v1'::"text"))
);

ALTER TABLE ONLY "private"."study_profiles" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_profiles" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_profiles"
    ADD CONSTRAINT "study_profiles_pkey" PRIMARY KEY ("profile_id");

ALTER TABLE ONLY "private"."study_profiles"
    ADD CONSTRAINT "study_profiles_calculation_fingerprint_fkey" FOREIGN KEY ("calculation_fingerprint") REFERENCES "private"."lca_calculation_contracts"("fingerprint");

ALTER TABLE "private"."study_profiles" ENABLE ROW LEVEL SECURITY;
