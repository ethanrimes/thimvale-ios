#!/usr/bin/env python3
"""Check curated repo IDs and single-file GGUF availability without downloading weights."""
import concurrent.futures
import json
import pathlib
import re
import sys
import urllib.request

source = pathlib.Path(__file__).resolve().parents[1] / "Sources/Services/ModelHub.swift"
entries = []
for line in source.read_text().splitlines():
    repository = re.search(r'repository: "([^"]+/[^"]+)"', line)
    if repository:
        quant = re.search(r'preferredQuant: "([^"]+)"', line)
        entries.append((repository[1], quant[1] if quant else "Q4_K_M"))

def check(entry):
    repo, quant = entry
    with urllib.request.urlopen("https://huggingface.co/api/models/" + repo + "?blobs=true", timeout=30) as response:
        model = json.load(response)
    files = [f for f in model.get("siblings", []) if f["rfilename"].lower().endswith(".gguf") and not any(excluded in f["rfilename"].lower() for excluded in ("mmproj", "-of-", "mtp"))]
    if not files:
        raise RuntimeError(f"{repo}: no single-file GGUFs")
    if not any(quant.lower() in file["rfilename"].lower() for file in files):
        raise RuntimeError(f"{repo}: default {quant} is unavailable")
    return f"OK {repo}: {len(files)} GGUF files, {quant} available, revision {model['sha'][:12]}"

with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
    futures = {pool.submit(check, entry): entry[0] for entry in entries}
    failed = False
    for future in concurrent.futures.as_completed(futures):
        try:
            print(future.result())
        except Exception as error:
            failed = True
            print(f"FAIL {futures[future]}: {error}")
    sys.exit(1 if failed else 0)
