#!/usr/bin/env python3
"""Mechanical catalog export. Check mode fails rather than silently changing CI files."""
import argparse
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / "ios/Sources/Services/ModelHub.swift").read_text()
entries = []
for line in source.split("actor ModelHub")[0].splitlines():
    if '.init(id: "' not in line:
        continue
    fields = dict(re.findall(r'(\w+): "((?:[^"\\]|\\.)*)"', line))
    fields = {key: json.loads('"' + value + '"') for key, value in fields.items()}
    fields["minimumMemoryGB"] = int(re.search(r'minimumMemoryGB: (\d+)', line)[1])
    fields.setdefault("preferredQuant", "Q4_K_M")
    fields["vision"] = 'vision: true' in line
    fields["summary"] = fields["summary"].replace("iPhone", "phone")
    entries.append(fields)
assert len(entries) >= 39 and len({item["id"] for item in entries}) == len(entries)
output = json.dumps(entries, ensure_ascii=False, indent=2) + "\n"
target = root / "shared/models.json"
parser = argparse.ArgumentParser()
parser.add_argument("--check", action="store_true")
args = parser.parse_args()
if args.check:
    assert target.read_text() == output, "Run python3 scripts/sync-catalog.py"
else:
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(output)
print(f"{len(entries)} model entries {'checked' if args.check else 'exported'}")
