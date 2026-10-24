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

## 2026-10-21 deployment trigger - explicit owner request

The owner asked to deploy to the existing Office WordPress test-mode site.
This branch authorizes only V8 WEB-ONLY READ-ONLY PREVIEW, using the tested
base source eab1717e21ff2ece7e228f62ca851d01499274c6.
Real authenticated Office site preflight: staging=true; host hardening=passed;
installed backend and web head a9d03f384096b54464ffbe9ba79da88252f9dd28;
old main.dart.js SHA-256 370475e9f998a6bde87128db48d11f6ed7db2d806e4b4b5a7fefea25a1f98531.

The host is not fully sanitized and active mobile sessions remain. No PHP backend,
database schema, accounting writers, sales posting, payroll, stock changes or
production deployment is authorized. Fail closed on changed baseline, failing
tests or unavailable authenticated web uploader. Keep PR #25 Draft and unmerged.

This documentation-only approval marker is the one-time deployment trigger.
Later feature development pushes must not automatically deploy.

## 2026-10-21 - Runner desktop detection hardening

On the user's continued request, add a no-mutation Windows runner interactive-session preflight BEFORE the slow GitHub artifact download. Session 0 or zero visible Chrome windows now fail clearly. The uploader must select an actual Chrome window by verifying its UI Automation address-bar URL (Office host + exact Setup Assistant desktop page), not by loosely matching a Chrome title. Ambiguous or inaccessible admin windows fail closed. Administrator credentials/cookies are never accessed, and an ordinary authenticated WPVibe REST connection is not substituted for browser login. Production posting and backend remain excluded. The web-only release still requires the owner-approval marker.

## 2026-10-21 — Nested ZIP integrity-protected deploy transport

The original GitHub-hosted web artifact was independently downloaded: all 33 files match SHA256SUMS.txt, including canvaskit/wimp.wasm. In contrast, its Windows runner extraction reported canvaskit/wimp.wasm hash mismatch and aborted before touching WordPress. This confirms a Windows extraction/staging mismatch, not a defect in the immutable hosted artifact. CI now builds one WordPress-ready ZIP on Linux and checks every contained file before uploading the ZIP itself as the sole GitHub Actions artifact. Windows verifies each entry hash directly from that nested ZIP stream, never extracting WASM files to its filesystem. The original web ZIP bytes, source marker and main JavaScript SHA are verified before delivery. PowerShell syntax parsing is enforced ahead of slow artifact transfers. No site mutation occurs unless the normal authenticated Setup Assistant upload and real live hash checks pass.

## 2026-10-21 — Windows artifact download corruption mitigation

Independent archive validation of GitHub artifact 12326924510 on a separate Linux environment proved the outer artifact and embedded WordPress ZIP were valid and all 33 internal source hashes matched. Windows runner nevertheless failed ZIP OpenRead with 'End of Central Directory record could not be found', after earlier extracted WASM file hash mismatches. We must not bypass ZIP signing or upload corrupted files. As a transport-only workaround, the Linux job encodes the already-verified ZIP into small ASCII base64 chunks with a source-HEAD, SHA256 and length manifest; Windows reconstructs the exact binary with strict chunk count, decoded length and SHA256 verification, then independently checks every ZIP entry using the existing fail-closed stage helper. This avoids putting a raw ZIP/WASM file through GitHub Actions artifact extraction on Windows. The existing same-session authenticated WordPress Setup Assistant and live hash attestation remain mandatory. No changes to site PHP, schema or accounting.

## 2026-10-21 — Actual authenticated WordPress Desktop Web UI surveyed

The Windows runner successfully opened the real authenticated `EH7 Setup Assistant` admin page in Session 1 and read real UI Automation labels: `Desktop Web` hyperlink, `Choose File: No file chosen` button and `Upload Web Bundle` button (enabled). The previous uploader unnecessarily re-clicked `Desktop Web` after opening the exact tab URL, starting a fresh navigation and querying stale UI too early. This uploader now keeps the already-verified Desktop Web tab, waits up to 60 seconds for the exact enabled upload control, and uses its native InvokePattern to submit the multipart form after selecting the certified ZIP. It never clicks other Setup Assistant actions. Post-upload actual WordPress bundle SHA and unchanged canonical V7 backend remain hard release gates. This change does not enable production accounting or backend writes.

## 2026-10-22 — Verified installed baseline and one-shot web-only preview retry

