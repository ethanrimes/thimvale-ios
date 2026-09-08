import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("experiments", Path(__file__).resolve().parents[2] / "scripts" / "summarize-experiments.py")
experiments = importlib.util.module_from_spec(spec)
spec.loader.exec_module(experiments)


class ExperimentReportTests(unittest.TestCase):
    def test_raw_throughput_excludes_warmup_and_uses_token_counts(self):
        rows = [dict(kind="inference", model="fixture", repetition=i, firstTokenMS=delay,
                     generatedTokens=10, decodeMS=delay) for i, delay in enumerate([1000, 100, 200])]
        summary = experiments.summarize(rows)[0]
        self.assertEqual(summary["samples"], 2)
        self.assertEqual(summary["median_firstTokenMS"], 150)
        self.assertEqual(summary["median_decode_tokens_per_second"], 75)

    def test_expected_phrase_presence_is_not_labeled_accuracy(self):
        row = dict(kind="answer", model="fixture", correct=True, supportedCitation=False,
                   output="Tuesday and Thursday", metrics={"totalMS": 100})
        summary = experiments.summarize([row])[0]
        self.assertEqual(summary["expected_phrase_present"], 1)
        self.assertEqual(summary["phrase_and_any_supporting_source_cited"], 0)
        self.assertNotIn("accuracy", summary)

    def test_retrieval_misses_score_zero_not_infinite(self):
        rows = [dict(kind="retrieval", variant="fixture", rank=rank, evidenceHit=rank > 0) for rank in [0, 1, 2]]
        summary = experiments.summarize(rows)[0]
        self.assertEqual(summary["mean_reciprocal_rank"], 0.5)
        self.assertEqual(summary["top1"], 1)
        self.assertEqual(summary["evidence_hits"], 2)

    def test_explicit_passing_scope_does_not_hide_overall_failure(self):
        log = "\n".join(["Test Case '-[Bench cache]' started.",
                          'THIMVALE_EXPERIMENT {"kind":"prompt-cache","model":"fixture"}',
                          "Test Case '-[Bench cache]' passed (1.0 seconds).",
                          "Test Case '-[Bench other]' started.",
                          'THIMVALE_EXPERIMENT {"kind":"other"}',
                          "Test Case '-[Bench other]' failed (1.0 seconds).", "** TEST FAILED **"])
        with self.assertRaises(ValueError):
            experiments.extract(log)
        with self.assertRaises(ValueError):
            experiments.extract(log, "Bench other")
        result = experiments.extract(log, "Bench cache")
        self.assertFalse(result["overall_test_run_succeeded"])
        self.assertEqual(len(result["records"]), 1)
        self.assertEqual(result["records"][0]["kind"], "prompt-cache")

    def test_incomplete_or_retried_scope_cannot_be_reported_as_passed(self):
        start = "Test Case '-[Bench cache]' started.\n"
        row = 'THIMVALE_EXPERIMENT {"kind":"prompt-cache"}\n'
        end = "Test Case '-[Bench cache]' passed (1.0 seconds).\n"
        for log in [start + row, 2 * (start + row + end), start + "file: error: assertion\n" + row + end]:
            with self.assertRaises(ValueError):
                experiments.extract(log, "Bench cache")
