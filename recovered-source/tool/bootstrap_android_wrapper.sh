#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/flutter/excel_herbal_erp"
ANDROID="$APP/android"

if ! command -v flutter >/dev/null 2>&1; then
  echo 'BLOCKED: Flutter SDK is required to bootstrap Android Gradle wrapper.' >&2
  exit 20
fi

if [[ -x "$ANDROID/gradlew" && -f "$ANDROID/gradle/wrapper/gradle-wrapper.properties" ]]; then
  echo 'PASS Android Gradle wrapper already present.'
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
flutter create \
  --platforms=android \
  --org in.excelherbal \
  --project-name excel_herbal_erp \
  "$TMP/excel_herbal_erp" >/dev/null

cp "$TMP/excel_herbal_erp/android/gradlew" "$ANDROID/gradlew"
cp "$TMP/excel_herbal_erp/android/gradlew.bat" "$ANDROID/gradlew.bat"
mkdir -p "$ANDROID/gradle/wrapper"
cp "$TMP/excel_herbal_erp/android/gradle/wrapper/gradle-wrapper.jar" "$ANDROID/gradle/wrapper/gradle-wrapper.jar"
cp "$TMP/excel_herbal_erp/android/gradle/wrapper/gradle-wrapper.properties" "$ANDROID/gradle/wrapper/gradle-wrapper.properties"
chmod +x "$ANDROID/gradlew"
echo 'PASS Android Gradle wrapper bootstrapped from installed Flutter template without overwriting EH7 Android config.'
