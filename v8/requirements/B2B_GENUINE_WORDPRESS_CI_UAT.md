# B2B Genuine WordPress Authentication and HTTP UAT — Isolated GitHub CI

## Why

The previous V8 `18/18` loopback HTTP smoke test used real PHP HTTP transport
and V7 route/response logic but **synthetic WordPress authentication and DB
adapters**. The real Railway project named "Excel Herbal ERP - Isolated UAT"
has an environment called `production`, pending changes and a WordPress
service sourced from a branch **other than** the V8 Draft PR #25 head.
Read-only inventory did not establish its WordPress DB as disposable
`v8_test` or its installed source as the latest V8 build. **No connection,
deployment, migration, login, or financial test on that Railway environment
was performed.**

## New genuine WordPress test

`.github/workflows/v8-b2b-real-wordpress-ci.yml` creates an **ephemeral
GitHub-hosted runner** with an isolated MariaDB 11.4 container, fresh
`v8_test` database and real WordPress core. It activates the actual ERP V7
plugin, runs its canonical schema migration only on this disposable database,
and loads **isolated UAT SQL prerequisites** from this repository.

`v8/backend/tests/b2b_real_wp_seed.php` refuses any other database,
non-development WordPress or nonempty ERP master tables. It seeds four fake
WordPress accounts linked to four fake ERP identities: RM with accounting
permission, BM, FSE and RM assigned another branch, with two branches.
Generated passwords live only inside the ephemeral workflow runner.
No actual employee, bank, retailer, tender, salary, stock or journal data
are imported.

`v8/backend/tests/b2b_real_wordpress_http_smoke.py` starts the real
WordPress application with a loopback-only PHP built-in web server (routing
pretty `/wp-json` paths through genuine WordPress REST internals).
It performs real `MobileAuth::login` WordPress password verification,
real `ActorResolver` ERP employee/company/branch lookups and
`BranchAuthority` checks, and calls the real REST callback using minted
Bearer tokens. It tests 401 unauthorized, BM/FSE 403 forbidden,
cross-branch refusal, malformed/absent branch 422, actual 200 with 14
InnoDB structural sources and all payment/posting flags false,
POST route not present, token logout revocation and cleanup.

**This tests genuine WordPress implementation but only on a fresh
CI-owned local host. It is not a deployed remote Railway or office test.**
The container is destroyed after CI. It does not post B2B financial transactions
or prove real UPI bank payments or cashier handovers.

## Remote staging release gate

A remote WordPress test is blocked until a separate developer environment
is verified with isolated `v8_test`, source head matching Draft PR,
fresh synthetic identities, and owner approval of any deployment.
Never run `.github/scripts/b2b-dev-http-role-uat.ps1` against
`office.excelherbal.in` or the ambiguous Railway `production` environment.

Green UAT does NOT authorize new canonical WordPress B2B posting endpoints,
GST/HSN changes, refunds, production migration, or PR merge.


## Subsequent security batch: real WordPress identity revocation and schema-failure HTTP checks

The real WordPress CI additionally exercises **the same already-issued
Finance Bearer token** after the underlying MariaDB security state changes:

1. Introduce an explicit `finance.accounting.view` **deny** through the
   actual ERP `employee_capability_overrides` table: next HTTP request must
   return 403. Restore the override; next HTTP request succeeds without login.
2. Deactivate the assigned branch: existing authenticated session must lose
   effective branch authority immediately (403). Restore synthetic branch.
3. Deactivate the synthetic ERP employee: old bearer must be denied at
   `MobileAuth` / active-employee JOIN (401). Restore synthetic employee.
   **Important:** this confirms inactivation blocks access while inactive;
   it does not certify irreversible session revocation across reactivation.
   That lifecycle policy requires a separate review and approval.
4. Temporarily rename the otherwise-empty `v8_b2b_payment_intents_uat`
   table. The genuine WordPress metadata query must produce
   `missing_source_table_count=1` and
   `structural_preflight_possible=false`; restore exact table identity.
5. A guarded `assert_restored` WP-CLI command checks the original four
   synthetic active employees, two active branches, absence of a finance deny,
   and restored staging payment-intent table at the end.

The only tool allowed to apply these changes is
`v8/backend/tests/b2b_real_wp_security_mutation.php`: it refuses execution
outside GitHub Actions + WP-CLI + WordPress `development` + exact runner
installation root + `v8_test`, and validates the expected fake company,
employee and branch identities and population sizes before every mutation.
Each mutation uses an explicit allowlist; no user/customer/tender/journal/
inventory production rows are created or changed.

These checks run inside the existing genuine WordPress CI workflow,
**not on Railway or a live WordPress installation**. They are security
regressions, not proof that any real external bank or cashier has verified
financial settlement.
