# Office Excel Herbal V8 — Owner-Approved Web-Only Read-Only Preview

**User approval:** Office `https://office.excelherbal.in` is the designated test-mode site; owner reports a current Hostinger Files + DB backup is available.

**Important:** This is specifically **only a Flutter Web frontend rollout**, not V8 PHP posting/DB migration. The current canonical V7 StockService/AccountingService backend remains installed and untouched. PR #25 stays Draft/unmerged.

## Release mechanism

- GitHub branch `codex/erp-v8-foundation-20261017`; exact commit/run SHA.
- One-shot push tag `[owner-approved-office-v8-web-preview]` is required for the dedicated `v8-office-web-preview-deploy.yml` workflow to execute. No future development push automatically deploys without the marker.
- Hosted Ubuntu runner builds Flutter Web with:
  - `EH7_API_BASE_URL=https://office.excelherbal.in/wp-json/excel-herbal-erp/v7`
  - `EH7_ENVIRONMENT=staging`
  - `EH7_PREVIEW_READ_ONLY=true`
  - `--base-href /wp-content/uploads/eh7-flutter-web/`.
- Flutter full analyze/test + preview-specific unit tests must PASS before creating a build. All asset hashes are stored in `SHA256SUMS.txt`, `.last_build_id` is set to exact GitHub SHA.
- Hosted build artifact remains available independently if the Windows self-hosted runner is offline.
- Windows self-hosted runner verifies the original WordPress staging `source_head=a9d03f384096b54464ffbe9ba79da88252f9dd28`, old web `main_sha256=370475e9f998a6bde87128db48d11f6ed7db2d806e4b4b5a7fefea25a1f98531`, initialized DB/schema, and host hardening.
- The exact-head ZIP is verified and staged, then the previously approved authenticated UI mechanism sends **only the web ZIP** to existing WordPress Setup Assistant's **Upload Web Bundle** form.
- After upload, the workflow downloads the actual new `main.dart.js`, compares SHA-256 with the immutable build and verifies the unchanged canonical PHP backend.

## Browser-side safety

The compile-time `PreviewReadOnlyPolicy` and Dio request interceptor block all mutation HTTP methods before network transmission, except exact login, refresh and logout routes. Multipart uploads, field stock issue, sales, payments, branch cash handover, accounting, salary, attendance and GPS POST operations are blocked. GPS tracking coordinator is not created in preview mode.

A visible top-of-app banner says **EXCEL HERBAL V8 PREVIEW • READ ONLY • NO FINANCIAL POSTING**.

This is a **client-side read-only restriction**, not server-side production financial authorization. Server-side capability and financial release gates remain mandatory. Existing V7 clients and other channels are unaffected.

## Known limitations / rollback

- Site already contains **27 employees, 7 branches and 95 stock balances** and staging data is **not fully sanitized**. The owner confirmed a Hostinger backup, but a machine-verifiable restore of that backup was not supplied.
- Uploading through the existing Setup Assistant **replaces the currently displayed Flutter web bundle at `eh7-flutter-web`**. It does not create a parallel preview folder. The earlier website should be recoverable from the owner's Hostinger web-files backup.
- If the Windows runner has no active authenticated WordPress admin Chrome session, the hosted candidate will build but deployment will not happen. Do not attempt cookie extraction, unsupported SFTP or a brute-force login.
- Some V8 UI panels query new API endpoints absent from the installed V7 backend, so those data panels can be unavailable; no V8 PHP/B2B sale-writer deployment is authorized.
- A green CI build is **not proof of live deployment**; the explicit live SHA verification step must PASS first.
- Never merge PR #25, run UAT-only migrations on the existing Office database, enable live bank verification or change production settlement gates through this workflow.
