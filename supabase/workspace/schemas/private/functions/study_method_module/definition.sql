CREATE OR REPLACE FUNCTION "private"."study_method_module"() RETURNS "jsonb"
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO ''
    AS $$select '{"repository":"tiangong-lca/pcr","sourceCommit":"51c0842c67b14ba886e2edee2846e26eefac030f","moduleId":"method.pef-2021-ef31","moduleVersion":"0.1.0","artifactSha256":"b19ba5754b0bc20c44c8c65966bafafd5984cd74636f2c805c0fa4373f5554ad","reviewBasisSha256":"989391423c7f31bdf77e18ea4438fab1a27ff6708c0f44ecad8ab8813763a165","sourceBindingsSha256":"3fd9b1dc68228db3e146b6d23daac853b27b9f504f9445a0cc5a971d53257ce2"}'::jsonb$$;

ALTER FUNCTION "private"."study_method_module"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_method_module"() FROM PUBLIC;
