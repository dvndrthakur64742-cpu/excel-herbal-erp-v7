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
- 24 backend regression cases pass.
- Route/contract static checks pass.
- `flutter pub get` passes.
- `flutter analyze` passes with no blocking issues.
- Full Flutter test suite passes.
- Release-mode web compile passes.
- PR remains draft until these checks are green.

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
- WordPress core checksums: verified
- WP-Cron spawn test: PASS
- Database: MariaDB 11.8.9
- Default storage engine: InnoDB
- `max_allowed_packet`: 1,073,741,824 bytes (1 GB)
- `WP_DEBUG`: false
- `WP_ENVIRONMENT_TYPE`: not explicitly defined
- `DISALLOW_FILE_EDIT`: not explicitly defined

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

Before production:

1. Create a fresh full database backup and plugin/files backup.
2. Keep an independent protected backup of the `eh7_document_key` option with the matching database backup.
3. Prove restore on a staging copy before production cutover.
4. Define `WP_ENVIRONMENT_TYPE` appropriately for each environment (`staging` on staging, `production` only at final production cutover).
5. Set `DISALLOW_FILE_EDIT` to true for production after confirming operational access for controlled deployments.
6. Confirm PHP OpenSSL + fileinfo and upload limits for private documents. Database engine and packet headroom are already above the documented minimum baseline.
7. Re-confirm schema `7.3.5-business-fixes-1` after any staging migration and inspect migration errors.
8. Verify the private document encryption key is recoverable only with the matching backup.

No WordPress configuration write should be made directly on the production site before backup/restore proof.

## Gate 4 — Staging business/data validation

Must be executed against a controlled staging database:

- Payroll working-day policy confirmed by HR/Accounts.
- Exact paid/unpaid leave type configuration confirmed.
- Historical salary baseline/revisions reviewed through independent maker-checker.
- 21 payroll calculator cases + 3 service guard cases pass.
- Real MySQL concurrency tests pass for overlapping payroll generation, concurrent transfers, transfer vs payroll generation, and salary approval vs generation.
- Failed SQL transaction rollback verified.
- REST authentication, branch scoping and idempotency verified.
- Zero-authorised-branch state remains fail-closed.
- Employee transfer/history ambiguity cases fail safely.
- Payroll editor cannot approve a payroll they edited.
- Approved/paid historical payroll is never silently recalculated.

## Gate 5 — Private HR document migration/recovery

Before production HR-document cutover:

- New private upload/download tested with authorised user.
- Revoked user and inactive document access denied.
- Encrypted document restore drill succeeds with matching `eh7_document_key`.
- Legacy public employee/candidate media inventory completed.
- Legacy originals are re-uploaded through private document endpoints and content verified before retirement.
- Old media originals/thumbnails/CDN copies are removed only after usage review and explicit deletion approval.
- Old public URLs are retested without authentication after retirement.

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

The WordPress wrapper page is audited separately from the Flutter artifact. The Flutter source already contains `lang="en"`, an ERP meta description and `noindex`; Lighthouse wrapper issues must not be incorrectly attributed to the generated Flutter source.

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
