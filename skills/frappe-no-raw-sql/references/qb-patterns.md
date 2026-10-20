# SQL → Frappe Query Builder patterns

Every example was checked with `.get_sql()` on Frappe v15. Imports used below:

```python
from frappe.query_builder import Case, CustomFunction, DocType, Interval
from frappe.query_builder.custom import ConstantColumn
from frappe.query_builder.functions import (
	Coalesce, Count, CurDate, Date, IfNull, Max, Sum, CombineDatetime, Round, Concat
)
```

## Contents
1. Select, where, order, limit
2. Operators
3. Joins (incl. child tables)
4. Aggregates and GROUP BY / HAVING
5. Functions: IFNULL, dates, CASE, DISTINCT, constants
6. Sub-queries
7. Dynamic conditions and query reports
8. INSERT / UPDATE / DELETE
9. Return shapes
10. Things that need care

---

## 1. Select, where, order, limit

```sql
SELECT name, customer, grand_total FROM `tabSales Invoice`
WHERE docstatus = 1 AND company = %s ORDER BY posting_date DESC, name LIMIT 20
```
```python
si = DocType("Sales Invoice")
rows = (
	frappe.qb.from_(si)
	.select(si.name, si.customer, si.grand_total)
	.where((si.docstatus == 1) & (si.company == company))
	.orderby(si.posting_date, order=frappe.qb.desc)
	.orderby(si.name)
	.limit(20)
).run(as_dict=True)
```
This one has no join or function, so `frappe.get_all("Sales Invoice", filters={"docstatus": 1, "company": company}, fields=[...], order_by="posting_date desc, name asc", limit=20)` is simpler. Prefer it.

`SELECT *` → `.select("*")`. Use an alias with `.as_("alias")`. For a field name with a space or a reserved word, use `si["field name"]` or `si.field("from")`.

## 2. Operators

| SQL | qb |
|---|---|
| `a = x`, `a != x`, `<`, `>=` | `t.a == x`, `t.a != x`, `t.a < x`, `t.a >= x` |
| `a IN (…)` / `NOT IN` | `t.a.isin(list)` / `t.a.notin(list)` |
| `a LIKE '%x%'` / `NOT LIKE` | `t.a.like(f"%{x}%")` / `t.a.not_like(...)` |
| `a IS NULL` / `IS NOT NULL` | `t.a.isnull()` / `t.a.isnotnull()` |
| `a BETWEEN x AND y` | `t.a[x:y]` or `t.a.between(x, y)` |
| `AND` / `OR` / `NOT` | `(c1) & (c2)`, `(c1) \| (c2)`, `~(c1)` |
| `a = ''` or NULL | `IfNull(t.a, "") == ""` |

An empty list passed to `.isin([])` generates `IN ()`, which is invalid SQL and fails only when the query runs. Guard it the same way the old code guarded the string join.

## 3. Joins

```sql
SELECT si.name, sii.item_code, sii.qty
FROM `tabSales Invoice` si
INNER JOIN `tabSales Invoice Item` sii ON sii.parent = si.name
LEFT JOIN `tabItem` i ON i.name = sii.item_code
WHERE si.docstatus = 1 AND i.is_stock_item = 1
```
```python
si = DocType("Sales Invoice")
sii = DocType("Sales Invoice Item")
item = DocType("Item")
rows = (
	frappe.qb.from_(si)
	.inner_join(sii).on(sii.parent == si.name)
	.left_join(item).on(item.name == sii.item_code)
	.select(si.name, sii.item_code, sii.qty)
	.where((si.docstatus == 1) & (item.is_stock_item == 1))
).run(as_dict=True)
```
To read a child table for one parent, use `frappe.get_all("Sales Invoice Item", filters={"parent": name, "parenttype": "Sales Invoice"}, fields=[...])`. fd_mis `sync.py` does this for barcodes, uoms and attributes.

## 4. Aggregates, GROUP BY, HAVING

```sql
SELECT customer, SUM(grand_total) AS total, COUNT(name) AS cnt
FROM `tabSales Invoice` WHERE docstatus = 1
GROUP BY customer HAVING SUM(grand_total) > 1000
```
```python
si = DocType("Sales Invoice")
rows = (
	frappe.qb.from_(si)
	.select(si.customer, Sum(si.grand_total).as_("total"), Count(si.name).as_("cnt"))
	.where(si.docstatus == 1)
	.groupby(si.customer)
	.having(Sum(si.grand_total) > 1000)
).run(as_dict=True)
```
To get a single scalar, `frappe.db.get_value(dt, filters, "sum(grand_total)")` or `frappe.qb.from_(t).select(Sum(t.x)).where(...).run()[0][0] or 0` both work.

## 5. Functions

| SQL | qb |
|---|---|
| `IFNULL(a, 0)` / `COALESCE(a, b)` | `IfNull(t.a, 0)` / `Coalesce(t.a, t.b)` |
| `DATE(creation)` | `Date(t.creation)` |
| `TIMESTAMP(posting_date, posting_time)` | `CombineDatetime(t.posting_date, t.posting_time)` |
| `ROUND(x, 2)` | `Round(t.x, 2)` |
| `CONCAT(a, ' ', b)` | `Concat(t.a, " ", t.b)` |
| `MAX(x)`, `MIN`, `AVG`, `ABS` | `Max(t.x)`, … from `frappe.query_builder.functions` |
| `SELECT DISTINCT a` | `.select(t.a).distinct()` |
| `'Sales' AS type` | `ConstantColumn("Sales").as_("type")` |
| `CURDATE() - INTERVAL 30 DAY` | pass `add_days(nowdate(), -30)` as a value (preferred), or `CurDate() - Interval(days=30)` |
| any other SQL function | `MyFn = CustomFunction("FN_NAME", ["arg1", "arg2"])`, then `MyFn(t.a, t.b)` |

