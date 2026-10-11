"""Sealing tests use synthetic data only, in temporary directories under run/."""

import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest.mock import patch

sys.dont_write_bytecode = True

from . import seal


class SealTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=seal.HERE)
        self.root = Path(self.temp.name)
        self.sealed = self.root / "sealed"
        self.sealed.mkdir()
        (self.sealed / "synthetic.jsonl").write_text(json.dumps({"id": "secret-case", "schema": 2}) + "\n")
        self.ledger = self.root / "ledger.jsonl"
        self.args = dict(round_name="fixture-round", candidate="fixture-system",
                         sealed_dir=self.sealed, ledger_path=self.ledger, bootstrap=0)

    def tearDown(self):
        self.temp.cleanup()

    def execute(self, **overrides):
        args = dict(self.args, system_factory=lambda **kwargs: kwargs,
                    runner=lambda episode, system: {"id": episode["id"]},
                    scorer=lambda results, **kwargs: {"counts": {"episodes": len(results)}, "natural": {"loss": 0}})
        args.update(overrides)
        return seal.run_sealed(**args)

    def test_preregistration_never_reads_sealed(self):
        with patch.object(Path, "rglob", side_effect=AssertionError("sealed read")):
            result = seal.preregister(**self.args)
        self.assertEqual(result["status"], "preregistered")
        with self.assertRaises(seal.SealError):
            seal.preregister(**self.args)

    def test_unregistered_round_refuses_before_read(self):
        with patch.object(Path, "rglob", side_effect=AssertionError("sealed read")):
            with self.assertRaisesRegex(seal.SealError, "preregistered"):
                self.execute()

    def test_candidate_configuration_and_code_cannot_change(self):
        seal.preregister(**self.args)
        with self.assertRaisesRegex(seal.SealError, "candidate"):
            self.execute(candidate="different")
        with self.assertRaisesRegex(seal.SealError, "configuration"):
            self.execute(format_name="v0")
        with patch.object(seal, "evaluator_fingerprint", return_value="changed"):
            with self.assertRaisesRegex(seal.SealError, "evaluator"):
                self.execute()
        self.assertEqual(len(self.ledger.read_text().splitlines()), 1)

    def test_success_is_aggregate_only_and_consumes_round_once(self):
        seal.preregister(**self.args)
        output = io.StringIO()
        def noisy_runner(episode, system):
            print("secret-case secret-message")
            print("secret-error", file=sys.stderr)
            self.assertFalse(system["legacy_cache"])
            self.assertTrue(system["quiet"])
            self.assertEqual(system["cache_path"], self.sealed / ".jev-cache")
            return {"id": episode["id"], "events": [{"message": "secret-message"}]}
        with redirect_stdout(output), redirect_stderr(output):
            result = self.execute(runner=noisy_runner)
        self.assertEqual(output.getvalue(), "")
        self.assertEqual(result["aggregate"]["counts"]["episodes"], 1)
        self.assertNotIn("secret", self.ledger.read_text())
        self.assertEqual([json.loads(line)["kind"] for line in self.ledger.read_text().splitlines()],
                         ["preregister", "started", "evaluated"])
        with self.assertRaisesRegex(seal.SealError, "consumed"):
            self.execute()

    def test_failed_read_is_consumed_and_exception_text_is_private(self):
        seal.preregister(**self.args)
        def broken(*args):
            raise ValueError("secret-case secret message")
        with self.assertRaises(seal.SealError) as caught:
            self.execute(runner=broken)
        self.assertNotIn("secret", str(caught.exception))
        self.assertNotIn("secret", self.ledger.read_text())
        self.assertEqual(json.loads(self.ledger.read_text().splitlines()[-1])["kind"], "failed")
        with self.assertRaisesRegex(seal.SealError, "consumed"):
            self.execute()

    def test_per_case_output_refused_before_budget_consumption(self):
        with self.assertRaisesRegex(seal.SealError, "per-case"):
            self.execute(per_case_output=self.root / "trace.jsonl")
        self.assertFalse(self.ledger.exists())

    def test_failure_ledger_error_does_not_expose_the_original_exception(self):
        seal.preregister(**self.args)
        original = seal._ledger
        calls = 0
        def ledger(path):
            nonlocal calls
            calls += 1
            if calls > 1:
                raise OSError("private ledger details")
            return original(path)
        def broken(*args):
            raise ValueError("secret-case secret-message")
        with patch.object(seal, "_ledger", side_effect=ledger):
            with self.assertRaises(seal.SealError) as caught:
                self.execute(runner=broken)
        self.assertNotIn("secret", str(caught.exception))
        self.assertTrue(caught.exception.__suppress_context__)
        self.assertEqual(json.loads(self.ledger.read_text().splitlines()[-1])["kind"], "started")

    def test_accidental_trace_fields_in_scorer_are_refused(self):
        seal.preregister(**self.args)
        with self.assertRaisesRegex(seal.SealError, "per-case"):
            self.execute(scorer=lambda *args, **kwargs: {"events": [{"id": "secret-case"}]})
        self.assertNotIn("secret-case", self.ledger.read_text())

    def test_malformed_ledger_fails_closed(self):
        self.ledger.write_text("not-json\n")
        with self.assertRaisesRegex(seal.SealError, "malformed"):
            self.execute()


if __name__ == "__main__":
    unittest.main()
