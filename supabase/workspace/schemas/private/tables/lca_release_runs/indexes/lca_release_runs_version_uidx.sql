CREATE UNIQUE INDEX "lca_release_runs_version_uidx" ON "private"."lca_release_runs" USING "btree" ("release_version") WHERE ("replaced_by_run_id" IS NULL);
