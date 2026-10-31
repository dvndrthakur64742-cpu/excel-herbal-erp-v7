# Flutter / PHP contract blockers — 2026-10-31

## Evidence
Imported Flutter source comes from a historical 7.4.0-era UAT branch; canonical PHP plugin starts at 7.3.6-rc1, advancing to 7.3.7-rc1 for a new staging candidate.
- Dart dependency resolution and static analyzer passed on Flutter 3.38.5.
- After mapping legacy `../backend/` to canonical `../plugin/`, Flutter suite reported **208 passed, 24 failed**.
- Failed contract audits are in `privacy_authority_contract_test.dart`, `frontend_functional_navigation_test.dart`, `reports_account_ledger_contract_test.dart`, and `employee_dashboard_gps_contract_test.dart`. These are actual source contract differences, not missing test paths.

## Security and business discrepancies to reconcile
- Some older tests demand finer-grained employee contact/documents, salary and GPS permissions and explicit hierarchy guard methods not yet present in canonical PHP 7.3.6.
- Report and navigation route declarations from the later Flutter branch differ from the canonical PHP backend.
- GPS tests expect server-owned automatic duty tracking at fixed times; approved Excel Herbal rules specify GPS check-in/check-out plus **Head Office-approved exceptions**. Do not change approved business policy merely to satisfy a legacy test.
- Flutter version 7.4.0 and PHP v7.3.7-rc1 require verified actual REST contract compatibility, not just version-name matching.

## Test gating
GitHub Actions independently runs Flutter client unit/widget tests and produces an **unverified UAT-only Web artifact** after they pass. The separate cross-module contract audit continues to fail the workflow until the canonical backend, approved rules and Flutter client converge.
**A built Web artifact is NOT production ready**, and failed integration audits must never be ignored for deployment approval.

## Next actions
1. Document minimal runtime API capabilities required by each Flutter screen and role.
2. Add missing server-side granular permissions and privacy protections as backwards-compatible PHP migrations where approved.
3. Reconcile sales, invoice-before-payment, distributor price slabs and approval workflows with the nine approved business decisions.
4. Replace incompatible legacy assumptions with new acceptance tests for GPS check-in/out and Head Office exception approval.
5. Re-run full PHP, Flutter, MariaDB and synthetic Railway UAT E2E gates before release.
