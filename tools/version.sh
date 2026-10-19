#!/usr/bin/env bash
# Zählt die zentrale Version in version.json hoch und vergibt eine neue Build-Kennung.
# Aufruf: tools/version.sh [patch|minor|major|id]   (Vorgabe: patch)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$root/version.json" "${1:-patch}" <<'PY'
import json, secrets, sys
path, part = sys.argv[1], sys.argv[2]
data = json.load(open(path))
major, minor, patch = (int(x) for x in data["version"].split("."))
if part == "major":
    major, minor, patch = major + 1, 0, 0
elif part == "minor":
    minor, patch = minor + 1, 0
elif part == "patch":
    patch += 1
elif part != "id":
    sys.exit(f"unbekannter Teil: {part}")
data["version"] = f"{major}.{minor}.{patch}"
data["id"] = secrets.token_hex(3)
data["voll"] = f"v{data['version']}-{data['id']}"
json.dump(data, open(path, "w"), ensure_ascii=False, indent=2)
open(path, "a").write("\n")
print(data["voll"])
PY
