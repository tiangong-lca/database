CREATE POLICY "display_scope" ON "private"."display_navigation_versions_v1" FOR SELECT TO "portal_display_executor" USING ((EXISTS ( SELECT 1
   FROM "private"."display_request_visible_settings_v1" "s"
  WHERE (("s"."dataset_kind" = "display_navigation_versions_v1"."dataset_kind") AND ("s"."dataset_id" = "display_navigation_versions_v1"."id") AND (("s"."dataset_version")::"text" = "display_navigation_versions_v1"."version")))));
