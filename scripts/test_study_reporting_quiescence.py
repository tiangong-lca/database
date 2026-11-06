#!/usr/bin/env python3
"""The owned upgrade guard waits for transient activity, never bypasses it."""
import unittest
from unittest.mock import patch
import test_study_runtime_reporting_upgrade as upgrade


class QuiescenceTests(unittest.TestCase):
    def test_idle_proceeds_without_sleep(self):
        with patch.object(upgrade, "sql", return_value="0\n") as query, patch.object(upgrade.time, "sleep") as sleep:
            upgrade.wait_for_database_quiescence()
            self.assertEqual(query.call_count, 1)
            sleep.assert_not_called()
            self.assertIn("pid<>pg_backend_pid()", query.call_args.args[0])

    def test_transient_activity_is_rechecked(self):
        with patch.object(upgrade, "sql", side_effect=["2", "1", "0"]) as query, patch.object(upgrade.time, "monotonic", side_effect=[0, 1, 2]), patch.object(upgrade.time, "sleep") as sleep:
            upgrade.wait_for_database_quiescence(5)
            self.assertEqual(query.call_count, 3)
            self.assertEqual(sleep.call_count, 2)

    def test_persistent_activity_blocks_reset_with_bounded_diagnostic(self):
        with patch.object(upgrade, "sql", side_effect=["1", "1", '[{"backend_type":"autovacuum worker","count":1}]']) as query, patch.object(upgrade.time, "monotonic", side_effect=[0, 1, 5]), patch.object(upgrade.time, "sleep") as sleep:
            with self.assertRaisesRegex(RuntimeError, "did not become quiescent.*autovacuum"):
                upgrade.wait_for_database_quiescence(5)
            self.assertEqual(sleep.call_count, 1)
            self.assertNotIn("query,", query.call_args.args[0])
            self.assertNotIn("application_name", query.call_args.args[0])

    def test_database_error_is_not_treated_as_idle(self):
        with patch.object(upgrade, "sql", side_effect=RuntimeError("owned upgrade SQL failed")), patch.object(upgrade.time, "sleep") as sleep:
            with self.assertRaisesRegex(RuntimeError, "owned upgrade SQL failed"):
                upgrade.wait_for_database_quiescence()
            sleep.assert_not_called()


if __name__ == "__main__":
    unittest.main()
