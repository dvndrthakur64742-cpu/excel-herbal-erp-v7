# Excel Herbal ERP v7.4.0 — Production Readiness Gates

Status: **NOT production approved yet**  
Working branch: `codex/erp735-document-integration`  
Production base: `v740-business-completion`

This checklist is intentionally fail-closed. A release is production-ready only when every required gate below is evidenced as PASS. No item in this document authorizes deployment, database mutation, PR merge, plugin update, or data migration by itself.

## Gate 1 — Source verification

Required before merge/release:

- `ERP correction verification` completes successfully on the exact release commit.
- PHP 8.1+ runtime check passes with OpenSSL and fileinfo available.
- PHP lint passes for backend source and tests.
- 33 backend regression cases pass (21 payroll fixtures + 3 payroll service guards + 6 transaction/idempotency primitive checks + 3 bearer-header compatibility checks).
- Route/contract static checks pass.
- `flutter pub get` passes.
- Pinned Flutter dependency resolution remains stable after `flutter pub get`.
- `flutter analyze` passes with no blocking issues.
- Full Flutter test suite passes.
- Release-mode web compile passes.
- PR remains draft until these checks are green.

### P1 source/CI evidence — 2026-09-17

`ERP correction verification` run `35209886816` completed successfully on source head `4609bb0d3ce0426706ac4a2861e16336e4327cad` before this evidence-only documentation update:

- pinned Flutter 3.44.9 dependency lockfile stability: PASS
- Flutter analyze: PASS
- full Flutter test suite (126 tests): PASS
- production Web compile + metadata/API/UAT-marker invariants: PASS
- PHP 8.3.33 source lint: PASS
- 24 backend regression cases: PASS
- route/contract static checks: PASS

### Runner constraint verified 2026-09-17

A GitHub-hosted Ubuntu verification attempt failed before any job step was allocated (`runner_id=0`, no recorded steps; job log blob unavailable). Because hosted capacity is not currently usable for this repository/account, correction verification remains on the approved Windows self-hosted runner. The self-hosted runner must therefore run as a Windows service so CI does not depend on an open PowerShell window.

## Gate 2 — Feature exposure

Production must expose only implemented server-authorised features.

- Existing backend capabilities are the authority for visible modules/actions.
- Advanced salary structure, rewards/incentives and promotion workspaces remain hidden unless the backend explicitly advertises their exact capabilities.
- The current 7.3.5 backend capability list does not advertise `salary.*`, `rewards.*` or `promotion.*`; the Flutter Compensation tab is therefore fail-closed with the current server.
- Do not add those capabilities until the corresponding backend workflows, maker-checker rules, persistence, audit and regression tests are complete.
- Do not describe CRM, manufacturing, offline sync, advanced compensation or PO/GRN as production-complete unless separately implemented and certified.

## Gate 3 — WordPress staging prerequisites

### Office environment baseline verified 2026-09-17

- WordPress: 7.1
- PHP: 8.3.33
- ERP plugin health endpoint: 7.3.5-rc1
- API contract: 7.3.5-contract-1
- Installed schema: `7.3.5-business-fixes-1`
- Private document encryption-key option: present (value must never be exposed in logs/reports)
- Setup Assistant: 1.7.1
- WordPress core checksums: verified across 3,338 core files
- WP-Cron spawn test: PASS (HTTP 200)
- Database: MariaDB 11.8.9
- Transaction isolation: `READ-COMMITTED`
- Default storage engine: InnoDB
- ERP tables: 73 total / 73 InnoDB / 0 non-InnoDB
- `max_allowed_packet`: 1,073,741,824 bytes (1 GB)
- `WP_DEBUG`: false
- `WP_ENVIRONMENT_TYPE`: not explicitly defined
- WordPress therefore currently reports the runtime environment as `production` by default; this does **not** mean the ERP project is production/live. The ERP remains in build/UAT stage.
- `DISALLOW_FILE_EDIT`: not explicitly defined
- WordPress Site Health reports the Authorization header as invalid/recommended. The security batch found that the fallback parser existed but `MobileAuth::user()` and `logout()` still read only `HTTP_AUTHORIZATION`; the branch now routes both through the shared parser and the disposable MariaDB gate exercises redirect/direct header paths plus login, refresh rotation and logout revocation. A real staging/mobile HTTP forwarding smoke test is still required before production.

### ERP diagnostics baseline

Read-only administration diagnostics returned `healthy`:

- employees: 27 total / 27 active
- employees without login: 9 (operational review item, not automatically an error)
- duplicate normalized mobiles: 0
- unbalanced journals: 0
- orphan journal lines: 0
- negative stock balances: 0
- active employees without open branch history: 0
- orphan sessions: 0
- stale completed idempotency records: 0

### P3 read-only security recheck — 2026-09-18

The connected office environment was rechecked without writes:

