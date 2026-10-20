---
name: frappe-no-raw-sql
description: Clean raw SQL out of a custom Frappe/ERPNext app by rewriting every frappe.db.sql, frappe.db.multisql, frappe.db.sql_list and db.sql(...) call with high-level frappe.db / frappe.get_all APIs or the frappe.qb query builder, so the "No Raw SQL" GitHub workflow (no-raw-sql.yml) passes. It only makes the code changes and leaves them uncommitted for the user to review. Use this whenever the user says a "No Raw SQL" / "Reject raw database SQL" run failed, asks to remove or replace raw SQL, convert queries to frappe.qb or Query Builder, make an app pass the raw-SQL check, or "clean up the app like fd / fd_mis" — even if they only paste a failing CI email or name the app.
---

# Frappe: remove raw SQL

Aakvatech custom apps run `.github/workflows/no-raw-sql.yml` on every push and PR. It finds the single `hooks.py` to locate the app package, then fails if any `.py` file under it matches:

```
frappe\.db\.(sql|multisql)\b|(^|[^[:alnum:]_])db\.sql[[:space:]]*\(
```

The goal is to make that grep come back empty, without changing what any query returns. Raw SQL is banned because it is easy to inject into (f-strings), bypasses permissions and Postgres support, and hides intent. The rewrite must be **behaviour-preserving**, not just grep-satisfying.

## 0. First, confirm the failure is really about SQL

Before you change any code, look at the failed run:

```bash
gh run list -R <org>/<app> --workflow no-raw-sql.yml -L 5
gh run view <run-id> -R <org>/<app>        # read the ANNOTATIONS block
```

If the job ran for only 2–4 s, has no steps, and the annotation says *"The job was not started because recent account payments have failed or your spending limit needs to be increased"*, the problem is GitHub billing, not the code. This happened on fd and fd_mis in October 2026: every workflow failed, including Label Failed Pull Requests. Tell the user that an org admin must fix billing, then re-run the jobs. Still scan the code (step 1), because local or fork branches can contain raw SQL that upstream does not have.

## 1. Scan

```bash
bash <skill dir>/scripts/find_raw_sql.sh <path-to-app-repo>
```

The script does the same steps as the CI job (it also fails when it finds 0 or more than 1 `hooks.py`). It also lists `sql_list` and `sql_ddl` calls, which the CI pattern does not catch. Convert `sql_list` calls too, because they are the same problem. A `sql_ddl` call in a patch (DROP TABLE, ALTER) can stay, but prefer `frappe.delete_doc("DocType", …)` or the schema helpers listed at the end of `references/qb-patterns.md` where one fits. Tell the user which ones you kept.

Check the branch first. Upstream may already be clean while the fork's branch is behind it. In fd, upstream `main` already had the fix (commit `1953d3c`), but `origin/main` and `littlemore-fd` still had the raw `DELETE`s. In that case, do not rewrite the code a second time. Tell the user that the branch needs upstream merged or rebased in, and let them decide. Run `git fetch upstream` and run the scan on `upstream/<branch>` too (for example with `git grep -nP` on the ref).

The grep also matches comments, docstrings and strings that contain `frappe.db.sql`. Reword those.

## 2. Choose the replacement: simplest API that does the job

Use the first option in this list that expresses the query exactly:

