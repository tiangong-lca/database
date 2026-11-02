CREATE TABLE IF NOT EXISTS "private"."studies" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "owner_id" "uuid" NOT NULL,
    "team_id" "uuid",
    "title" "text" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "revision" bigint DEFAULT 1 NOT NULL,
    "grant_epoch" bigint DEFAULT 1 NOT NULL,
    "current_revision_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "studies_grant_epoch_check" CHECK (("grant_epoch" > 0)),
    CONSTRAINT "studies_revision_check" CHECK ((("revision" >= 1) AND ("revision" <= '9007199254740991'::bigint))),
    CONSTRAINT "studies_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'archived'::"text"]))),
    CONSTRAINT "studies_title_check" CHECK ((("length"("btrim"("title")) >= 1) AND ("length"("btrim"("title")) <= 512)))
);

ALTER TABLE ONLY "private"."studies" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."studies" OWNER TO "postgres";

ALTER TABLE ONLY "private"."studies"
    ADD CONSTRAINT "studies_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."studies"
    ADD CONSTRAINT "studies_id_current_revision_id_fkey" FOREIGN KEY ("id", "current_revision_id") REFERENCES "private"."study_revisions"("study_id", "id");

ALTER TABLE ONLY "private"."studies"
    ADD CONSTRAINT "studies_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "private"."studies"
    ADD CONSTRAINT "studies_team_id_fkey" FOREIGN KEY ("team_id") REFERENCES "private"."teams"("id");

ALTER TABLE "private"."studies" ENABLE ROW LEVEL SECURITY;