- WordPress 7.1 / PHP 8.3.33 / MariaDB 11.8.9.
- Runtime environment still reports `production` because `WP_ENVIRONMENT_TYPE` is not explicitly defined.
- `DISALLOW_FILE_EDIT` is still not explicitly defined.
- Abilities API exposes only three core read-only abilities; no backup or staging ability is available.
- `eh7_document_key` is present and non-empty without reading or exposing its value.
- Schema remains `7.3.5-business-fixes-1`; no schema migration error option is present.
- Private encrypted blobs: 0; employee documents: 0; candidate documents: 0.
- Active mobile sessions: 15. No real session was mutated by this audit.

### P2 hardening blockers confirmed 2026-09-17

- No connected WordPress backup plugin is present. Host-level/database backup and restore proof is still required before plugin/config changes.
- The WordPress connector can read but cannot write `wp-config.php`; `WP_ENVIRONMENT_TYPE` and `DISALLOW_FILE_EDIT` therefore require a controlled host-level configuration change after backup/restore proof.
- WordPress 7.1 Abilities API exposes only core site/user/environment read abilities; no Hostinger backup or staging ability is available through the connected API.

Before production:

1. Create a fresh full database backup and plugin/files backup.
2. Keep an independent protected backup of the `eh7_document_key` option with the matching database backup.
3. Prove restore on a staging copy before production cutover.
4. Define `WP_ENVIRONMENT_TYPE` appropriately for each environment (`staging` during controlled UAT, `production` only at final production cutover).
5. Set `DISALLOW_FILE_EDIT` to true for production after confirming operational access for controlled deployments.
6. Confirm PHP OpenSSL + fileinfo and upload limits for private documents. Database engine and packet headroom are already above the documented minimum baseline.
7. Re-confirm schema `7.3.5-business-fixes-1` after any staging migration and inspect migration errors.
8. Verify the private document encryption key is recoverable only with the matching backup.

No WordPress configuration write should be made directly on the production-classified site before backup/restore proof.

## Gate 4 — Staging business/data validation

Must be executed against a controlled staging database:

- Payroll working-day policy confirmed by HR/Accounts.
- Exact paid/unpaid leave type configuration confirmed.
- Historical salary baseline/revisions reviewed through independent maker-checker.
- 21 payroll calculator cases + 3 service guard cases + 6 transaction/idempotency primitive checks + 3 bearer-header compatibility checks pass in CI.
- Real MySQL concurrency tests pass for overlapping payroll generation, concurrent transfers, transfer vs payroll generation, and salary approval vs generation. CI primitive tests do **not** replace this multi-session MariaDB staging gate.
- Failed SQL transaction rollback verified.
- REST authentication, branch scoping and idempotency verified.
- Zero-authorised-branch state remains fail-closed.
- Employee transfer/history ambiguity cases fail safely.
- Payroll editor cannot approve a payroll they edited.
- Approved/paid historical payroll is never silently recalculated.

### P2 runtime evidence — 2026-09-17

- Real authenticated branch-scope check: PASS. A read against branch `999999`, outside the current actor's effective authority, returned HTTP 403 with `branch_forbidden`.
- Real idempotency replay check: PASS using the transfer-accounting repair path only after its read-only preview reported `repairable=0` and `blocked=0`.
- The same payload and idempotency key were submitted twice; both returned the same zero-repair result and the idempotency ledger contains a single new completed, payload-bound, cached record for the operation.
- No stock, journal or transfer record was repaired by this test.
- Disposable MariaDB 11.8.9 multi-process business concurrency is PASS on head `6f361a1a039f87953703ccc943ce75e36d1bcfee`, CI run `35318834495`: concurrent payroll generation, concurrent stock-transfer state transition, employee transfer vs payroll, and salary approval vs payroll all preserve their invariants. Transaction rollback/savepoint proof is also PASS. This is strong isolated CI evidence; it does not replace a later controlled staging-host smoke test.
- Zero-authorised-branch runtime proof is **not yet executed** because doing so safely requires a dedicated staging test identity rather than altering a real employee's authority.

## Gate 5 — Private HR document migration/recovery

Before production HR-document cutover:

- New private upload/download tested with authorised user.
- Revoked user and inactive document access denied.
- Encrypted document restore drill succeeds with matching `eh7_document_key`.
- Legacy public employee/candidate media inventory completed.
- Legacy originals are re-uploaded through private document endpoints and content verified before retirement.
- Old media originals/thumbnails/CDN copies are removed only after usage review and explicit deletion approval.
- Old public URLs are retested without authentication after retirement.

### P2 document inventory — 2026-09-17

Read-only database inventory currently reports:

- `eh7_document_key`: present and non-empty (value not read or exposed)
- private encrypted blobs: 0
- employee documents: 0
- active legacy employee documents without private storage: 0
- candidate documents: 0
- active legacy candidate documents without private storage: 0

