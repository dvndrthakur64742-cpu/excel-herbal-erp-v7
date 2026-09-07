# Excel Herbal ERP 7.1 — Build + Device UAT Status

Date: 2026-09-03
Phase approval: APPROVED for non-production build/device UAT.

## Completed in current runtime

- Clean-source regression: PASS
- UAT safety gate: PASS
- Flutter static integrity: PASS
- Backend PHP files: 36
- Flutter lib Dart files: 28
- Clean schema contract: 60 canonical tables (schema test PASS)
- Backend handler mapping: 118/118 PASS
- Flutter API contract: 101/101 PASS
- PHP lint: 36/36 PASS
- Optional batch policy: PASS
- Seven owner-decision-required policies remain disabled
- Production API is no longer the default for compiler/UAT builds
- UAT banner is shown for non-production builds
- Android HTTPS-only policy remains enforced
- Android release debug-signing remains forbidden
- Android Gradle wrapper bootstrap is deterministic from the installed Flutter template and does not overwrite EH7 Android configuration
- Workflow UAT contracts: PASS across 118 registered routes
- Customer Receipt is now mandatory against one selected posted outstanding Sale (`sale_id`); FIFO multi-sale allocation is removed
- Supplier Payment remains mandatory against one selected posted Supplier Bill; supplier advance remains disabled
- Future-dated primary employee Branch Transfer is rejected until a scheduled-transfer executor exists

## Compiler result


tool/verify_flutter.sh exit code: 20

```
BLOCKED: Flutter SDK is not installed in this environment.
Run this gate with Flutter 3.47.2 exactly (CI workflow is included).
```

Result: BLOCKED, not PASS. Flutter SDK is not installed in this execution environment.

## Staging result

The owner explicitly approved `office.excelherbal.in` as the initial UAT/pre-production ERP environment. Read-only verification confirms schema `7.1.0-clean-10`, 60 EH7 tables, and `initialized=false`; core business tables are empty. UAT builds may target this domain only with an explicit office-UAT override and must retain the UAT banner.

## Safety correction made in this phase

The previous compiler APK configuration defaulted to the production office API. That was unsafe for UAT. It has been changed so debug/compiler builds default to a non-production invalid endpoint, and production API use is rejected by the build gate unless a separately approved production flag is supplied.

## Remaining exit gates

1. Run Flutter 3.47.2 compiler on an SDK-enabled machine/CI.
2. PASS flutter pub get.
3. PASS flutter analyze.
4. PASS flutter test.
5. Produce Android debug APK and record SHA-256.
6. Use the explicitly approved empty office EH7 environment in controlled UAT mode.
7. Run critical device UAT against staging.
8. Only after these pass may migration planning proceed.

No production deployment, live business write, migration, or cutover was performed.
