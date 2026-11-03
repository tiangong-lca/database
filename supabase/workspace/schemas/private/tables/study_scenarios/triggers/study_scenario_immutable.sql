CREATE OR REPLACE TRIGGER "study_scenario_immutable" BEFORE DELETE OR UPDATE ON "private"."study_scenarios" FOR EACH ROW EXECUTE FUNCTION "private"."study_guard_immutable"();
