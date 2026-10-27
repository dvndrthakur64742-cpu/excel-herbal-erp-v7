# GPS Office Preview Backend Compatibility — 24 October 2026

**Scope:** V8 development branch only. No WordPress deploy, no financial/stock/attendance mutations or schema changes.

## Live evidence
- GitHub V8 backend `RouteRegistry.php` implements authenticated GET `/workforce/gps/duty`.
- Office WordPress `/wp-json/excel-herbal-erp/v7/workforce/gps/duty` returned REST 404 `rest_no_route` (24 Oct 2026).
- Current Office web HEAD `7b6448fccdb170228877e0c70e789a2a942f2583`, Office canonical V7 backend HEAD `95a9e2806edef95257cd6b6aee6f1d56ca632d6b`.
- The Office REST namespace does still register GET `/workforce/gps/route` and POST `/workforce/gps/points`. Do **not** substitute attendance or infer duty from phone clock.

## Changes in this batch
1. On exact API 404 `rest_no_route`, the Flutter GPS service fails closed and displays a backend-version explanation.
2. No GPS point, permission prompt, or position request should be made when duty-status GET fails.
3. All other error classes retain their existing error behavior; 403 denial and unrelated business 404 are tested distinctly.
4. An explicit subsequent `sync()` may resume once the backend supplies an authoritative duty status.

## Verification and remaining gate
- Added focused tests to `flutter-app/test/gps_tracking_service_test.dart`.
- Existing 272/272 CI tests were certified at previous HEAD; do not reuse that pass label for this commit until new CI runs.
- **Backend mismatch remains unresolved on Office.** Frontend error messaging does NOT implement the missing server route.
- Before backend rollout: current WordPress verified database/files backup plus restore drill, active session/sanitization gate, source hash, real role-authenticated GET, API/Flutter contract, Android/browser GPS permissions and 10:30–17:00 device UAT.
- The `[owner-approved-office-v8-web-preview]` release marker must **not** appear in the commit message: this change is not approved for deployment.
