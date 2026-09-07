# Excel Herbal ERP 7.1 — Stage 1+2 CI-Ready Verification

Date: 2026-09-03

## Verified in current runtime

- Business policy contracts: PASS
- Optional batch policy: PASS
- Seven owner-decision-required policies remain disabled: PASS
- Single authorised branch hides selector: PASS
- Multi authorised branches show selector: PASS
- Effective-date branch authority projection: PASS
- Clean schema: 60 canonical tables
- Backend API handler mapping: 103/103 PASS
- Flutter API path contract: 89/89 PASS (including dynamic routes)
- PHP lint: 34/34 PASS
- Flutter static integrity: 28 Dart files PASS
- Workflow UAT contracts: 103-route critical lifecycle contract PASS
- Customer receipt allocation: one specific outstanding Sale only; no FIFO allocation table
- Future-dated primary Branch Transfer cannot become effective early
- Android HTTPS-only manifest: PASS
- Android release does not use debug signing: PASS
- Approved release-keystore gate: PASS
- No legacy V4/V5/V6/PWA runtime dependency detected: PASS

## Flutter compiler status

Actual Flutter compiler gate is NOT marked PASS in this runtime because the Flutter SDK is not installed.
`tool/verify_flutter.sh` exits with code 20 when Flutter is absent.

A non-deploying GitHub Actions workflow is included at:
`.github/workflows/eh7-flutter-ci.yml`

It runs:
1. clean-source regression,
2. Flutter 3.47.2 stable setup,
3. `flutter pub get`,
4. `flutter analyze`,
5. `flutter test`,
6. Android debug APK compiler build,
7. debug APK artifact upload.

Production release signing is intentionally separate. `EH7_BUILD_RELEASE=1` requires an approved `android/key.properties` and release keystore. No signing secret or keystore is included in this source package.

## No production action

No live deployment, database migration, cutover, or production business write was performed by this verification/package step.
