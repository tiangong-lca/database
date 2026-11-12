CREATE TABLE IF NOT EXISTS "private"."portal_index_outbox" (
    "event_id" bigint NOT NULL,
    "provider" "text" NOT NULL,
    "source_transaction" "xid8" NOT NULL,
    "during_maintenance" boolean NOT NULL,
    "dataset_kind" "text" NOT NULL,
    "dataset_id" "uuid" NOT NULL,
    "dataset_version" "text" NOT NULL,
    "before_brand" "text",
    "after_brand" "text",
    "removed_latest" boolean DEFAULT false NOT NULL,
    "state" "text" DEFAULT 'pending'::"text" NOT NULL,
    "available_at" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "attempt" integer DEFAULT 0 NOT NULL,
    "lease_token" "uuid",
    "lease_expires_at" timestamp with time zone,
    "lease_candidates" "jsonb",
    "accepted_keys" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "last_settlement_token" "uuid",
    "last_outcome" "text",
    "last_reason" "text",
    "last_retry_after_seconds" integer,
    "settled_at" timestamp with time zone,
    CONSTRAINT "portal_index_outbox_check" CHECK ((("lease_token" IS NULL) = ("lease_expires_at" IS NULL))),
    CONSTRAINT "portal_index_outbox_check1" CHECK ((("lease_token" IS NULL) = ("lease_candidates" IS NULL))),
    CONSTRAINT "portal_index_outbox_check2" CHECK ((("lease_token" IS NULL) OR ("state" = 'pending'::"text"))),
    CONSTRAINT "portal_index_outbox_check3" CHECK ((("state" <> 'held'::"text") OR "during_maintenance")),
    CONSTRAINT "portal_index_outbox_dataset_kind_check" CHECK (("dataset_kind" = ANY (ARRAY['process'::"text", 'flow'::"text"]))),
    CONSTRAINT "portal_index_outbox_dataset_version_check" CHECK (("dataset_version" ~ '^[0-9]{2}\.[0-9]{2}\.[0-9]{3}$'::"text")),
    CONSTRAINT "portal_index_outbox_provider_check" CHECK (("provider" = ANY (ARRAY['indexnow'::"text", 'baidu'::"text", 'baidu_withdrawal'::"text"]))),
    CONSTRAINT "portal_index_outbox_state_check" CHECK (("state" = ANY (ARRAY['held'::"text", 'pending'::"text", 'accepted'::"text", 'blocked'::"text", 'skipped'::"text", 'manifest_ready'::"text"])))
);

ALTER TABLE ONLY "private"."portal_index_outbox" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."portal_index_outbox" OWNER TO "postgres";

ALTER TABLE "private"."portal_index_outbox" ALTER COLUMN "event_id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "private"."portal_index_outbox_event_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

ALTER TABLE ONLY "private"."portal_index_outbox"
    ADD CONSTRAINT "portal_index_outbox_pkey" PRIMARY KEY ("event_id");

ALTER TABLE ONLY "private"."portal_index_outbox"
    ADD CONSTRAINT "portal_index_outbox_provider_source_transaction_dataset_kin_key" UNIQUE ("provider", "source_transaction", "dataset_kind", "dataset_id", "dataset_version");

ALTER TABLE "private"."portal_index_outbox" ENABLE ROW LEVEL SECURITY;
