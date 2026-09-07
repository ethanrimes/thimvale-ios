#!/usr/bin/env python3
"""Check curated repo IDs and single-file GGUF availability without downloading weights."""
import concurrent.futures
import json
import pathlib
import re
import urllib.request

source = pathlib.Path(__file__).resolve().parents[1] / "Sources/Services/ModelHub.swift"
repositories = re.findall(r'repository: "([^"]+/[^"]+)"', source.read_text())

def check(repo):
    with urllib.request.urlopen("https://huggingface.co/api/models/" + repo + "?blobs=true", timeout=30) as response:
        model = json.load(response)
    files = [f for f in model.get("siblings", []) if f["rfilename"].lower().endswith(".gguf") and "mmproj" not in f["rfilename"].lower() and "-of-" not in f["rfilename"]]
    if not files:
        raise RuntimeError(f"{repo}: no single-file GGUFs")
    return f"OK {repo}: {len(files)} GGUF files, revision {model['sha'][:12]}"

with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
    for result in pool.map(check, repositories):
        print(result)
