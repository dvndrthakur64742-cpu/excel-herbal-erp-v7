# Excel Herbal ERP v7.4.0 — Staging Pilot & Release Gates

Status: **BLOCKED FOR PRODUCTION**. This document is an operational runbook, not deployment approval.

## P6 read-only office audit — 2026-09-18

Automated source baseline before this batch: commit `402bb718c1b5bd57988d6a0744594165abc98cce`, CI run `35335003194`, FULL GREEN. P6 release-gate implementation was then certified FULL GREEN on commit `9e96fb2071377b5bee38b0a6de883c47304bc569`, CI run `35335931529`.

Connected office environment was inspected read-only:

- WordPress 7.1, PHP 8.3.33, MariaDB 11.8.9.
- ERP health reports version `7.3.5-rc1`, API contract `7.3.5-contract-1`, schema `7.3.5-business-fixes-1`, schema installed.
- Setup reports initialized and no schema migration-error option is present.
- Maintenance mode is off.
- Runtime environment reports `production`, but `WP_ENVIRONMENT_TYPE` is not explicitly defined.
- `DISALLOW_FILE_EDIT` is not explicitly defined.
- No connected backup plugin/Abilities API backup capability is available.
- MariaDB `max_allowed_packet` is `1073741824` bytes (1 GiB), comfortably above the earlier 32 MiB recommendation; PHP upload/post limits still require host-level evidence.
- `eh7_document_key` is present and non-empty without reading or exposing its value.
- Current private/employee/candidate document counts are zero.
- Existing active mobile sessions are present; no session was created, refreshed, revoked or mutated by this audit.
- No production/office database write, plugin update, theme publish, merge or deployment was performed.

The connected WPVibe REST client authenticates through its WordPress connection. It can prove that protected ERP routes are reachable for an authorised WordPress identity, but it **cannot** prove real mobile Bearer forwarding or unauthenticated/expired-token 401 behaviour. That gate remains pending.

## Machine-enforced release policy

`release-gates/v7.4.0.json` is the source of truth for pre-production manual gates.

`.github/scripts/verify-release-gates.ps1` has two modes:

- `ci`: validates the gate document and confirms fail-closed state without failing ordinary development CI while manual gates are still pending.
- `production`: fails unless every required manual gate is `passed`, each passed gate has evidence, `production_approved=true`, and approval metadata is populated.

Both production Web and Android workflows must run the verifier in `production` mode before any production artifact build. This prevents a manual workflow dispatch from bypassing Gates 1–9.

## Gate sequence

### 1. Host backup + restore proof — BLOCKED

Required evidence:

- complete MariaDB backup,
- plugin/files backup including the deployed ERP and private storage dependencies,
- independent protected backup of `eh7_document_key` matched to that database snapshot,
- restore to a controlled staging copy,
- restored ERP health/schema check,
- encrypted document recovery drill on staging.

Do not change production-classified host configuration before this proof.

### 2. Environment hardening — BLOCKED by Gate 1

After backup/restore proof:

- if the host is serving UAT, explicitly set `WP_ENVIRONMENT_TYPE=staging`,
- only at final cutover set `WP_ENVIRONMENT_TYPE=production`,
- set `DISALLOW_FILE_EDIT=true` for production cutover once operational file access is confirmed,
- record PHP upload/post limits and MariaDB `max_allowed_packet`,
- confirm OpenSSL and fileinfo.

### 3. Real HTTPS Bearer / 401 / 403 — PENDING

Use a dedicated UAT employee and controlled staging database.

Evidence must show:

1. mobile login returns access + refresh tokens,
2. Bearer access to `/me` succeeds,
3. refresh rotates both tokens,
4. old access/refresh tokens are rejected,
5. missing/invalid/expired token returns 401,
6. valid identity without branch/capability returns 403 on a protected action,
7. logout/revoke makes the token unusable.

Never use an office administrator's real active session for this drill.

### 4. Android physical-device GPS — PENDING

Use the manual `EH7 v7.4.0 Android Staging Pilot` workflow with a **controlled staging API URL**. Office is blocked by default.

Record:

- workflow run and APK SHA-256,
- device/Android version,
- install + login,
- Location off -> blocked state,
- permission denied/denied-forever states,
- permission granted + check-in,
- GPS point accepted,
- app background/resume sync,
- checkout stops duty GPS,
- 5 PM/server cutoff behaviour where practical,
- logout stops local tracking.

The pilot APK is a debug/UAT artifact and is not a production release artifact.

### 5. Real private HR multipart upload — PENDING

On staging only:

- upload controlled non-business fixture through the real multipart endpoint,
- verify no public WordPress attachment URL is created,
- authenticated download matches original SHA-256,
- deactivation/revocation blocks later download,
- restore database/files/key and verify recovery.

### 6. Business report review — PENDING

Accounts/operations must compare controlled staging transactions with:

- Sales,
- Purchase,
- Stock,
- Finance journals,
- Receivables,
- Payables,
- Trial Balance,
- Profit & Loss,
- Balance Sheet,
- finance reconciliation.

Automated P5 E2E checks are supporting evidence, not business acceptance.

### 7. Pilot sign-off — PENDING

Required sign-off: operational owner + HR + Accounts. Record names/roles, date, tested build/run, known accepted limitations, and change ticket.

Only after Gates 1–7 are evidenced may `production_approved` be changed to `true`. That change itself requires explicit final production deployment approval. PR merge and production deployment remain separate decisions.
