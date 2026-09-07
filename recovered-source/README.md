# Excel Herbal ERP 7 — Greenfield Clean Core

Clean V7 source architecture. No V4/V5/V6 runtime import and no PWA/service-worker layer.

- Backend namespace: `ExcelHerbal\\ERP7`
- REST namespace: `/wp-json/excel-herbal-erp/v7`
- Schema prefix: `eh7_`
- Schema version: `7.1.0-clean-10`
- Flutter is the mobile presentation client.
- Branch authority = primary assigned branch + explicit effective additional authorities; Role never expands it.
- Batch is optional per product.
- Posted corrections use controlled reversal; business source contains no direct delete path.

## Verification

Run `./tool/verify_source_rc.sh` anywhere with PHP + Python for the complete source/static gate.
Run `./tool/verify_stage12.sh` on a machine with Flutter 3.47.2 exactly for source gates plus `flutter analyze`, `flutter test` and debug APK compilation.

## UAT safety

Debug/UAT defaults to `https://uat.invalid/wp-json/excel-herbal-erp/v7` and displays a UAT banner. Supply an approved HTTPS staging endpoint with `EH7_API_BASE_URL`. Production API use remains blocked by the build gate until separately approved.

## Fresh setup

See `docs/INITIAL-SETUP.md`. Activation installs schema only; one-time setup is WordPress-admin-only and does not silently migrate or post historical business data.

## Current state

Source/static gates are release-candidate complete. Actual Flutter compiler/device UAT and legacy-data migration/reconciliation remain external mandatory gates before production cutover.
