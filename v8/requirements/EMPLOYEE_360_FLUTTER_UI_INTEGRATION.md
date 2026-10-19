# Employee 360 Flutter Web/Android UI — v0.14 development milestone

## Delivered source integration

- Existing Organization → Employees record bottom sheet has a new **Sales, Points & Stock** action. This pushes a standalone `Employee360Screen` instead of a duplicate employee master.
- Authenticated read-only GETs use existing canonical backend: `/organization/employees/{id}/360` and `/organization/employees/{id}/360/register?type=sales|stock`, with 25-row bounded server-side pagination.
- Responsive tabs show **Monthly Summary**, **Sales Register**, **Employee Stock Register**, **Attendance**, and (only if the API says `visible=true` *and* the actor has `finance.accounting.view`) **tagged employee Journal**. GPS Route uses existing protected route and is gated by `workforce.gps.team.view`.
- Reuses current date-range selection (max 366 days), `RecordsList`, Flutter API authentication and backend branch/hierarchy checks. Failure/retry and source annotations are displayed rather than fake zeroes.
- Fields such as purchase cost, salary allocation, account mapping or B2B posting controls are not created by this UI. The **employee dashboard is not edited**. The separate employee profile intentionally shows aggregate sales money and points, as previously approved.
- Important: backend has **no trustworthy Employee Cash Remittance ledger yet**; the UI does not claim branch cashier receipt or zero outstanding. Existing GPS route lacks a server-controlled employee manual switch; no manual toggle was added.

## Files

- `flutter-app/lib/screens/organization/employee_360_screen.dart` (new)
- `flutter-app/lib/screens/organization/organization_screen.dart` import (edit)
- `flutter-app/lib/screens/organization/organization_employees.dart` on-profile action (edit)
- `flutter-app/lib/core/api_paths.dart` route builders (edit)
- `flutter-app/test/employee_360_ui_contract_test.dart` contract tests (new)

## Verification gates

The source is reviewable in the **development** branch; **not deployed**. The Flutter/Dart SDK is absent from the local build container, so no successful Flutter analyzer, build or widget-test execution is claimed. The Windows self-hosted GitHub runner previously failed before any PHP regression because `php` was missing from PATH. Browser/device UAT remains required.

The weighted ERP estimate is unchanged at about **15% operational readiness** until the page is Flutter-compiled, API-endpoint-backed and tested in an actual development environment. This is a larger user-visible integration step, but not yet a production-delivered screen.
