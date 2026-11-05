# Office Flutter Web deployment handoff — review candidate (2026-11-03)

**Status: Built and independently verified, NOT DEPLOYED. This archive is the Flutter Web frontend only, not a WordPress V7/V15 plugin update.**

## Provenance

- Development source SHA: `0697c9e96fceb2c2af2b91ed0afc214dbfe5f6d3`.
- GitHub Actions PR merge checkout SHA: `9c49c7fd97657a1324bc81cd1346166d2df5929c`; this is intentionally different from the branch SHA.
- CI run: https://github.com/dvndrthakur64742-cpu/excel-herbal-erp-v7/actions/runs/41575632371
- GitHub artifact: https://github.com/dvndrthakur64742-cpu/excel-herbal-erp-v7/actions/runs/41575632371/artifacts/13203068713
- Artifact name: `eh7-office-flutter-web-REVIEW-ONLY`.
- Downloaded ZIP name: `excel-herbal-erp-flutter-web-REVIEW-0697c9e9.zip`.
- ZIP SHA-256: `490c55d8d466123b568b3c3348fac0d94096f3f6d2500c2428dd20dffaecc5f8`.
- ZIP size: 11,502,961 bytes.
- Independent ZIP CRC verification: PASS. ZIP includes 28 entries: **27 packaged app files** all matching `SHA256SUMS.txt`; the 28th entry is `SHA256SUMS.txt` itself. No missing/unlisted entries or checksum mismatches.
- An earlier artifact (SHA `0c12275d`) had a manifest that incorrectly included a hidden Flutter `.last_build_id` excluded by GitHub artifact packaging. **Do not use the earlier artifact**. This issue was fixed in workflow commit `0697c9e9`.

## Technical build configuration

- API URL: `https://office.excelherbal.in/wp-json/excel-herbal-erp/v7`.
- Base href: `/wp-content/uploads/eh7-flutter-web/`.
- Flutter SDK pinned by CI to 3.38.5.
- The `EH7_ENVIRONMENT=production` compiler setting is necessary for the current **host allowlist** to permit the Office domain. The Office WordPress site itself is a **development** site with existing data. The build contains NO bank secrets or test credentials.
- PWA strategy: none in the new build. Review existing browser/service-worker registration before switching to a new bundle; a cached old JS can continue to display the old error.
- The compiled `main.dart.js` includes the Office API URL and no Railway UAT API hostname.
- The Flutter application keeps fail-closed bootstrap validation: invalid/missing `business_date`, `business_timezone`, `server_timestamp`, or inconsistent API contract **blocks business posting**. New UI only improves the safe error message when an authenticated bootstrap request fails.

## Verified hosted environment (read-only, 2026-11-03)

- WordPress V7 plugin: **7.3.10-rc2 active**; Universal V15 15.0.0 inactive.
- API `/health` returns schema `7.3.12-prepaid-refund-evidence-1`, contract `7.3.12-contract-refund-evidence-1`, `environment=staging`, `staging_safety.sanitized=false`, an unverified source-head marker and nonzero active mobile sessions.
- WordPress Administrator-authorized GET `/bootstrap` returns valid business date **2026-11-03**, timezone `Asia/Kolkata`, valid timestamp, matching top-level and feature API contracts, 7 authorized branch records and complete navigation projections. **This does not prove another employee's login/bootstrap works** and should not lead to guessed token/session state.
- Existing hosted Web bundle `/wp-content/uploads/eh7-flutter-web/main.dart.js` still had an October 27, 2026 Last-Modified date at the read-only audit; it already targeted the Office V7 API but masked any bootstrap transport error with the generic startup error.
- The prior host backup setting referenced a September 5, 2026 backup path. **No new November 3 full website files+DB backup, restoration rehearsal or reliable Web folder rollback snapshot has been verified.**

## Hard blockers and safe promotion order

1. Obtain fresh **Hostinger full website file archive + database dump**, and verify readability/restore on a separate disposable environment. Keep a distinct backup of the old `eh7-flutter-web/` folder and record SHA-256 before any replacement.
2. Reconcile hosted source marker/version and database schema against the reviewed source; review 27 employee records, 7 branches, existing stock/journal rows and active sessions. **Do not reset data or revoke users merely to turn `sanitized` green.**
3. On the backed-up cloned site, use a fresh authorized test login to verify GET `/bootstrap`, date/timezone/contract, branch role restrictions, login → dashboard → logout, and previously observed startup-error behavior.
4. Confirm service-worker/cache behavior. Publish the entire verified build **atomically** to a versioned preview location; avoid partially overwriting JS/WASM assets. Never auto-publish this GitHub Actions artifact.
5. Smoke test on Chrome desktop/mobile and real Android. Never post real money, stock movements or payroll during first UAT.
6. Only after sign-off promote to the intended `eh7-flutter-web/` URL with immediate rollback capability and post-deploy validation.

## Deliverable limitation

This release candidate **fixes the presentation of startup failures**, not necessarily their underlying cause for every employee. The actual authenticated employee/session screenshot failure still requires user-scoped, authorized E2E diagnostics. No WordPress files, sessions, plugin installations, production payment records or business data were changed during this release build.
