#!/usr/bin/env bash
# Run the same raw-SQL check as the "No Raw SQL" GitHub workflow (.github/workflows/no-raw-sql.yml),
# plus a wider scan for raw-SQL helpers the CI pattern does not catch.
#
# Usage: find_raw_sql.sh <app-repo-path>
# Exit code: 1 when the CI pattern matches (the workflow would fail), 0 otherwise.
set -uo pipefail

repo="${1:-.}"
cd "$repo" || { echo "Cannot enter $repo" >&2; exit 2; }

mapfile -t hooks < <(find . -mindepth 2 -maxdepth 3 -type f -name hooks.py -not -path './.git/*' -print)
if [ "${#hooks[@]}" -ne 1 ]; then
	echo "Expected exactly one Frappe hooks.py, found ${#hooks[@]} (the CI job fails on this too)" >&2
	exit 2
fi
app_dir=$(dirname "${hooks[0]}")

echo "== CI pattern (these fail the workflow) in $app_dir"
ci_hits=$(grep -RInE --include='*.py' \
	'frappe\.db\.(sql|multisql)\b|(^|[^[:alnum:]_])db\.sql[[:space:]]*\(' \
	"$app_dir")
if [ -n "$ci_hits" ]; then
	echo "$ci_hits"
	echo "-- $(echo "$ci_hits" | wc -l) line(s) in $(echo "$ci_hits" | cut -d: -f1 | sort -u | wc -l) file(s)"
else
	echo "none"
fi

echo
echo "== Other raw SQL helpers (pass CI today, still raw SQL)"
grep -RInE --include='*.py' 'db\.(sql_list|sql_ddl)\b' "$app_dir" || echo "none"

[ -z "$ci_hits" ]
