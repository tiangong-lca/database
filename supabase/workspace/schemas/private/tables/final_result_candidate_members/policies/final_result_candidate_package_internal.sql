CREATE POLICY "final_result_candidate_package_internal" ON "private"."final_result_candidate_members" FOR SELECT TO "api_internal_executor" USING (true);
