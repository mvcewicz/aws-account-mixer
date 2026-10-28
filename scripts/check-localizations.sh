#!/bin/bash
# Checks that every UI string in the code has a Polish translation and that no translation is stale.
# The keys come straight from the compiler (-emit-localized-strings), so they match what SwiftUI looks up.
set -euo pipefail
cd "$(dirname "$0")/.."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/strings"

swift build --scratch-path "$TMP/build" --product AWSAccountMixer \
    -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$TMP/strings" >/dev/null
plutil -convert json -o "$TMP/pl.json" Resources/pl.lproj/Localizable.strings

python3 -I - "$TMP/strings" "$TMP/pl.json" <<'PY'
import glob, json, sys

code = {
    entry["key"]
    for path in glob.glob(sys.argv[1] + "/*.stringsdata")
    for entries in json.load(open(path))["tables"].values()
    for entry in entries
}
translated = set(json.load(open(sys.argv[2])))

missing, stale = sorted(code - translated), sorted(translated - code)
for key in missing:
    print(f"missing: {key!r}")
for key in stale:
    print(f"stale:   {key!r}")
print(f"{len(code)} keys in code, {len(missing)} missing, {len(stale)} stale")
sys.exit(1 if missing or stale else 0)
PY
