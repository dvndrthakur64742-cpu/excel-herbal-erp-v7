# Flutter UAT source integration — 2026-10-31

## Source provenance
The editable `flutter-app/` tree was restored from the existing GitHub branch
`codex/reports-date-export-workflow`, not reconstructed from compiled JavaScript.

## Safety changes
- `EH7_ENVIRONMENT=uat` defaults to the isolated Railway WordPress UAT API, **not** the live office host.
- A `production` release must explicitly use the canonical production URL.
- The ApiClient blocks every normal request, upload, private document download, and token refresh if the build's environment and API target are inconsistent.
- Tests assert safe UAT defaults and prohibit UAT-to-production endpoints.

## Build & QA
- `.github/workflows/erp-v7-flutter.yml` installs a pinned Flutter SDK, analyzes, runs Flutter tests, and generates a UAT-only Web artifact with SHA256 checksums.
- This imported Flutter app has `version: 7.4.0+740` in pubspec, while PHP plugin is `7.3.6-rc1`; contracts require actual integration verification. Do not infer interoperability from version strings alone.
- Backend now returns `business_date`, `business_timezone`, `server_timestamp`, `api_contract`, and `features.api_contract` in authenticated `/bootstrap`, matching Flutter startup validation.

## Release blockers
- Never upload UAT Web artifact to `office.excelherbal.in`.
- Run authenticated mobile login / refresh / bootstrap using **synthetic UAT identities**.
- Clean up / review old destructive Railway staged patch before configuring any Railway deployment.
- Production login remains blocked for employees with invalid WordPress links until individually verified and provisioned.
- Current PHP/Flutter tests are not a substitute for database-backed workflow, multi-browser, and mobile UX validation.