CASE:
```python
Case().when(t.status == "Paid", 1).when(t.status == "Unpaid", 0).else_(-1).as_("flag")
```

## 6. Sub-queries

From fd `hourly_sync`:
```python
frappe.qb.from_(cash_sale_item).delete().where(
	cash_sale_item.parent.notin(frappe.qb.from_(cash_sale).select(cash_sale.name))
).run()
```
`EXISTS (…)` → `.where(ExistsCriterion(subquery))` (`from pypika.terms import ExistsCriterion`). A sub-query in FROM: give it an alias with `sub = (frappe.qb.from_(...).select(...)).as_("sub")`, then `frappe.qb.from_(sub).select(sub.col)`.

## 7. Dynamic conditions and query reports

Old pattern:
```python
conditions = ""
if filters.get("company"):
	conditions += " AND company = %(company)s"
if filters.get("from_date"):
	conditions += " AND posting_date >= %(from_date)s"
frappe.db.sql(f"SELECT ... WHERE docstatus = 1 {conditions}", filters, as_dict=1)
```
New pattern:
```python
si = DocType("Sales Invoice")
query = frappe.qb.from_(si).select(si.name, si.grand_total).where(si.docstatus == 1)
if filters.get("company"):
	query = query.where(si.company == filters.company)
if filters.get("from_date"):
	query = query.where(si.posting_date >= filters.from_date)
data = query.run(as_dict=True)
```
Each `.where()` call is added with AND. Build OR groups as one `Criterion` first: `Criterion.any([c1, c2])` / `Criterion.all([...])` (`from frappe.query_builder import Criterion`).

Keep `get_conditions()`-style helpers, but have them take the query and return it, instead of returning a string.

## 8. INSERT / UPDATE / DELETE

```python
# UPDATE `tabCash Sale` SET is_mis_invoice_submitted = 1 WHERE name IN (...)
cs = DocType("Cash Sale")
frappe.qb.update(cs).set(cs.is_mis_invoice_submitted, 1).where(cs.name.isin(names)).run()
# simpler, when the filters are plain:
frappe.db.set_value("Cash Sale", {"name": ("in", names)}, "is_mis_invoice_submitted", 1)

# DELETE FROM `tabX` WHERE parent = %s
frappe.db.delete("X", {"parent": parent})

# INSERT INTO `tabX` (a, b) VALUES (...), (...)
frappe.qb.into(DocType("X")).columns("a", "b").insert(*rows).run()
```
Raw INSERTs into doctype tables skip `name`, `creation`, `owner` and hooks. Check whether `frappe.get_doc({...}).insert()` (or `frappe.db.bulk_insert`) was what the code really meant.

`frappe.db.set_value` and raw `UPDATE` do not run controller hooks. Keep it that way. Do not "upgrade" to `doc.save()` without the user's agreement, because that changes behaviour.

## 9. Return shapes

| old | new |
|---|---|
| `frappe.db.sql(q)` → tuple of tuples | `query.run()` |
| `frappe.db.sql(q, as_dict=1)` | `query.run(as_dict=True)` |
| `frappe.db.sql(q, as_list=1)` | `query.run(as_list=True)` |
| `frappe.db.sql_list(q)` / `[d[0] for d in sql(q)]` | `query.run(pluck=True)` or `frappe.get_all(dt, filters, pluck="field")` |
| `frappe.db.sql(q)[0][0]` | `query.run()[0][0]`, or `frappe.db.get_value` |
| `frappe.db.sql(q, debug=1)` | `query.run(debug=True)` |

## 10. Things that need care

- **Python `and`/`or`/`not` and `in`** inside `.where()` are bugs. Use `&`, `|`, `~` and `.isin()`.
- **Operator precedence:** `&` binds tighter than `==` in Python, so put every comparison in parentheses.
- **Field names that clash with pypika methods** (`name` is fine, but `count`, `as_`, `field`, `table`, `get_sql`): use `t["count"]`.
- **Doctype names with spaces** are handled by `DocType("Sales Invoice")`. Never write `` `tab…` ``.
- **`None` values change meaning between APIs.** Raw `col = %s` with `None` becomes `col = NULL`, which matches no rows. qb `t.col == None` keeps `= NULL`. But `frappe.db.delete` / `frappe.get_all` / `set_value` filters turn `{"col": None}` into `col IS NULL`, which matches rows. Use qb when a filter value can be `None`, or the rewrite can delete or update more rows than before. (Found in vsd_fleet_ms `delete_gl_entries`.)
- **Correlated sub-queries are safe.** qb qualifies the outer column inside the sub-query (`` `tabTrips`.`assigned_driver`=`tabTruck Driver`.`name` ``), so you do not need aliases.
- **`frappe.get_all` and `ignore_permissions`:** `get_all` ignores permissions and `get_list` applies them. Raw SQL never applied them, so `get_all` (or qb) keeps the old behaviour.
- **Postgres:** qb produces portable SQL. Vendor-only syntax (`ON DUPLICATE KEY`, `FORCE INDEX`, `GROUP_CONCAT … SEPARATOR`) needs `GroupConcat` or a different approach. Flag these to the user.
- **`sql_ddl`** (ALTER/DROP in patches) has no qb equivalent. Use `frappe.db.add_index`, `frappe.db.add_unique`, `frappe.db.change_column_type`, or `frappe.delete_doc("DocType", …)` where they fit. Otherwise keep it and tell the user (it does not fail the CI pattern).
