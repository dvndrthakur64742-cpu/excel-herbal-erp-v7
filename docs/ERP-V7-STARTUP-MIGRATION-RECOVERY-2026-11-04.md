# Excel Herbal ERP V7 — Startup and WordPress Migration Recovery

Date: 2026-11-04. Development branch only; **do not deploy automatically** to office.excelherbal.in.

## Evidence examined
- Connected Office administrator bootstrap GET succeeded on 2026-11-04 and included a valid business date, Asia/Kolkata timezone, timestamp and matching API contract metadata. This does NOT verify an individual employee login session.
- The live Office site still uses an older ERP PHP plugin and Flutter Web bundle, with missing new endpoints. Its reported source markers are not aligned. Production review remains issue #30.
- The existing Windows development environment D:/ERP7-Development ran localhost-only XAMPP. Initial native launcher health timed out on a cold request, followed by an HTTP 200 healthy synthetic-only response once services were warm.
- Local Apache/PHP logs from 2026-11-03 repeatedly showed WordPress dbDelta issuing invalid ALTER TABLE statements treating an entire compact comma-separated table definition as one column. This is direct local evidence of a migration formatter defect; not proof of the live employee startup error.

## Fix 1 — properly formatted WordPress schema declarations
- All 85 canonical compact table definitions retain their original SQL meanings and identifiers.
- Schema::dbDeltaLines splits on commas only at top level, preserving DECIMAL(14,2), compound indexes and quoted SQL defaults.
- Schema::install now supplies one column or index per line to WordPress dbDelta.
- Pure PHP tests cover every definition and malformed or nested examples. Run automatically from backend CI and Windows Quick QA.
- Do not force a schema reset or migration on hosted Office based solely on these results.

## Fix 2 — bounded, fail-closed Flutter bootstrap recovery
- GET /bootstrap alone may retry ONCE when it fails with a transient network error or HTTP 502/503/504, after a short delay.
- Never automatically retry an authentication/permission denial, malformed contract, 500 error, login request or a financial/stock mutation.
- API request reference (when supplied by the backend) is shown as a safe support reference on the startup recovery screen. No token or password is displayed.
- Retain fail-closed business-date, timezone and API-contract checks before navigation or posting.
- Flutter policy and integration widget tests exercise transient recovery, 401 logout, 403 fail closed, invalid business date and support reference clearing.

## Required before resolving live startup blocker
1. Verify exact failed request/error code and response from the affected employee session; never collect or expose passwords or access tokens.
2. Check live Flutter bundle and backend source/schema/version compatibility against a tested release candidate.
3. Complete isolated real WordPress+MariaDB and Flutter CI; verify authenticated desktop/mobile navigation with synthetic role accounts.
4. Establish production database+files backup, a tested restore and rollback, and reconcile the inactive Universal V15 plugin data ownership before explicitly authorised Office deployment.
5. Re-test the same existing Office URL with the affected employee; only then mark issue #30 resolved.

Local source changes and green CI are not a hosted production fix.
