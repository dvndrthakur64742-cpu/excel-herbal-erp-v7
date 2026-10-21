# Excel Herbal ERP V8 — Unified WordPress Main Plugin

## Purpose

Replace the split ERP7 Core + legacy Setup Assistant with ONE installable V8
WordPress plugin. This is a packaging and administration consolidation of the
existing audited ERP business code, not a new ERP or database migration.

The installable ZIP contains:
- V8 main plugin and independent WordPress Admin Setup Center.
- Complete existing ERP7 business source as an internal compatibility engine.
- One bundled and manifest-certified READ-ONLY Flutter V8 web preview.
- A WordPress nonce + Administrator capability protected preview installation
  action. Staging safety, exact source SHA, individual source-file SHA-256,
  existing database version and Office host checks are mandatory.
- Atomic web swap with the previous browser runtime retained for rollback.
- Existing ERP REST routes (/excel-herbal-erp/v7), existing employee, sales,
  stock, finance, payroll and attendance database tables and records.

## CRITICAL safe replacement sequence

1. Do NOT delete either original plugin or the database.
2. Install the V8 main plugin ZIP while the existing ERP stays in place;
   do not activate yet.
3. Deactivate old ERP7 Core without deleting its files. V8 activation is
   deliberately blocked if any of the previous V7 Core plugin paths is active.
   This prevents duplicate REST routes, attendance cron hooks and PHP classes.
4. Activate V8 on the SAME staging WordPress instance. Verify that its
   existing database schema matches and the old REST API and permissions work.
5. Open WordPress Admin > Excel Herbal ERP V8 > Unified Setup. Install bundled
   read-only web preview using its explicit, nonce-protected button. The old
   web directory is preserved as a rollback copy and actual file hashes are
   checked before activation.
6. Verify UI, routes, roles, data registers, employee profiles and attendance.
7. Only after the rollback copy and staging acceptance pass, separately
   approve removal of old ERP7 and old Setup Assistant. Do NOT delete ERP
   database tables or wp-content/uploads/eh7-flutter-web.
8. V8 remains BUILD/STAGING. Production approval is distinct and not granted.

## Compatibility / security notes

- Historical PHP class names and tables retain the ERP7 prefixes on purpose,
  so we continue the existing ERP, not recreate or truncate data.
- The V8 main plugin has no uninstall.php, no DROP, TRUNCATE, table deletion,
  user deletion or automatic cleanup on plugin deactivate.
- It refuses activation or execution on the production host.
- Existing old V7 plugin must be DEACTIVATED, not necessarily deleted, before
  activating V8.
- Old Setup Assistant is not used to administer V8 and may be removed AFTER
  acceptance.
- Bundled preview is read-only. The separate V8 B2B modules that are still in
  isolated tests are not falsely advertised as WordPress-integrated production
  writers. The canonical REST API remains the current /v7 route until a
  separately approved compatibility release.

## Automated verification

CI workflow: .github/workflows/v8-wordpress-unified-plugin.yml.

- Flutter analyzer plus full Flutter test suite.
- Immutable source SHA marker and SHA256SUMS for every bundled web file.
- PHP syntax validation of every bundled PHP file.
- WordPress bootstrap smoke: reject active old V7 Core, accept safe web paths,
  reject path traversal, load existing backend classes, register V8 admin hooks.
- End-to-end mock web preview install: bytes checked, old web directory backed
  up, file hashes match, existing ERP schema option remains unchanged.
- One correct WordPress plugin ZIP root (excel-herbal-erp-v8/) and a separate
  SHA256 release manifest. Packaging does NOT deploy the plugin.

## Mandatory schema migration gate (detected by packaging tests)

Office WordPress currently reports schema version 7.3.5-performance-indexes-1, but the existing branch's ERP Core Schema::VERSION is 7.3.8-reminder-review-center-1. For safety the V8 plugin now refuses to activate or boot its business routes unless the installed schema **already exactly matches** the packaged Core's expected version. New plugin activation MUST NOT silently run dbDelta/ALTER, populate salary snapshots, revoke sessions or rewrite financial data. Before the V8 switch, obtain an independently verified DB backup, review the schema delta and seek explicit owner approval for a staging migration, run that migration with rollback readiness, then activate V8. The standalone plugin ZIP can be installed as INACTIVE while this gate remains blocked.
