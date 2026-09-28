# Excel Herbal ERP v7 — Production Readiness P1

Status: BUILD/STAGING CANDIDATE. Do not deploy or merge to a production release branch until every BLOCKING gate below is verified.

## Current source baseline

- Working branch: `codex/erp735-document-integration`
- Production base branch: `v740-business-completion`
- Production API target: `https://office.excelherbal.in/wp-json/excel-herbal-erp/v7`
- Flutter release version: `7.4.0+740`
- Backend correction plugin: `7.3.5-rc1`

## BLOCKING gates

### 1. CI and build certification

- [ ] GitHub-hosted backend PHP lint passes.
- [ ] GitHub-hosted 24 backend regression cases pass.
- [ ] GitHub-hosted route/contract static checks pass.
- [ ] Windows self-hosted Flutter `pub get` passes.
- [ ] Windows self-hosted Flutter `analyze` passes with no errors.
- [ ] Full Flutter test suite passes.
- [ ] Release web compile passes against the production API define.
- [ ] Production web invariants pass: production API URL, no UAT banner, required HTML metadata.
- [ ] Android release APK compiles.
- [ ] Production Android APK/AAB signing is verified before distribution.

### 2. WordPress host readiness

- [x] WordPress core checksums verified.
- [x] `WP_DEBUG` is false.
- [x] WP-Cron spawn test returns HTTP 200.
- [ ] Define `WP_ENVIRONMENT_TYPE` explicitly as `production` before final go-live.
- [ ] Define `DISALLOW_FILE_EDIT` as `true` before final go-live, after confirming the operational update process.
- [ ] Review pending plugin updates on staging before applying them to the ERP host.
- [ ] Confirm OpenSSL and fileinfo extensions are available in the actual PHP runtime.
- [x] Confirm all ERP tables use InnoDB. Verified 73 ERP tables on 2026-09-17.
- [x] Confirm MySQL `max_allowed_packet` provides adequate headroom for private HR document storage. Verified 1,073,741,824 bytes (1 GiB) on 2026-09-17.
- [ ] Confirm PHP upload/post limits provide adequate headroom for private HR document storage.

### 3. Backup and recovery

- [ ] Take a complete database backup.
- [ ] Back up current ERP plugin files and deployed Flutter web bundle.
- [ ] Back up the `eh7_document_key` independently and securely with the database recovery package.
- [ ] Perform a restore drill on staging and prove the application boots and encrypted documents remain readable.
- [ ] Record backup timestamp, restore timestamp, operator, and checks performed.

### 4. Schema and migration

- [x] Confirm schema version `7.3.5-business-fixes-1` on the connected office ERP host.
- [x] Confirm `salary_revisions`, `payroll_editors`, and `private_documents` tables exist.
- [x] Confirm payroll calculation/version columns and employee/candidate HR private-file references exist.
- [x] Confirm `eh7_document_key` exists and is non-empty without reading or exposing its value.
- [ ] Run migration twice on a staging clone to prove idempotency.
- [ ] Inspect migration errors and verify document-key preservation through a restore/migration drill.

### 5. Business logic and concurrency

- [ ] Exercise all 21 payroll calculator cases and 3 service guard cases in the target PHP/MySQL environment.
- [ ] Test concurrent overlapping payroll generation attempts.
- [ ] Test concurrent employee transfer attempts.
- [ ] Test transfer vs payroll generation concurrency.
- [ ] Test salary approval vs payroll generation concurrency.
- [ ] Verify maker-checker rules for payroll, finance reversals, inventory adjustments, salary revisions and other approval workflows.
- [ ] Verify historical salary snapshots and payroll calculation JSON remain immutable after approval/payment.

### 6. Security and authorization

- [ ] Verify REST authentication for valid, expired and revoked sessions.
- [ ] Verify 401 vs 403 handling end-to-end.
- [ ] Verify branch-scope fail-closed behavior, including zero-authorized-branch accounts.
- [ ] Verify idempotency replay/duplicate-write protection for every critical mutation family.
- [ ] Verify reporting category and additional/temporary designation never escalate authority.
- [ ] Verify acting-duty delegation is branch/action/date constrained and preserves maker-checker rules.
- [ ] Verify private employee/candidate document download requires an active authorized ERP identity.
- [ ] Verify inactive/revoked users cannot access private documents.

### 7. Legacy document migration

- [ ] Inventory legacy public HR/candidate media URLs.
- [ ] Re-upload required documents through private endpoints.
- [ ] Verify downloaded private copies match originals before retiring legacy records.
- [ ] Check all media references before deleting public originals/thumbnails/CDN copies.
- [ ] Re-test retired legacy URLs without authentication.

### 8. Flutter functional and responsive UAT

- [ ] Test 360px and 390px mobile widths.
- [ ] Test 768px tablet width.
- [ ] Test 960px responsive boundary.
- [ ] Test 1366px desktop width.
- [ ] Verify Home, My Work, Sales, Inventory, Purchase, Finance, Payroll/Performance, Reports, Organization, Communication and Administration navigation.
- [ ] Verify Daily Order morning → approval → issue → evening → final-post flow.
- [ ] Verify attendance, GPS lifecycle, leave and field-visit flows on a physical device.
- [ ] Verify authenticated HR document download/open/share on Android and Web where supported.

### 9. Incomplete feature policy

Do not expose a feature as production-ready merely because route constants or UI shells exist.

- [x] Advanced salary-structure APIs are production-hidden. `CompensationWorkspace` is compile-time UAT-only.
- [x] Reward/incentive/penalty workflows are production-hidden. `CompensationWorkspace` is compile-time UAT-only.
- [x] Promotion workflow is production-hidden. `CompensationWorkspace` is compile-time UAT-only.
- [ ] Any unimplemented CRM / PO-GRN / manufacturing / offline-sync functionality is clearly outside the v7.4.0 production scope and not represented as complete in release notes/user-facing navigation.

### 10. Pilot and release approval

- [ ] HR validates employee lifecycle, leave and payroll policy configuration.
- [ ] Accounts validates payroll, journal integrity, closing/reversal behavior and historical data policy.
- [ ] One pilot branch completes real UAT without critical defects.
- [ ] Production web artifact SHA-256 recorded.
- [ ] Signed APK/AAB SHA-256 recorded.
- [ ] Final release notes list known limitations and rollback procedure.
- [ ] Explicit owner approval received before deployment/merge/go-live.

## Current known non-blocking web findings

- ERP web source includes `<html lang="en">`, a production meta description and `noindex,nofollow,noarchive`.
- Production web workflow targets `v740-business-completion` and watches `flutter-app/**`.
- Lighthouse/browser audit should be repeated on the newly compiled production web artifact; current deployed page results may reflect an older web bundle.
- Large Flutter JavaScript payload and main-thread execution should be tracked as a performance optimization item after correctness/security gates, unless pilot-device performance is unacceptable.

## Change control

No production deployment, database migration, plugin update, WordPress configuration mutation, PR merge, or release publication is authorized by this checklist alone. Each production-affecting batch requires explicit owner approval.
<!-- UAT deployment certification trigger: precise WordPress window-selection fix validated by CI on 2026-09-28. -->
<!-- UAT deploy trigger after exact ZIP picker certification: 6a6227157eae18107de30ff449ae0193dd333195 -->
<!-- UAT deploy trigger after runtime-smoke HOME fix certification: aac346f87c5d4c02b1ae25d84c8f69a44f28ffb8 -->
<!-- UAT deploy trigger after atomic identical-web marker certification: a7f2b2d54d086f3380ae850deaa357374744af82 -->
