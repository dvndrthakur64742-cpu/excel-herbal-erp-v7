# B2B WordPress Staging REST Admission — Development Only

## Motivation

The B2B V8 UAT writer, Cash/UPI tender verification, canonical V7
AccountingService/StockService and MariaDB MVCC branch/day snapshot run
successfully in isolated `v8_test` CI. **None of these financial writers has
been made reachable through the production WordPress REST API.**

This milestone adds a deliberately smaller **WordPress staging diagnostic**
that exercises the real V7 REST route registry and dispatcher and server-side
branch/capability rules. It checks *structural* readiness only, never executes
sale posting or touches accounting balances.

## Endpoint and admission controls

GET `/wp-json/excel-herbal-erp/v7/development/b2b-staging-readiness?branch_id=N`

All conditions must hold **on registration AND on every request**:

1. `wp_get_environment_type() === 'development'`.
2. An explicit opt-in constant `EH8_ENABLE_B2B_STAGING_REST_PROBE === true`.
3. The connected **actual** WordPress `$wpdb->get_var('SELECT DATABASE()')`
   must equal `v8_test` (not merely a supplied DSN or option).
4. A safe WordPress table prefix.
5. Authenticated active V7 actor from `ActorResolver::current()`.
6. `finance.accounting.view` capability and effective authorized branch from
   `Guard::branch()`, with actor company inferred server-side.

If items 1–4 are false the diagnostic route is **not registered**; even a
stale callback rejects the request at the service layer. If role/branch is
unauthorized the service refuses *before* querying source metadata. The
separate global feature flag reports whether the probe is actually exposed,
instead of pretending staging diagnostics are available on production.

The probe reads *only* `information_schema.TABLES` metadata for the 14
canonical V7 + UAT staging sources already used by the snapshot. It verifies
all tables are present and have `InnoDB` engines. A missing table or
nontransactional engine makes `structural_preflight_possible=false`.

It returns **no sale totals, customer identities, cash details, UPI receipts,
stock units, journal lines, secrets or credentials**. Metadata readiness
does NOT approve a transaction, financial reversal, bank proof, GST/HSN
invoice, stock issue, deployment or snapshot. It does not execute a snapshot.

## Security and test coverage

- WordPress route-registration smoke: production/staging/misconfigured
  development and unsafe database prefix = **no diagnostic route**.
- Correct disposable WordPress development database: exactly one authenticated
  **GET** registration, no B2B POST counterpart.
- Existing V7 `ApiContract::validate` rejects malformed/missing branch IDs.
- Existing `ApiDispatch::dispatch` invokes only the read-only probe; tests
  use canonical V7 Actor/Guard classes, not a new account subsystem.
- Manager with accounting permission may inspect assigned branch; RM
  (reports only), BM, FSE, and cross-branch actors fail closed.
- Missing/non-InnoDB 14-table manifest cannot be falsely marked ready.
- Database errors fail closed; no writes, messaging or third-party calls.
- CI: Linux PHP 8.3/8.4 and Windows PHP 8.4 run this regression, alongside
  disposable real MariaDB snapshot and existing Flutter UI suites.

**Limits:** This validates staging admission/code paths with a WordPress
routing stub; it is **not** proof of a deployed WordPress environment or
real-browser/mobile user journey. Before a live staging deployment, create a
truly disposable `v8_test` WordPress database and isolated host, rehearse
schema installation/migration and rollback, and run real HTTP login/role UAT.
Do **not** set the opt-in constant on production WordPress or on a copy of
real employee/customer data.

## Still blocked

B2B retailer sale POST on WordPress; independent production bank provider
and Cash handover; GST/HSN/discount pricing business policy; refund/reversal;
real WordPress staging role/device tests; owner release approval.

**No production deployment, no PR merge and no live DB modifications.**
