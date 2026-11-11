CREATE UNIQUE INDEX "lca_release_runs_replacement_uidx" ON "private"."lca_release_runs" USING "btree" ("replaced_by_run_id") WHERE ("replaced_by_run_id" IS NOT NULL);
