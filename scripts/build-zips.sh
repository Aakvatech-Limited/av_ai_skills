#!/usr/bin/env bash
# Make one .zip file per skill in skills/.
#
# Each zip holds the skill folder with SKILL.md inside it. This is the
# layout that claude.ai expects when you upload a skill.
#
# Usage: scripts/build-zips.sh [output folder]   (default: dist)

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
OUT="$(realpath -m "${1:-dist}")"

mkdir -p "$OUT"
cd "$ROOT/skills"

count=0
for skill_md in */SKILL.md; do
  skill="$(dirname "$skill_md")"
  rm -f "$OUT/$skill.zip"
  zip -qr "$OUT/$skill.zip" "$skill"
  count=$((count + 1))
done

echo "Made $count zip files in $OUT"