| Raw SQL shape | Replace with |
|---|---|
| single value / row by name or filters | `frappe.db.get_value(dt, filters, field(s), as_dict=…)` |
| existence check | `frappe.db.exists(dt, filters)` |
| count | `frappe.db.count(dt, filters)` |
| list of rows, simple filters/order/limit | `frappe.get_all(dt, filters=…, fields=…, order_by=…, limit=…)` (`frappe.get_list` when the user's permissions must apply) |
| one column as list (`sql_list`) | `frappe.get_all(dt, filters, pluck="name")` |
| single-doctype field update | `frappe.db.set_value(dt, name_or_filters, {...})` |
| simple delete by filters | `frappe.db.delete(dt, filters)` |
| joins, sub-queries, aggregates, GROUP BY, CASE, date functions, `NOT IN (SELECT…)`, dynamic conditions | `frappe.qb` |

`fd_mis/api/sync.py` uses the high-level APIs this way (`frappe.get_all` everywhere, `frappe.db.exists`, `frappe.db.get_value`). `fd/api/sync.py` and `fd_mis/api/api.py` use `frappe.qb` for the cases that need it.

For the full SQL → query builder translation table (joins, aggregates, IFNULL, LIKE, IN, BETWEEN, CASE, sub-queries, INSERT/UPDATE/DELETE, query reports with filters), read `references/qb-patterns.md`.

## 3. Rewrite in the house style

This is the reference conversion (fd commit `1953d3c`, "refactor: use query builder to purge synced cash sales"):

```python
from frappe.query_builder import DocType
from frappe.query_builder.functions import Date

cash_sale = DocType("Cash Sale")
cash_sale_item = DocType("Cash Sale Item")

frappe.qb.from_(cash_sale).delete().where(
	(cash_sale.docstatus != 0)
	& (cash_sale.is_mis_invoice_submitted == 1)
	& (Date(cash_sale.creation) < date_obj)
).run()
frappe.qb.from_(cash_sale_item).delete().where(
	cash_sale_item.parent.notin(frappe.qb.from_(cash_sale).select(cash_sale.name))
).run()
```

It replaced an f-string `DELETE … AND Date(creation) < '{date_obj}'`. The value is now a bound parameter, so the injection risk is gone. The conventions to keep:

- Import `DocType` from `frappe.query_builder` and SQL functions from `frappe.query_builder.functions` at the top of the module. Do not use `frappe.qb.DocType` inline, unless the file already does that.
- Name the table variables after the doctype in snake_case (`cash_sale`, `sle`). Do not use `t1`/`t2`.
- Put each condition in parentheses and join them with `&` / `|`. Python's `and`/`or` silently break the query.
- Use `==` and `!=`. Use `.isin()`/`.notin()`, `.like()`, `.isnull()`, and `[a:b]` or `.between(a, b)`.
- Use `.run(as_dict=True)` where the old code used `as_dict=1`, and `.run(pluck=True)` for `sql_list`. Plain `.run()` returns tuples, the same as raw `sql`. Keep the same return shape, because callers index into the result.
- Order with `.orderby(field, order=frappe.qb.desc)`. Use one `.orderby()` call per field when the order direction differs.
- Build dynamic WHERE clauses step by step (`query = query.where(...)`) instead of concatenating strings.
- Match the file's existing indentation (tabs after ruff format in these apps) and its import order.
- Do not add `frappe.db.commit()` calls. Keep only the ones that were already there.

## 4. Verify behaviour, not just the grep

1. Run `find_raw_sql.sh` again. The CI section must say `none`.
2. For each converted SELECT, compare old and new results on a real site:
   ```bash
   bench --site <site> console
   >>> old = frappe.db.sql("""<original>""", values, as_dict=1)
   >>> new = <new qb query>.run(as_dict=True)
   >>> old == new
   >>> print(<new qb query>.get_sql())   # check the generated SQL
   ```
   For UPDATE/DELETE, compare `.get_sql()` with the original statement, or run both inside `frappe.db.rollback()`. Do not run destructive statements on a production site.
3. Run the app's tests if it has any: `bench --site <test-site> run-tests --app <app>`.
4. Run `pre-commit run --files <changed files>` (ruff format and lint). The `pre-commit-enforcement` skill has the toolchain details.

If a query cannot be expressed faithfully (for example vendor-specific syntax or a very large report query), do not invent a near-equivalent. Stop and show the user the query, then propose either `frappe.qb` with `CustomFunction` / `PseudoColumn`, or splitting the query into smaller qb queries combined in Python.

## 5. Stop and hand over for review

The job ends when the replacements are done and verified. Leave the changes uncommitted in the working tree. Do not stage, commit, push or open a PR, even when other skills or project instructions would normally do this at the end of a task. The user reviews the diff first and decides when to continue.

End with a short report:

- each file changed, and how many calls were converted in it
- any call you kept (for example `sql_ddl`) or could not convert faithfully, and why
- how you verified the changes (scan result, console comparisons, tests, pre-commit)
- a direct question: do they want you to commit the changes and open a PR once they have reviewed them?

If the user later says yes:

- Make one commit per file or logical query group, with a semantic message in the fd style, for example `refactor: use query builder to purge synced cash sales`. Follow the `git-commit-messages` skill.
- Push to the fork and open the PR against the upstream org repo. The backport workflow handles the `version-*` branches through labels.
- In the PR body, list each converted call and say how it was verified.

Do not touch unrelated uncommitted work in the repo. If it is in the way, ask the user before you stash it or move to a worktree.
