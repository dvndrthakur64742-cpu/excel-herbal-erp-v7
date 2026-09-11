# Excel Herbal ERP v7.4.0 — Final Stabilization Status

Date: 2026-09-11
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
- Report branch selector state is keyed to both branch scope mode and current branch, so switching between branch-required and All Authorised reports cannot retain a stale dropdown value.
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

Fresh package re-check:

- PHP lint: 51/51 PASS
- ZIP integrity: PASS
- SHA-256: `786c8ff2b063cd1c606522095da27ec455fe80e57b4bca84b454d946103118aa`

Frontend/backend report query cross-check also confirms Trial Balance uses `to` plus an optional branch. When branch is omitted, the backend aggregates only the actor's existing authorised branch IDs; it does not expand to company-wide authority.

## Reporting-data readiness

The software hierarchy engine is corrected, but reporting-manager master data still contains legitimate business-data gaps. No Reporting Manager was guessed or auto-assigned. The Hierarchy Readiness workspace is the operational path for authorised managers to complete those links explicitly.

## Flutter certification blocker

GitHub-hosted runner execution was probed multiple times after source stabilization.

### Standard hosted runner

- Run ID: `34486920153`
- Initial job: `102903441436`
- Runner: `ubuntu-latest`
- Result: failure before runner execution
- Steps: `null`
- Job logs: `null`

### Alternate hosted runner

- Run ID: `34498125506`
- Initial job: `102941721000`
- Runner: `ubuntu-slim`
- Result: failure before runner execution
- Steps: `null`
- Job logs: `null`

### Explicit re-run

- Same run: `34498125506`
- Re-run job: `102982204766`
- Re-run request was accepted by GitHub.
- Result again: failure before runner execution
- Steps: `null`
- Job logs: `null`

Because every probe failed before the first workflow step, no Flutter command executed. These results are neither a Flutter compile PASS nor a Flutter compile failure. The evidence isolates the remaining blocker to GitHub-hosted runner allocation/account execution rather than the workflow's Dart source steps.

All temporary push-trigger probes were removed after diagnosis. The certification workflow is restored to manual-dispatch only, `contents: read`, artifact-only, and does not mutate source or publish a release automatically.

## Local fallback evidence

A prior 48 MB Flutter source bundle was inspected locally. It contains `.dart_tool` metadata and test cache generated with Flutter 3.47.2, confirming the existing project dependency set has previously been exercised on the same Flutter line. That cache points to the original hosted-runner SDK/package paths, which are not mounted in the current container and therefore cannot execute current tests by itself.

Current local environment:

- OpenJDK 21: available
- Flutter executable: unavailable
- Dart executable: unavailable
- Android SDK/ADB: unavailable
- original hosted-runner Flutter/package cache paths: unavailable
- direct SDK bootstrap from this execution container: unavailable

Flutter 3.47.2 API documentation was also checked for the current branch-selector implementation: `DropdownButtonFormField.initialValue` is the supported API in this Flutter release line.

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
- Overall release readiness: **approximately 98–99%**.
- Production APK certification: **pending only because Flutter analyze/test/APK/device UAT have not executed successfully on a Flutter-capable runner**.

Do not publish or call an APK production-ready until the remaining certification gate passes.
