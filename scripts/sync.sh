#!/usr/bin/env bash
# Copy skills from the outside repos in sources.yml into skills/.
#
# For each source, the script:
#   1. Clones the repo at the given ref.
#   2. Removes the skills it copied from that source last time
#      (so skills deleted upstream are deleted here too).
#   3. Copies the selected skill folders into skills/.
#   4. Records the source commit in skills/.sources.lock.
#
# The script stops with an error if an outside skill has the same name as
# one of our own skills, or as a skill from another source.
#
# Needs: git, yq (v4, https://github.com/mikefarah/yq).
# Usage: scripts/sync.sh   (run from anywhere inside the repo)

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
SOURCES="$ROOT/sources.yml"
SKILLS_DIR="$ROOT/skills"
LOCK="$SKILLS_DIR/.sources.lock"

command -v yq >/dev/null || { echo "error: yq is not installed" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$SKILLS_DIR"
[ -f "$LOCK" ] || printf 'sources: {}\n' >"$LOCK"

NEW_LOCK="$WORK/new.lock"
printf '%s\n' \
  '# Written by scripts/sync.sh. Do not edit by hand.' \
  '# Shows which commit of each outside repo the skills in this folder came from.' \
  'sources: {}' >"$NEW_LOCK"

# Every skill folder that a source owned in the last sync.
mapfile -t previously_owned < <(yq '.sources[].skills[]' "$LOCK")

# Skill folder names claimed during this run, as "name source".
declare -A claimed=()

count="$(yq '.sources | length' "$SOURCES")"
for ((i = 0; i < count; i++)); do
  name="$(yq ".sources[$i].name" "$SOURCES")"
  repo="$(yq ".sources[$i].repo" "$SOURCES")"
  ref="$(yq ".sources[$i].ref" "$SOURCES")"
  path="$(yq ".sources[$i].path // \"skills\"" "$SOURCES")"

  echo "==> $name ($repo@$ref)"
  dest="$WORK/src-$name"
  git clone --quiet --depth 1 --branch "$ref" "https://github.com/$repo.git" "$dest"
  commit="$(git -C "$dest" rev-parse HEAD)"

  # Pick skill folders: those under $path that contain a SKILL.md.
  if [ "$(yq ".sources[$i].include | type" "$SOURCES")" = "!!seq" ]; then
    mapfile -t wanted < <(yq ".sources[$i].include[]" "$SOURCES")
  else
    mapfile -t wanted < <(find "$dest/$path" -mindepth 2 -maxdepth 2 -name SKILL.md -printf '%h\n' | xargs -rn1 basename | sort)
  fi
  mapfile -t excluded < <(yq ".sources[$i].exclude // [] | .[]" "$SOURCES")

  skills=()
  for skill in "${wanted[@]}"; do
    [[ " ${excluded[*]} " == *" $skill "* ]] && continue
    if [ ! -f "$dest/$path/$skill/SKILL.md" ]; then
      echo "error: $repo has no $path/$skill/SKILL.md" >&2
      exit 1
    fi
    if [ -n "${claimed[$skill]:-}" ]; then
      echo "error: skill '$skill' comes from both '${claimed[$skill]}' and '$name'" >&2
      exit 1
    fi
    claimed[$skill]="$name"
    skills+=("$skill")
  done

  # Write this source to the new lock file.
  NAME="$name" REPO="$repo" REF="$ref" COMMIT="$commit" \
    yq -i '.sources[strenv(NAME)] = {"repo": strenv(REPO), "ref": strenv(REF), "commit": strenv(COMMIT), "skills": []}' "$NEW_LOCK"
  for skill in "${skills[@]}"; do
    NAME="$name" SKILL="$skill" yq -i '.sources[strenv(NAME)].skills += [strenv(SKILL)]' "$NEW_LOCK"
  done

  echo "    commit $commit, ${#skills[@]} skills"
done

# A claimed name must not clash with one of our own skills. Our own skills
# are folders in skills/ that no source owned in the last sync.
for skill in "${!claimed[@]}"; do
  if [ -d "$SKILLS_DIR/$skill" ] && [[ " ${previously_owned[*]} " != *" $skill "* ]]; then
    echo "error: '$skill' from '${claimed[$skill]}' has the same name as our own skill skills/$skill" >&2
    exit 1
  fi
done

# All checks passed. Replace the old copies with the new ones.
for skill in "${previously_owned[@]}"; do
  rm -rf "${SKILLS_DIR:?}/$skill"
done
for skill in "${!claimed[@]}"; do
  name="${claimed[$skill]}"
  path="$(NAME="$name" yq '.sources[] | select(.name == strenv(NAME)) | .path // "skills"' "$SOURCES")"
  cp -r "$WORK/src-$name/$path/$skill" "$SKILLS_DIR/$skill"
done
cp "$NEW_LOCK" "$LOCK"

echo "Done. ${#claimed[@]} outside skills in skills/."
