# Excel Herbal ERP V8 — Authorized Multi-Branch Comparison & CSV Export

New read-only authenticated REST route:
`GET /reports/branch-compare?mode=week|month&date=YYYY-MM-DD&branches=2,3`
The optional `branches` filter defaults to **all effective authorized branches**
for the logged-in actor. The actor's server-derived company ID and branchIds
are the ONLY source of authority; user-submitted branch IDs can restrict but
NEVER expand scope. `reports.view` required. Maximum 12 branches per request
and 2,500 employee records per branch; fail closed rather than partial totals.

The route reuses the exact existing, canonical
`BranchPeriodControlReport::view` for EACH authorized branch. It does not
duplicate calculations, create a new ledger, or reinterpret posted sales.
All per-branch reports are checked for source company, branch ID, period,
read-only status, and never-verified external Cash/UPI flags before
aggregation. Posted Daily Order INR, Counter Sales INR, Stock PCS and signed
Points remain distinct units; current-vs-previous comparison uses complete
calendar weeks/months, NOT pace-adjusted current-to-date days.

**Privacy:** Regional multi-branch comparison NEVER exports employee-tagged
Cash-in-Transit GL, employee salary, margin, purchase costs, or customer data,
even when the actor has finance capability. The only employee information is
authorized employee name, employee ID and sales/stock/points/pending summary.

## Manager export

`GET /reports/branch-compare?...&export=csv` returns a REST JSON envelope
with `csv`, `filename`, `mime_type=text/csv`, authorized branch IDs,
and the same read-only warning. CSV is UTF-8 BOM Excel-friendly, RFC4180
double-quote escaped, and any leading-whitespace Excel formula trigger
`= + - @` is forced to inert text with an apostrophe. Negative numeric
points are legitimate values; they also are escaped for Excel safety.

CSV rows cover each authorized branch summary, its authorized employees
and a single combined total; no finance-only GL. Max 2 MB export size.
The Flutter Reports screen provides weekly/monthly regional views and
a Share CSV action, after refetching the export from the SAME authorized
server route and verifying returned branch IDs equal the displayed scope.

## Validation

- PHP 8.3/8.4 and GitHub-hosted Windows: precise financial sums,
  permissions, filtered scopes, wrong company/source, duplicate/tampered
  branch IDs, month/week periods, signed points, malicious CSV text.
- Disposable real V7 MariaDB: compare two authorized branches, one posted
  employee sale, pending closing, counter sales, points, original stock
  custody movement history; confirm no extra accounting/cash posting and
  no GL leak.
- Flutter UI compile/contract and branch selector regression.

This feature is DEVELOPMENT/UAT only. Production deployment, real WordPress
UAT, physical-device checks and PR merge remain separate approval gates.
