CREATE OR REPLACE TRIGGER "study_snapshot_immutable" BEFORE DELETE OR UPDATE ON "private"."study_source_snapshots" FOR EACH ROW EXECUTE FUNCTION "private"."study_guard_immutable"();
