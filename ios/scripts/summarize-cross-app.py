#!/usr/bin/env python3
"""Summarize matched simulator streaming measurements; never treat failed loads as speed."""
import argparse
import json
import math
from collections import defaultdict
from pathlib import Path
from statistics import median


def output_count(row):
    completion = row.get("completion", {})
    generated = row.get("generatedTokens", completion.get("tokens_predicted"))
    if row["app"] == "PocketPal":
        # Pinned llama.rn 0.13.0-rc.5 nextToken() increments num_tokens_predicted
        # only when `tg` is true. The first sample follows multi-token prefill,
        # so it is streamed but excluded from that native decode counter.
        # Accept this normalization ONLY with a complete, non-batched event log
        # and an uninterrupted output-limit stop; retain native counts in raw data.
        events = row.get("events", [])
        pieces = [event["token"] for event in events if event.get("token")]
        if (generated != 127 or row.get("callbacks") != 128 or len(pieces) != 128
                or "".join(pieces) != completion.get("text")
                or completion.get("stopped_limit") is not True
                or any(completion.get(key) is not False for key in
                       ("stopped_eos", "stopped_word", "interrupted", "context_full", "truncated"))):
            raise ValueError("Unverified PocketPal token-counter normalization")
        return generated + 1
    return generated


def summarize(rows):
    groups = defaultdict(list)
    failures = []
    for row in rows:
        if row.get("status") != "ok":
            failures.append({key: row.get(key) for key in ("app", "model", "repetition", "error")})
            continue
        if row["repetition"] < 0:
            continue
        completion = row.get("completion", {})
        prompt = row.get("promptTokens", completion.get("tokens_evaluated"))
        generated = output_count(row)
        callbacks = row.get("callbacks", generated)
        if generated != 128 or callbacks != generated:
            raise ValueError(f"Unmatched output/callback counts: {row['app']} {row['model']}: {generated}/{callbacks}")
        if not isinstance(prompt, int) or prompt <= 0:
            raise ValueError("Missing prompt token count")
        rate = row["streamTokensPerSecond"]
        if not math.isfinite(rate) or rate <= 0:
            raise ValueError("Invalid streaming rate")
        groups[(row["model"], row["app"])].append(dict(row, promptTokens=prompt))
    summaries = []
    for (model, app), samples in sorted(groups.items()):
        if {r["repetition"] for r in samples} != {0, 1, 2, 3} or len(samples) != 4:
            raise ValueError(f"Incomplete or duplicate measured repetitions: {app} {model}")
        if len({r["promptTokens"] for r in samples}) != 1:
            raise ValueError("Prompt counts changed within a case")
        rates = [r["streamTokensPerSecond"] for r in samples]
        summaries.append({"model": model, "app": app, "samples": len(samples),
            "promptTokens": samples[0]["promptTokens"], "outputTokens": 128,
            "median_stream_tokens_per_second": median(rates), "min_stream_tokens_per_second": min(rates),
            "max_stream_tokens_per_second": max(rates),
            "median_first_token_ms": median(r.get("callbackFirstTokenMS", r["firstTokenMS"]) for r in samples),
            "median_load_ms": median(r["loadMS"] for r in samples)})
    for model in {r["model"] for r in summaries}:
        if len({r["promptTokens"] for r in summaries if r["model"] == model}) != 1:
            raise ValueError(f"Prompt token mismatch between apps for {model}")
    return {"metric": "stream callbacks after the first / elapsed first-to-last callback seconds",
            "warmups_excluded": True, "summaries": summaries, "failures": failures}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+", type=Path)
    args = parser.parse_args()
    rows = [row for path in args.inputs for row in json.loads(path.read_text())]
    print(json.dumps(summarize(rows), indent=2))
