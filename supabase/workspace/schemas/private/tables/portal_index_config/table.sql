CREATE TABLE IF NOT EXISTS "private"."portal_index_config" (
    "singleton" boolean DEFAULT true NOT NULL,
    "origin" "text",
    "allowed_brands" "text"[],
    "capture_enabled" boolean DEFAULT false NOT NULL,
    "dispatch_enabled" boolean DEFAULT false NOT NULL,
    "maintenance_gap" boolean DEFAULT false NOT NULL,
    "maintenance_transaction" "xid8",
    "maintenance_resume_transaction" "xid8",
    "indexnow_not_before" timestamp with time zone,
    "baidu_not_before" timestamp with time zone,
    CONSTRAINT "portal_index_config_check" CHECK ((("origin" IS NULL) = ("allowed_brands" IS NULL))),
    CONSTRAINT "portal_index_config_check1" CHECK (((NOT "capture_enabled") OR ("origin" IS NOT NULL))),
    CONSTRAINT "portal_index_config_check2" CHECK (((NOT "dispatch_enabled") OR "capture_enabled")),
    CONSTRAINT "portal_index_config_check3" CHECK (((NOT "maintenance_gap") OR "capture_enabled")),
    CONSTRAINT "portal_index_config_check4" CHECK ((("maintenance_transaction" IS NULL) OR "maintenance_gap")),
    CONSTRAINT "portal_index_config_check5" CHECK ((("maintenance_resume_transaction" IS NULL) OR ("maintenance_transaction" IS NOT NULL))),
    CONSTRAINT "portal_index_config_singleton_check" CHECK ("singleton")
);

ALTER TABLE ONLY "private"."portal_index_config" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."portal_index_config" OWNER TO "postgres";

ALTER TABLE ONLY "private"."portal_index_config"
    ADD CONSTRAINT "portal_index_config_pkey" PRIMARY KEY ("singleton");

ALTER TABLE "private"."portal_index_config" ENABLE ROW LEVEL SECURITY;
