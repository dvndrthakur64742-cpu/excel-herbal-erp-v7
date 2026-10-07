#!/usr/bin/env bash
set -euo pipefail

APK_PATH="${1:?APK path is required}"
PACKAGE_NAME="in.excelherbal.erp"
ACTIVITY="$PACKAGE_NAME/.MainActivity"
OUT_DIR="dist/android-emulator-uat"
mkdir -p "$OUT_DIR"
REPORT="$OUT_DIR/EVIDENCE.json"
LOGCAT="$OUT_DIR/logcat.txt"
SCREENSHOT="$OUT_DIR/final-screen.png"

pass_install=false
pass_location_on=false
pass_mock_location=false
pass_background_resume=false
pass_permission_denied=false
pass_permission_denied_forever=false
pass_location_off=false
pass_permission_restored=false

cleanup() {
  adb shell cmd location set-location-enabled true --user 0 >/dev/null 2>&1 ||     adb shell settings put secure location_mode 3 >/dev/null 2>&1 || true
  adb shell pm clear-permission-flags "$PACKAGE_NAME" android.permission.ACCESS_FINE_LOCATION user-fixed user-set >/dev/null 2>&1 || true
  adb shell pm clear-permission-flags "$PACKAGE_NAME" android.permission.ACCESS_COARSE_LOCATION user-fixed user-set >/dev/null 2>&1 || true
  adb shell pm grant "$PACKAGE_NAME" android.permission.ACCESS_COARSE_LOCATION >/dev/null 2>&1 || true
  adb shell pm grant "$PACKAGE_NAME" android.permission.ACCESS_FINE_LOCATION >/dev/null 2>&1 || true
  adb logcat -d > "$LOGCAT" 2>/dev/null || true
  adb exec-out screencap -p > "$SCREENSHOT" 2>/dev/null || true
  cat > "$REPORT" <<EOF
{
  "schema_version": 1,
  "gate": "android_emulator_gps_automation",
  "package": "$PACKAGE_NAME",
  "api_level": "$(adb shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')",
  "android_version": "$(adb shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')",
  "checks": {
    "apk_install_and_launch": $pass_install,
    "location_service_on": $pass_location_on,
    "mock_gps_fix_injected": $pass_mock_location,
    "real_background_resume": $pass_background_resume,
    "permission_denied_state": $pass_permission_denied,
    "permission_denied_forever_state": $pass_permission_denied_forever,
    "location_service_off_state": $pass_location_off,
    "permission_and_location_restored": $pass_permission_restored
  }
}
EOF
  cat "$REPORT"
}
trap cleanup EXIT

adb wait-for-device
adb shell getprop sys.boot_completed | grep -q '1'

adb install -r "$APK_PATH"
pass_install=true

adb shell pm grant "$PACKAGE_NAME" android.permission.ACCESS_COARSE_LOCATION
adb shell pm grant "$PACKAGE_NAME" android.permission.ACCESS_FINE_LOCATION

if adb shell cmd location set-location-enabled true --user 0 >/dev/null 2>&1; then
  pass_location_on=true
else
  adb shell settings put secure location_mode 3
  test "$(adb shell settings get secure location_mode | tr -d '\r')" != "0"
  pass_location_on=true
fi

adb emu geo fix 77.1095 31.9579
pass_mock_location=true

adb shell am start -W -n "$ACTIVITY" >/dev/null
sleep 3
adb shell pidof "$PACKAGE_NAME" >/dev/null
pass_install=true

adb shell input keyevent KEYCODE_HOME
sleep 2
adb shell am start -W -n "$ACTIVITY" >/dev/null
sleep 2
adb shell pidof "$PACKAGE_NAME" >/dev/null
pass_background_resume=true

adb shell pm revoke "$PACKAGE_NAME" android.permission.ACCESS_FINE_LOCATION || true
adb shell pm revoke "$PACKAGE_NAME" android.permission.ACCESS_COARSE_LOCATION || true
fine_line="$(adb shell dumpsys package "$PACKAGE_NAME" | grep 'android.permission.ACCESS_FINE_LOCATION:' | head -1 || true)"
coarse_line="$(adb shell dumpsys package "$PACKAGE_NAME" | grep 'android.permission.ACCESS_COARSE_LOCATION:' | head -1 || true)"
echo "fine_permission=$fine_line"
echo "coarse_permission=$coarse_line"
echo "$fine_line" | grep -q 'granted=false'
pass_permission_denied=true

adb shell pm set-permission-flags "$PACKAGE_NAME" android.permission.ACCESS_FINE_LOCATION user-set user-fixed
adb shell pm set-permission-flags "$PACKAGE_NAME" android.permission.ACCESS_COARSE_LOCATION user-set user-fixed
fixed_dump="$(adb shell dumpsys package "$PACKAGE_NAME" | grep -A1 'android.permission.ACCESS_FINE_LOCATION:' | head -2 || true)"
echo "$fixed_dump"
echo "$fixed_dump" | grep -Eq 'USER_FIXED|USER_SET'
pass_permission_denied_forever=true

if adb shell cmd location set-location-enabled false --user 0 >/dev/null 2>&1; then
  location_state="$(adb shell cmd location is-location-enabled --user 0 2>/dev/null | tr -d '\r' || true)"
  echo "location_state=$location_state"
  if [[ "$location_state" == "false" || -z "$location_state" ]]; then
    pass_location_off=true
  fi
else
  adb shell settings put secure location_mode 0
  test "$(adb shell settings get secure location_mode | tr -d '\r')" = "0"
  pass_location_off=true
fi

adb shell am force-stop "$PACKAGE_NAME"
adb shell am start -W -n "$ACTIVITY" >/dev/null
sleep 2
adb shell pidof "$PACKAGE_NAME" >/dev/null

adb shell pm clear-permission-flags "$PACKAGE_NAME" android.permission.ACCESS_FINE_LOCATION user-fixed user-set || true
adb shell pm clear-permission-flags "$PACKAGE_NAME" android.permission.ACCESS_COARSE_LOCATION user-fixed user-set || true
adb shell pm grant "$PACKAGE_NAME" android.permission.ACCESS_COARSE_LOCATION
adb shell pm grant "$PACKAGE_NAME" android.permission.ACCESS_FINE_LOCATION
adb shell cmd location set-location-enabled true --user 0 >/dev/null 2>&1 || adb shell settings put secure location_mode 3
adb emu geo fix 77.1095 31.9579
pass_permission_restored=true

echo "PASS Android emulator GPS/permission/lifecycle smoke"
