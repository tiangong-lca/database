CREATE TABLE IF NOT EXISTS "private"."study_members" (
    "study_id" "uuid" NOT NULL,
    "actor_id" "uuid" NOT NULL,
    "role" "text" NOT NULL,
    CONSTRAINT "study_members_role_check" CHECK (("role" = ANY (ARRAY['owner'::"text", 'editor'::"text", 'viewer'::"text"])))
);

ALTER TABLE ONLY "private"."study_members" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_members" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_members"
    ADD CONSTRAINT "study_members_pkey" PRIMARY KEY ("study_id", "actor_id");

ALTER TABLE ONLY "private"."study_members"
    ADD CONSTRAINT "study_members_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "private"."study_members"
    ADD CONSTRAINT "study_members_study_id_fkey" FOREIGN KEY ("study_id") REFERENCES "private"."studies"("id");

ALTER TABLE "private"."study_members" ENABLE ROW LEVEL SECURITY;