There is therefore no legacy HR-document migration backlog in the current database. The security batch adds a fail-closed disposable recovery gate that creates a synthetic encrypted HR document, exports the disposable MariaDB database, drops it, restores the SQL backup, verifies decryption with the restored matching `eh7_document_key`, rejects a wrong key, and rejects an inactive document. This is a CI recovery simulation only; host-level backup/files restore on a controlled staging copy remains required before production.

## Gate 6 — WordPress/plugin maintenance

At audit time the office site reported pending updates for:

- Hostinger Easy Onboarding 2.1.37 -> 3.0.0
- Hostinger Reach 1.8.0 -> 1.8.1
- WPVibe 1.16.3 -> 1.17.1

Update sequence:

1. Fresh backup/restore point.
2. Apply updates on staging first.
3. Re-run ERP REST/auth/document smoke tests.
4. Re-run PageSpeed/basic browser checks.
5. Apply to production only after staging verification and explicit approval.

No plugin update was applied during the P2 preflight because backup/restore proof is still missing.

## Gate 7 — Web production artifact

The production web workflow now targets `v740-business-completion` instead of the stale hierarchy branch and watches the full `flutter-app/**` source tree.

It must:

- run from `v740-business-completion` or explicit manual dispatch,
- use Flutter 3.44.9,
- run analyze + all tests before build,
- compile with `EH7_ENVIRONMENT=production`,
- compile against `https://office.excelherbal.in/wp-json/excel-herbal-erp/v7`,
- reject a build containing a `UAT BUILD` marker,
- verify `<html lang="en">` and the ERP meta description in the generated artifact,
- publish SHA-256 manifests with the artifact.

### P2 browser baseline — 2026-09-17

Fresh mobile Lighthouse against the public WordPress wrapper returned:

- Accessibility: 84
- Best Practices: 81
- SEO: 91
- Performance: unavailable from this lab run; diagnostics still reported roughly 3.3 MiB transfer, 3.6 s JavaScript execution and 4.2 s main-thread work.
- Wrapper issues: missing `<html lang>` and missing meta description; one deprecated-API warning and missing source maps were also reported.

The rendered WordPress root page is an outer frame generated from page `1194` with shortcode `[eh7_desktop_app]`; its iframe points to the deployed Flutter web artifact. The outer wrapper HTML lacks `lang` and a meta description. The iframe artifact itself was separately verified to contain `<html lang="en">`, the `Excel Herbal ERP operations portal` meta description and `noindex,nofollow,noarchive`.

The WordPress wrapper page is therefore audited separately from the Flutter artifact. Wrapper Lighthouse issues must not be incorrectly attributed to the generated Flutter source.

## Gate 8 — Android production artifact

Android production signing remains intentionally isolated to the approved Windows self-hosted runner.

Required:

- runner online as a Windows service (not dependent on an open PowerShell window),
- pinned JDK/Android SDK/Flutter toolchain available,
- production signing material stored outside the repository,
- `flutter analyze` + full tests pass before build,
- release APK signature verifies,
- signed AAB is produced when signing material is present,
- SHA-256 manifests captured for release APK/AAB.

### P2 workflow inspection — 2026-09-17

The Android production workflow is fail-closed by design:

- uses the approved Windows/X64 self-hosted runner and pinned Flutter 3.44.9 toolchain,
- reads signing configuration only from runner-local paths outside the repository,
- builds/tests before release packaging,
- verifies APK signature state,
- emits a signed APK/AAB only when approved signing material is staged,
- otherwise preserves only an unsigned release-mode compile artifact and exits the production-readiness summary as blocked.

This workflow has been inspected but a newly signed production APK/AAB has **not** been produced or approved in P2.

Recommended runner service setup after the runner is already configured:

```powershell
cd C:\actions-runner
.\svc.cmd install
.\svc.cmd start
Get-Service "actions.runner.*"
```

Run the service setup from an elevated PowerShell window. Do not re-run `config.cmd` unless the existing runner registration is actually lost.

## Gate 9 — UAT / pilot

Before production deployment:

- Android physical-device smoke test.
- Desktop/mobile web smoke test.
- Login/session refresh/403/401 behaviour.
- Attendance + GPS lifecycle.
- Daily Order full morning -> approval -> issue -> evening -> final-post flow.
- Sales receipt flow.
- Inventory transfer/receive/adjustment flow.
- Purchase and supplier payment flow.
- Finance expense/approval/closing/reversal flow.
- Payroll generation/review/approve/pay flow.
- Reports and branch-scope validation.
- HR document upload/download/revocation.
- Pilot branch sign-off by operational owner plus HR/Accounts for payroll-sensitive functions.

## Release decision

Production release is allowed only when Gates 1-9 have evidence and the final production deployment receives explicit approval. Until then the PR stays draft and no production deployment/database mutation is authorised.