On the existing approved Office staging host, authenticated read-only health
reports **source_head** `95a9e2806edef95257cd6b6aee6f1d56ca632d6b`,
**web_runtime.main_sha256** `a0462c5f464f0300659b79ea3fd87fbc505849eefc4a3085820ff21e5d0781f8`,
**schema_installed** true, environment **staging**, host-hardening **passed**.
The old SHA guards in the dedicated web-preview workflow described an earlier
site baseline and would reject this confirmed newer installed Office build.
Update only those two exact-match guards; retain all status, host, schema,
authenticated Chrome, source and immutable SHA validation.

This is exclusively the owner-requested READ-ONLY Flutter web candidate;
no new PHP plugin, migrations, journal writes, stock, salary or bank-posting.
Do not assume success from an uploaded artifact or green hosted build: require
the actual after-upload main.dart.js hash plus unchanged backend health before
announcing a successful site deployment. The existing Office web runtime rollback
remains mandatory, and existing mobile sessions are not revoked or modified.

The current V8 installed plugin may not yet include FrontendShell, so Office
root-page routing is a **separate plugin release** and is not claimed by this
web-only preview deployment. The direct web preview is the valid acceptance URL
until that separate release is staged and verified.

## 2026-10-22 — failed upload guard and current WordPress form fix

Run 39774038933 built, signed and restored a 33-entry candidate ZIP
(SHA-256 f57e8fe8aafb29c3cef450fa4a94ea35f685dad745ff82fd5fd1f2d20be926de),
but **deployment failed before upload**. The Windows uploader still hard-coded
the obsolete a9d03f3/370475e baseline although the workflow had been updated
to the verified installed 95a9e28/a0462c5 baseline. The website's old web
SHA remained unchanged. The fix reads both required SHA pins from the exact
workflow's environment; it fails closed if either pin is malformed or the
site diverges.

The old Excel Herbal Setup Assistant upload page is no longer the active
administration path. The existing V7 UAT Web Deploy Admin registered by the
V8 business core exposes the supported administrator form at
/wp-admin/tools.php?page=eh7-uat-web-deploy. The updater now verifies that
exact Office URL and explicitly sets/verifies the original **source SHA**,
**audit reason** and **confirmation checkbox** in the authenticated Chrome
UI before selecting a certified WEB-ONLY ZIP and submitting the actual form.
The site's nonce and administrator authorization remain mandatory and are
never forged or bypassed. The old web runtime must be preserved as a rollback.
The final live hash check and unchanged business backend are still required
for a truthful deployed status.

The Office front page's legacy unreplaced [excel_herbal_portal] shortcode
and a narrow WordPress-contained iframe displayed the WordPress shell behind
the Flutter login. WordPress page 1194 was changed via its own content edit
path to redirect to the existing /wp-content/uploads/eh7-flutter-web/index.html
same-origin standalone app, with a no-script link. No plugin source, ledger,
stock, PHP finance posting, employee session, schema or credentials changed.


## 2026-10-22 — HTTP-size-safe CanvasKit-only artifact and UIA correction

The 15 MB web candidate was mostly alternate rendering runtimes. The
**compiled Flutter 3.44.9 bootstrap builds only dart2js+CanvasKit**. The
certified release workflow now inspects the compiler-produced bootstrap and
fails closed unless its build list matches this exact CanvasKit-only format
(and the self-unregistering service worker has no asset pre-cache). It excludes
unused Skwasm, Wimp, experimental WebParagraph and debugging .symbols files,
while retaining BOTH full/Chromium CanvasKit JS+WASM, the main JS, bootstrap,
fonts, shaders, assets, service-worker and page entrypoint. It regenerates a
manifest of every included byte, proves the exact archive source commit, and
enforces a strict 9 MiB upload budget. **If Flutter starts building another
renderer, pruning aborts until an architect changes and tests this gate.**

The previous certified admin UI automation had two independent problems:
Chrome exposed the file chooser by `AutomationId=eh7_web_bundle` rather than
`Choose File:*`; and immediately reading the ValuePattern/checkbox after
setting values occasionally observed a transient older state. Use exact
WordPress `eh7_source_head`, `eh7_reason`, `eh7_confirm`,
`eh7_web_bundle` element identifiers and allow short accessibility update
settling; still fail closed on missing source, audit reason or owner
confirmation, wrong selected ZIP, wrong staging hash or wrong WordPress
admin form. Post-upload completion is determined by fresh live backend +
SHA-256/source-head verification, NOT merely the button click or browser
navigation. The full backend/core, database, cash/stock and salary remain
unchanged. Preserve the verified pre-deploy web backup and route.


