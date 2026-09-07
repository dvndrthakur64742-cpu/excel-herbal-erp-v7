#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/flutter/excel_herbal_erp"
PROD='https://office.excelherbal.in/wp-json/excel-herbal-erp/v7'

if grep -q "defaultValue: '$PROD'" "$APP/lib/core/app_config.dart"; then
  echo 'FAIL: Flutter default API points to production.' >&2
  exit 31
fi
if grep -q 'android:usesCleartextTraffic="true"' "$APP/android/app/src/main/AndroidManifest.xml"; then
  echo 'FAIL: Android cleartext traffic is enabled.' >&2
  exit 32
fi
if ! grep -q 'android:usesCleartextTraffic="false"' "$APP/android/app/src/main/AndroidManifest.xml"; then
  echo 'FAIL: Android HTTPS-only policy missing.' >&2
  exit 33
fi
if grep -RniE 'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)' "$APP/android" >/dev/null; then
  echo 'FAIL: Release build is configured with debug signing.' >&2
  exit 34
fi

echo 'PASS UAT safety: non-production default API, HTTPS-only Android, no release debug signing.'
