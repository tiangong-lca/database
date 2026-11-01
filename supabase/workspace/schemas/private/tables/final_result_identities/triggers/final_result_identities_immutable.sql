CREATE OR REPLACE TRIGGER "final_result_identities_immutable" BEFORE DELETE OR UPDATE ON "private"."final_result_identities" FOR EACH ROW EXECUTE FUNCTION "private"."result_query_immutable_guard"();