## 2026-10-22 — Office staging: verified deployment COMPLETE, post-server completion

The approved CanvasKit-only candidate from commit
`bdcc617e41ace10d44422a7d914a38eb459ea300` was built and SHA
validated: 14 unused renderer/symbol files omitted, 19 certified web files,
6,872,372-byte inner ZIP (9 transport blocks), main.dart.js SHA-256
`f57e8fe8aafb29c3cef450fa4a94ea35f685dad745ff82fd5fd1f2d20be926de`.

GitHub Actions run 39781021789's upload job initially marked failure because
it checked the old web SHA immediately after WordPress received the POST.
WordPress continued processing and successfully saved
`eh7_uat_web_deploy_last_result.ok=true` with the new source and hash at
2026-10-22 12:54:17 UTC. A *separate* authenticated WordPress V7 health
read confirmed the new `web_runtime.source_head` and
`web_runtime.main_sha256`. An independent Windows HTTP GET of the public
`/wp-content/uploads/eh7-flutter-web/main.dart.js` returned exactly
`f57e8fe8aafb29c3cef450fa4a94ea35f685dad745ff82fd5fd1f2d20be926de`
for its 5,421,405 bytes. The canonical backend remained
`95a9e2806edef95257cd6b6aee6f1d56ca632d6b`, staging hardening and
schema checks passed; no new PHP core, migrations or financial posting.

**Runner diagnosis:** a WordPress multipart POST can finish processing well
after the client/browser initially reports a network error. Prevent misleading
failure and dangerous duplicate submissions by polling ONLY authenticated
read-only server health for at most five minutes after submitting a single
approved ZIP. Fail closed for an unexpected source hash, backend change,
environment mismatch, or deadline; only an exact signed new web SHA and
unchanged core count as success.

Now that the live CanvasKit web SHA is `f57e8fe8...`, pin the next
release workflow's expected *old* web SHA to that exact live value. This
maintenance commit **does not trigger another Office deployment**.

**Acceptance status:** Flutter tests and compiled web PASS; deployed web
HTTP hash verified. A full authenticated human Admin/Manager Employee 360
interaction is still pending and must not be represented as completed.

## 2026-10-24 — Owner-approved staging read-only V8 UI refresh request

The owner explicitly requested "real percentage" and "deploy" in the
ERP project's current chat. For safety this deployment is constrained to
the existing `v8-office-web-preview-deploy.yml` owner-approved
**web-only, read-only** workflow, not the unified backend plugin, MariaDB
migration, new financial routes or live Cash/UPI settlement postings.

Preflight observations, independently checked before requesting release:
- Office host reports `environment=staging` and hardening passed.
- Canonical installed backend source is
  `95a9e2806edef95257cd6b6aee6f1d56ca632d6b`.
- Existing web runtime is
  `bdcc617e41ace10d44422a7d914a38eb459ea300`, main JS SHA-256
  `f57e8fe8aafb29c3cef450fa4a94ea35f685dad745ff82fd5fd1f2d20be926de`.
- Staging `sanitized=false`; active mobile sessions exist. **Therefore
  deploying the new backend, canonical cashier/PSP writer or financial
  schema is explicitly NOT approved by this release.**
- V8 unified plugin remains active; previous V7 versions remain inactive.
- Self-hosted Windows runner is online in interactive Session 1 with
  visible Chrome. Browser admin login and upload MUST be separately
  verified by the pinned workflow before a single upload.

Release controls: build exact HEAD, rerun full Flutter suite, compile with
`EH7_PREVIEW_READ_ONLY=true`, certify every asset with SHA-256 and stage a
web-only WordPress ZIP. Before upload validate expected OLD backend hash and
OLD web hash. Authenticate via the current WordPress UAT Setup Assistant,
retain the web rollback, and independently fetch actual Office health and
main.dart.js SHA after upload. Stop if ANY mismatch, login issue, missing
backup or noninteractive runner. Do not attempt a backend/database deploy as
fallback; on interrupted multipart upload re-read health before retrying.

**Progress accounting:** module code and tests passing are not equivalent to
business-production acceptance. Cashier/UPI release scope remains **3 of 5
confirmed checkpoints (60%)**, with authorized human browser UAT and safe
staging backend rollout outstanding. The **total ERP completion percentage is
not verified** until all module checklists and acceptance criteria are audited.
A read-only web-only preview changes the staging-visualization status, not
the Cashier/UPI production-readiness numerator.
