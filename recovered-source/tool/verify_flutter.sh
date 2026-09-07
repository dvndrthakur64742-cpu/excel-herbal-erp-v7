#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/flutter/excel_herbal_erp"
PROD_API='https://office.excelherbal.in/wp-json/excel-herbal-erp/v7'
API_BASE="${EH7_API_BASE_URL:-https://uat.invalid/wp-json/excel-herbal-erp/v7}"
ENVIRONMENT="${EH7_ENVIRONMENT:-uat}"

if ! command -v flutter >/dev/null 2>&1; then
  echo 'BLOCKED: Flutter SDK is not installed in this environment.' >&2
  echo 'Run this gate with Flutter 3.47.2 exactly (CI workflow is included).' >&2
  exit 20
fi

if [[ "$API_BASE" != https://* ]]; then
  echo 'FAIL: EH7_API_BASE_URL must use HTTPS.' >&2
  exit 22
fi

if [[ "$API_BASE" == "$PROD_API" && "${EH7_ALLOW_PRODUCTION_API:-0}" != "1" ]]; then
  echo 'BLOCKED: Production API is forbidden for compiler/device UAT without explicit production approval.' >&2
  exit 23
fi

"$ROOT/tool/bootstrap_android_wrapper.sh"
"$ROOT/tool/verify_uat_safety.sh"

cd "$APP"
flutter --version
flutter pub get
flutter analyze
flutter test
flutter build apk --debug \
  --dart-define=EH7_API_BASE_URL="$API_BASE" \
  --dart-define=EH7_ENVIRONMENT="$ENVIRONMENT"
DEBUG_APK="$APP/build/app/outputs/flutter-apk/app-debug.apk"
test -f "$DEBUG_APK"
sha256sum "$DEBUG_APK"
echo "PASS Android debug compiler-gate APK: $DEBUG_APK"

if [[ "${EH7_BUILD_RELEASE:-0}" == "1" ]]; then
  if [[ ! -f android/key.properties ]]; then
    echo 'BLOCKED: EH7_BUILD_RELEASE=1 requires android/key.properties and approved release keystore.' >&2
    exit 21
  fi
  flutter build appbundle --release \
    --dart-define=EH7_API_BASE_URL="$API_BASE" \
    --dart-define=EH7_ENVIRONMENT="$ENVIRONMENT"
  AAB="$APP/build/app/outputs/bundle/release/app-release.aab"
  test -f "$AAB"
  sha256sum "$AAB"
  echo "PASS signed Android release AAB: $AAB"
fi
