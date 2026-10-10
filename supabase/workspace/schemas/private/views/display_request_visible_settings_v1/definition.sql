CREATE OR REPLACE VIEW "private"."display_request_visible_settings_v1" WITH ("security_barrier"='true') AS
 SELECT "dataset_kind",
    "dataset_id",
    "dataset_version"
   FROM "private"."dataset_display_settings" "s"
  WHERE ("is_visible" AND (("current_setting"('portal.display_global'::"text", true) = 'true'::"text") OR ("brand" = ANY ("string_to_array"("current_setting"('portal.display_brands'::"text", true), ','::"text")))) AND ((NULLIF("current_setting"('portal.display_filter_brand'::"text", true), ''::"text") IS NULL) OR ("brand" = "current_setting"('portal.display_filter_brand'::"text", true))));

ALTER VIEW "private"."display_request_visible_settings_v1" OWNER TO "postgres";
