# V8 Web startup failure vs V7 REST backend — diagnostic and fix (2026-11-02)

## Evidence

The user's screenshot of `https://office.excelherbal.in/wp-content/uploads/eh7-flutter-web/index.html` shows **"ERP startup temporarily unavailable / ERP startup data is unavailable"**, not a login screen. This UI deliberately blocks business posting when server business date, timezone, timestamp or API-contract bootstrap validation is invalid, or a bootstrap call fails.

A **read-only** inspection of the actual hosted static web bundle (served HTTP 200, last-modified **2026-10-27 06:04:55 GMT**, `main.dart.js` about 5.47 MB) confirmed:
- It contains exactly that recovery screen and bootstrap compatibility checks.
- It contains `https://office.excelherbal.in/wp-json/excel-herbal-erp/v7` as its API base URL; therefore this is **not** simply a wrong API hostname.
- Its static bundle predates the current development fixes. Merely updating the WordPress plugin does not update a Flutter web bundle stored under `wp-content/uploads/eh7-flutter-web/`.

The live WordPress V7 read-only health endpoint returns HTTP 200 with `version=7.3.10-rc2`, `schema=7.3.12-prepaid-refund-evidence-1`, and `api_contract=7.3.12-contract-refund-evidence-1`. WordPress timezone is `Asia/Kolkata` (UTC offset +5:30). It also returns `environment=staging`, **`staging_safety.sanitized=false`**, `source_head=local-integrated-v15-workflow-unverified` and nonzero active mobile sessions. No assumptions of a clean synthetic-only UAT should be made about this host.

**Root cause not yet conclusively identified** because the user's authenticated `GET /bootstrap` response is not available. Public health cannot prove the authenticated user's branch/role, session, or per-user bootstrap response. Do **not** reset sessions, use test credentials against active staff accounts, suppress the startup gate or invent a backend response.

## Development-only code fix (GitHub SHA `3885781d`)

The Flutter startup recovery UI previously used:

`app.bootstrapCompatibilityError ?? app.error`

When `bootstrap` was null, that always displayed "ERP startup data is unavailable" **even when the authenticated bootstrap request had actually failed with a safe API/network error**. This masked the actionable failure.

The new `AppState.bootstrapFailureMessage` prioritizes a safe request error if present, then reports the detailed bootstrap compatibility reason, then a generic fallback. The recovery UI uses that getter. **It does NOT modify `bootstrapReady`, data validation, posting controls, API host allowlist or the current session.** It only clarifies a blocked login/startup state.

New Flutter unit tests verify (1) network/API error visibility, (2) invalid business-date lockout, and (3) valid API contract/date/timezone acceptance. On **SHA `3885781d`**, all four GitHub workflows completed successfully: Flutter UAT, PHP/MariaDB staging, isolated WordPress, and Windows QA.

## Deployment and E2E gates still pending

1. Obtain and verify a full hosted backup and restoration procedure before modifying office site files. Record the currently hosted static Flutter JS bundle checksum, source build flags, V7 plugin/source hash and schema version.
2. Build a fresh Flutter Web artifact for the *intended* API target/environment. Keep `AppConfig.unsafeApiTarget` unchanged. Never secretly retarget a UAT build to an office host with active employee sessions. A production-targeted build must be explicitly authorized and tested first.
3. Publish only with a **versioned isolated release/rollback** of the entire Flutter `build/web` directory and a cache invalidation strategy; partial JS assets or stale service workers can break startup. Do not replace the hosted uploads folder based on code passing CI alone.
4. On a test identity with authorized branch access, inspect authenticated `/bootstrap`: `business_date` valid YYYY-MM-DD, `business_timezone`, parseable `server_timestamp`, matching top-level and `features.api_contract` fields, navigation lists, and branch IDs. **Do not copy bearer tokens into chat/logs.**
5. Confirm authenticated login → bootstrap → branch-scoped dashboard → logout/revocation, then scheduled attendance and stock workflows. Recheck 403 branch isolation. No real customer data or finance posts for UAT.
6. Real-device/mobile browser verification, service worker cache refresh, data migration rehearsal and rollback sign-off before calling the hosted issue resolved.

**No website file updates, production database writes or user session changes were made in this diagnostic/code-fix slice.**
