#!/usr/bin/env python3
"""Extract opt-in synthetic experiment records from a successful simulator log.

Usage: python3 scripts/summarize-experiments.py LOG --output RESULTS.json
Never feed customer conversations into this tool. Normal app logs contain no text.
"""
import argparse
import collections
import json
from pathlib import Path
import re
import statistics


def summarize(records):
    groups = collections.defaultdict(list)
    for row in records:
        key = (row["kind"], row.get("model"), row.get("threads"), row.get("cached"), row.get("batch"), row.get("variant"))
        groups[key].append(row)
    result = []
    for key, rows in groups.items():
        kind, model, threads, cached, batch, variant = key
        measured = [r for r in rows if r.get("repetition", 1) > 0] if kind in {"inference", "prefill-batch"} else rows
        item = {"kind": kind, "model": model, "threads": threads, "cached": cached, "batch": batch, "variant": variant, "samples": len(measured)}
        metrics = [r.get("metrics", r) for r in measured]
        for field in ("firstTokenMS", "totalMS", "promptTokens", "reusedTokens", "elapsedMS"):
            values = [r[field] for r in metrics if field in r]
            if values:
                item["median_" + field] = statistics.median(values)
        tps = [1000 * r["generatedTokens"] / r["decodeMS"] for r in metrics if r.get("decodeMS", 0) > 0]
        if tps:
            item["median_decode_tokens_per_second"] = statistics.median(tps)
        if kind == "retrieval":
            item.update(top1=sum(r["rank"] == 1 for r in rows), evidence_hits=sum(r["evidenceHit"] for r in rows),
                        mean_reciprocal_rank=statistics.mean(1 / r["rank"] if r["rank"] else 0 for r in rows))
        if kind == "answer":
            # Deliberately not called "accuracy": this permissive check misses added false claims.
            item["expected_phrase_present"] = sum(r["correct"] for r in rows)
            item["phrase_and_any_supporting_source_cited"] = sum(r["correct"] and r["supportedCitation"] for r in rows)
        result.append({k: v for k, v in item.items() if v is not None})
    return result


def extract(log, test_case=None):
    overall_success = "** TEST SUCCEEDED **" in log and "** TEST FAILED **" not in log
    scope = log
    if test_case:
        # Preserve a successful measurement when a different test in the run
        # failed. Never label that overall run as successful, or mix its records.
        name = re.escape(test_case)
        pattern = rf"Test Case '-\[{name}\]' started\.\n(.*?)Test Case '-\[{name}\]' (passed|failed) \("
        matches = re.findall(pattern, log, flags=re.DOTALL)
        if len(matches) != 1 or matches[0][1] != "passed" or " error: " in matches[0][0]:
            raise ValueError("The selected test case must have exactly one completed, passing execution.")
        scope = matches[0][0]
    elif not overall_success:
        raise ValueError("Only successful runs can be extracted without an explicitly passing --test-case scope.")
    records = [json.loads(line.split("THIMVALE_EXPERIMENT ", 1)[1]) for line in scope.splitlines() if "THIMVALE_EXPERIMENT " in line]
    if not records:
        raise ValueError("No experiment records found.")
    return {"overall_test_run_succeeded": overall_success, "test_case": test_case,
            "summary": summarize(records), "records": records}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--test-case", help="Exact XCTest name, e.g. ThimvaleIntegrationTests.ExperimentTests testPromptCacheMatrix")
    args = parser.parse_args()
    log = args.log.read_text()
    try:
        result = extract(log, args.test_case)
    except ValueError as error:
        parser.error(str(error))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({"log": args.log.name, **result}, indent=2) + "\n")
    print(json.dumps(result["summary"], indent=2))


if __name__ == "__main__":
    main()
