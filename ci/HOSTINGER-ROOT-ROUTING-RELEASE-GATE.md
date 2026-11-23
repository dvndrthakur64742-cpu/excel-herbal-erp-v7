# Excel Herbal ERP — Hostinger Root Routing Release Blocker

**Reviewed on:** 23 November 2026  
**Site:** https://office.excelherbal.in  
**Backend health SHA:** `da45867ac0db3e4219fcf229f971986d0067acc7`  
**Cutover decision:** **BLOCKED** (do not modify production automatically).

## Read-only evidence

| Public URL | Observed result |
| --- | --- |
| `/` | HTTP 200 `text/html`; base points to `/wp-content/uploads/eh7-web-e7ede3d/`; old Last-Modified/ETag; PHP header absent |
| `/erp/` | HTTP 200 `text/html; charset=utf-8`; WordPress PHP; base points to `/wp-content/plugins/excel-herbal-erp-v7/web/` |
| `/wp-json/excel-herbal-erp/v7/health` | HTTP 200 JSON, reviewed source matches |
| `/?rest_route=/excel-herbal-erp/v7/health` | HTTP 200 **HTML homepage**, not WordPress JSON |
| `/index.php?rest_route=/excel-herbal-erp/v7/health` | Previously HTTP 200 JSON; rerun before any host change |

Root PHP/template routing **may be bypassed by a static document index or host rewrite**, but the exact server configuration is not proven. Do not assume a specific file exists, or blame the firewall/CDN without logs. Live WPVibe WP-CLI and file-read tools can receive the same homepage HTML; do not treat that response as a WP-CLI command result.

## New admin-only diagnostic available in the next QA build

This branch adds **Tools → ERP Hosting Diagnostics** within the existing ERP WordPress plugin.
An authenticated WordPress administrator can also read the **same redacted metadata**
through the canonical WordPress REST URL:

`GET https://office.excelherbal.in/wp-json/eh7-host-diagnostics/v1/root`

The API **requires WordPress `manage_options`** and returns HTTP 403 to other roles.
It reports presence/readability, file size, UTC modification date and boolean indicators
for old `eh7-web-*` references, rewrite directives and document-index rules. It does
**not** disclose physical directory paths, raw `.htaccess` content or credentials.
It does not follow file symlinks or perform any writes.

This endpoint is **not present on the existing live build** until a reviewed single-plugin
QA candidate containing this branch is installed after backup/restore readiness.
Do not use `/?rest_route=...` to reach it on the current site: the alternate query
form is known to return the old homepage HTML. Use the canonical `/wp-json/` URL.

The diagnostic is a source of additional evidence, not proof of the exact host rewrite,
and does not authorize a homepage cutover.

## Safest next actions — inspection first

1. **Confirm restore capability**: capture full WordPress files + SQL backup and verify restore on separate hosting/UAT. Keep a copy of installed ERP and UI installer, plus rollback contacts and window. **No successful backup/restore has been confirmed in this task.**
2. In **Hostinger hPanel → Websites → Manage → File Manager**, locate the **document root actually configured for the office subdomain**; do not assume it is the primary site's `public_html`.
3. Inspect *filenames, file types and last-modified times only* for `index.html`, `index.php`, `.htaccess`, server DirectoryIndex/rewrite rules, and static page caching. Do not share `wp-config.php`, passwords, tokens or private business data.
4. Determine whether a static `index.html`, custom rewrite, cached static root, or legacy UI installer is causing `/` and root-query requests to skip WordPress. Inspect Hostinger request logs for the exact URLs above, and both `/wp-json/*` and `?rest_route=` forms.
5. **Only after verified backup/restore and explicit approval**, test a reversible configuration change (e.g. adjust document-index order or temporarily rename a confirmed old root entry *without deletion*). Keep WordPress `index.php` and ERP REST routes intact. This document gives no automatic server-write instructions.
6. Re-run the preflight with the reviewed source SHA. Require JSON from both REST forms and the same plugin asset base on root and preview **after** the controlled homepage opt-in. This gate is intended for *post-cutover acceptance*; a pre-cutover legacy root correctly returns BLOCK.
7. Carry out real **Employee / Branch Manager / Head Office** sign-in, post-expiry refresh, attendance/order read/role access, logout and small-screen checks using authorised test accounts. Never disclose credentials in logs.
8. After sign-off, decide whether the old UI installer can be deactivated. Test service-worker/PWA behavior and CDN cache separately; do not deactivate it before compatibility review.

## Rollback requirements

If root UI, navigation, REST, staff login or data authority fails, reverse the explicitly approved document-root change (if any), return `eh7_integrated_frontpage_enabled` to `0` using the authorised WP admin control, restore prior installed plugin only if necessary, and verify API health. Use cache purge only after identifying its owner and retaining rollback logs. Preserve all ERP business data.

## Reproducible read-only preflight

From an isolated reviewed checkout with Node 18+:

```powershell
node --test ci/office-origin-preflight.test.mjs
node ci/office-origin-preflight.mjs --origin=https://office.excelherbal.in --expected-sha=da45867ac0db3e4219fcf229f971986d0067acc7 --output=dist/office-origin-preflight.json
```

The script performs **anonymous public GETs only**, writes a local metadata report and returns exit code **2** if cutover is blocked. It does not capture any tokens, staff data, full page bodies or secrets in its saved report.

**Release blockers are independent:** passing this route gate does not prove hosted backups, restore rehearsal, staff-role UAT, security sign-off or production approval.
