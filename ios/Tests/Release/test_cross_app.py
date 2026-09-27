import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("cross_app", Path(__file__).resolve().parents[2] / "scripts/summarize-cross-app.py")
study = importlib.util.module_from_spec(spec)
spec.loader.exec_module(study)


class CrossAppTests(unittest.TestCase):
    def rows(self, app="Fixture", prompt=243):
        return [dict(app=app, model="fixture", repetition=i, status="ok", promptTokens=prompt,
                     generatedTokens=128, callbacks=128, streamTokensPerSecond=10 + i,
                     firstTokenMS=100, loadMS=50) for i in range(-1, 4)]

    def test_excludes_warmup(self):
        result = study.summarize(self.rows())["summaries"][0]
        self.assertEqual(result["samples"], 4)
        self.assertEqual(result["median_stream_tokens_per_second"], 11.5)

    def test_does_not_hide_failed_loads(self):
        result = study.summarize([dict(app="Fixture", model="unsupported", repetition=-1, status="failed", error="unsupported architecture")])
        self.assertEqual(result["summaries"], [])
        self.assertEqual(len(result["failures"]), 1)

    def test_rejects_incomplete_runs_and_callback_batching(self):
        with self.assertRaises(ValueError):
            study.summarize(self.rows()[:-1])
        rows = self.rows()
        rows[-1]["callbacks"] = 100
        with self.assertRaises(ValueError):
            study.summarize(rows)

    def test_rejects_different_prompts(self):
        with self.assertRaises(ValueError):
            study.summarize(self.rows() + self.rows("Other", prompt=244))

    def test_pocketpal_excludes_first_sample_from_native_counter(self):
        rows = self.rows("PocketPal")
        for row in rows:
            del row["generatedTokens"]
            row["events"] = [dict(token="x", atMS=i) for i in range(128)]
            row["completion"] = dict(tokens_predicted=127, tokens_evaluated=243,
                text="x" * 128, stopped_limit=True, stopped_eos=False,
                stopped_word=False, interrupted=False, context_full=False, truncated=False)
        self.assertEqual(study.summarize(rows)["summaries"][0]["outputTokens"], 128)
        rows[-1]["events"].pop()
        with self.assertRaises(ValueError):
            study.summarize(rows)

    def test_pocketpal_counter_mismatch_is_not_generically_ignored(self):
        rows = self.rows("PocketPal")
        with self.assertRaises(ValueError):
            study.summarize(rows)
