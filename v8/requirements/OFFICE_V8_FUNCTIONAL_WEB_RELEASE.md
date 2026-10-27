# Office V8 functional web candidate — staging, 27 Oct 2026

The owner clarified that `https://office.excelherbal.in` is **not currently
production** and asked for the project to move forward. This release track is
for a functional Flutter web UAT candidate on the **same Office website**.

## What has changed

- Workflow: `.github/workflows/v8-office-functional-web-candidate.yml`.
- Uses the existing `excel-herbal-erp/v7` REST API and the current PHP backend.
- Flutter is compiled with `EH7_ENVIRONMENT=staging` and
  `EH7_PREVIEW_READ_ONLY=false` so authorized requests (stock request,
  attendance, etc.) can reach the existing server-side role and posting gates.
- The CI candidate contains **only Flutter web assets**. It never installs the
  V8 PHP backend, updates a database or changes payment release flags. Ordinary
  pushes build only, while a *separate one-shot owner-marker job* can upload
  this exact artifact via the existing authenticated WordPress UAT web form.
- The signed ZIP and JSON manifest attest the exact Git source HEAD, main JS
  SHA-256, archive SHA-256, staging API endpoint and write-enabled build mode.
- Archive generation verifies the Flutter renderer manifest, rejects an active
  caching service worker, keeps CanvasKit runtime assets and rejects unknown
  asset layouts. The full Flutter suite and package tests must pass first.

## Why this is not an automatic deploy

The existing Office WordPress web installer requires an authenticated admin
session and current source/asset checksum attestation. Its older read-only
workflow has a **stale pinned web hash** and must not be reused or weakened.
At the latest read-only health check, Office reported backend source
`95a9e2806edef95257cd6b6aee6f1d56ca632d6b`, web source
`12d74a520471807e2a7a8f8521abbfdbd73573a8`, main JS SHA-256
`07eda6ed7f2e963ee0147274543b497e753ec4da990a5324accfcb04298aeea8`.
The site also reported `staging_safety.sanitized=false` and active mobile
sessions. These values are observations, not evergreen approved release pins.

For the owner's current staging rollout request, the one-shot commit message
marker `[owner-approved-office-v8-functional-web]` runs a Windows desktop
install job *only after* the same-head Flutter tests and signed build pass.
The job checks backend `95a9e28...`, current web source `12d74a5...` and
current main SHA `07eda6ed...` exactly; any drift fails before upload.
It reconstructs the web ZIP from SHA-256-verified ASCII transport, verifies
the functional-release manifest and uses the WordPress admin form's own nonce,
file input, source-head, audit reason and confirmation controls. No login
credentials or browser cookies are read. The server's UatWebDeployAdmin
atomically renames the previous web directory to a timestamped rollback copy
before activating a new bundle, and attempts to restore it if activation fails.
Successful deployment requires a second public fetch of the actual JS hash and
read-only backend health. If the Windows runner has no unlocked authenticated
Chrome session, the job stops without upload.

## Install acceptance checklist (same Office URL)

1. Get a fresh `/wp-json/excel-herbal-erp/v7/health` snapshot. Verify
   `environment=staging`, backend `source_head`, schema and hardening.
2. Capture **and verify restorable** current `/eh7-flutter-web/` files and the
   necessary Hostinger backup/rollback. Do not rely on an old backup claim.
3. Arrange a clear UAT window and warn testers that staging transactions are
   write-enabled and may change test records. No financial gates are bypassed.
4. Download the exact successful GitHub Actions artifact; independently verify
   the outer ZIP SHA-256 against its JSON manifest and all inner SHA256SUMS.
5. Using the supported Office WordPress admin UAT Web Deploy form, upload the
   web ZIP once with its **exact source HEAD** and a recorded audit reason.
   Do not use unauthenticated APIs, cookie extraction, or blind retries.
6. Poll fresh health after submission; verify `web_runtime.source_head` equals
   the candidate commit, live `main.dart.js` SHA-256 equals the manifest and
   backend source/schema remain unchanged. A CI green check alone is not deploy.
7. Run role-specific authenticated UAT: Employee stock request -> ASM review
   and issue -> records; login/session and narrow mobile layout; finance reads.
   Exercise financial writes only under existing business approval gates.
8. If acceptance fails, restore the previously verified web bundle and confirm
   its original health SHA. Do not alter backend/database as a workaround.

## Status

Source and packaging tests may pass while installation is **not performed**.
Only a post-install live hash and authenticated functional UAT can close this
release. The one-shot job must be observed to completion; a queued job,
failed form or green build step is not proof of deployment. PR #25 is still a
draft development PR, not a production sign-off.
