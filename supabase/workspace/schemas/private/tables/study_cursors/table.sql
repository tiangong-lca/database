CREATE TABLE IF NOT EXISTS "private"."study_cursors" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "actor_id" "uuid" NOT NULL,
    "client_id" "text",
    "selection" "jsonb" NOT NULL,
    "access_epoch" "text" NOT NULL,
    "after_id" "uuid" NOT NULL,
    "expires_at" timestamp with time zone DEFAULT ("clock_timestamp"() + '00:05:00'::interval) NOT NULL
);

ALTER TABLE ONLY "private"."study_cursors" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."study_cursors" OWNER TO "postgres";

ALTER TABLE ONLY "private"."study_cursors"
    ADD CONSTRAINT "study_cursors_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."study_cursors"
    ADD CONSTRAINT "study_cursors_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "auth"."users"("id");

ALTER TABLE "private"."study_cursors" ENABLE ROW LEVEL SECURITY;
