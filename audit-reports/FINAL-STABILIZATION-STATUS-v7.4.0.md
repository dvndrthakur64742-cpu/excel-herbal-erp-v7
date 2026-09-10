# Excel Herbal ERP v7.4.0 — Final Stabilization Status

Date: 2026-09-10
Branch: `v7-hierarchy-gps-reporting-dashboard`
Backend runtime: v7.3.2 / API contract `7.3.2-contract-1`

## Source completion

The requested hierarchy/reporting/GPS/price-distribution/role-dashboard correction scope is source-complete.

Completed and locked by source invariants/regression coverage:

- Reporting Manager is separate from Reporting Category.
- Reporting Category is grouping only and never grants authority.
- Additional/Temporary Designations do not inherit or expand authority.
- Additional/Temporary Designation active-state normalization handles boolean/integer/string API values safely.
- Reporting Manager changes require an audit reason and use the existing server cycle/branch-authority protections.
- Team Operations includes branch-scoped Hierarchy Readiness for Field Executive, ASM and SM reporting links; no manager is auto-assigned.
- Duty GPS lifecycle is server-owned and automatic; business UI has no manual Start/Stop route controls.
- GPS Team/Route visibility remains hierarchy + authorised-branch scoped.
- Price Distribution retains exactly: Sale Price, HO Amount, BM Profit, Salary Fund, Expense, Points.
- Price Distribution and Trial Balance can use All Authorised Branches without expanding the server-projected authorised branch IDs.
- Sales/Purchase/Stock/Finance reports remain branch-required.
- Home management dashboard requires both Team projection and `reports.view`.
- Reports-only/accounting-only profiles do not gain Team management dashboards.
- ERP Tools user-facing exposure is replaced by My Account & Duty and technical maintenance/diagnostic controls are not exposed there.
- Zero authorised branches fail closed at the app root and defensively in `AppState` capability/navigation projection.
- Excel Herbal logo and brand theme are used across the stabilized login/shell surfaces.
- Central business/security UI errors and targeted administration/profile copy are standardized.
- Mandatory app-update enforcement honors the backend `force_update` contract, with `update_required` retained only as compatibility fallback.
- Flutter API paths are checked against the backend RouteRegistry before Flutter tooling runs.
- v14 code/module/schema was not merged.

## Backend/live verification

Production backend v7.3.2 was verified live during stabilization:

- health/version contract correct;
- Price Distribution live with the exact six approved fields;
- GPS Team live with `manual_start_allowed=false` and `manual_stop_allowed=false`;
- fake/out-of-authority branch requests rejected;
- invalid reporting-category filters rejected.

Fresh package re-check on 2026-09-10:

- PHP lint: 51/51 PASS
- ZIP integrity: PASS
- SHA-256: `786c8ff2b063cd1c606522095da27ec455fe80e57b4bca84b454d946103118aa`

## Reporting-data readiness

The software hierarchy engine is corrected, but reporting-manager master data still contains legitimate business-data gaps. No Reporting Manager was guessed or auto-assigned. The Hierarchy Readiness workspace is the operational path for authorised managers to complete those links explicitly.

## Flutter certification blocker

A single controlled GitHub Actions certification attempt was made after source stabilization:

- Run ID: `34486920153`
- Event: push (one-shot trigger only)
- Result: failure before runner execution
- Job: `build`
- Steps: `null`
- Job logs: `null`

Therefore no Flutter command executed in that run. This is neither a Flutter compile PASS nor a Flutter compile failure.

The one-shot push trigger was removed immediately after the diagnostic run. The certification workflow is restored to manual-dispatch only, `contents: read`, artifact-only, and does not mutate source or publish a release automatically.

The current execution environment also has no Flutter/Dart SDK or Android SDK, and direct external SDK download is unavailable here, so it cannot substitute for the failed GitHub runner.

## Remaining certification gate

When a Flutter-capable runner is available, execute exactly one controlled certification sequence:

1. `python3 tool/finalize_hierarchy_gps_frontend.py`
2. `python3 tool/verify_api_paths_against_backend.py`
3. `flutter pub get`
4. `flutter analyze --no-fatal-infos --no-fatal-warnings`
5. `flutter test`
6. build the v7.4.0 UAT APK against `https://office.excelherbal.in/wp-json/excel-herbal-erp/v7`
7. verify APK non-empty + SHA-256 artifact
8. final mobile/tablet/desktop visual UAT

## Completion statement

- Backend/live correction: **100% complete**.
- Requested source/business-logic correction scope: **100% complete**.
- Source regression/static stabilization: **100% complete for the requested scope**.
- Overall release certification: **not 100% yet**, because Flutter analyze/test/APK/device UAT have not executed successfully on a Flutter-capable runner.

Do not publish or call an APK production-ready until the remaining certification gate passes.
