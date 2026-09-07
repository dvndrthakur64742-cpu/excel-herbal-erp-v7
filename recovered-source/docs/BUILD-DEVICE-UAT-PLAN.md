# Excel Herbal ERP 7.1 — Build + Device UAT Gate

Status: APPROVED for non-production build/device verification only.

## Safety boundary

- No production deployment.
- No database migration/cutover.
- No business write to `office.excelherbal.in` during UAT.
- Debug/compiler builds default to `https://uat.invalid/...` and visibly show `UAT`.
- A real staging API URL must be explicitly supplied for end-to-end API UAT.
- Production API use is blocked by `tool/verify_flutter.sh` unless `EH7_ALLOW_PRODUCTION_API=1`; that flag is reserved for a separately approved production/cutover phase.

## Compiler acceptance

1. `./tool/verify.sh` PASS.
2. `./tool/verify_uat_safety.sh` PASS.
3. `flutter pub get` PASS.
4. `flutter analyze` PASS with no errors.
5. `flutter test` PASS.
6. Android debug APK builds successfully.
7. APK SHA-256 recorded.

## Device UAT acceptance

Use a staging WordPress + MySQL environment containing the EH7 backend only. Record device model, Android version, app build hash, API environment, tester, timestamp, and evidence for each flow.

| Flow | Required result |
| --- | --- |
| Login/session refresh/logout | Correct auth, refresh and secure logout |
| Branch authority | 0 branch blocks; 1 auto-select/hides selector; 2+ shows authorised branches only |
| Attendance | GPS permission, check-in, check-out, retry/error states |
| Daily Order | create → submit → approve → issue → additional → evening → final post |
| Optional batch | batchless works; required batch enforces selection; expired outbound batch blocked |
| Counter Sale | stock/COGS/receipt/outstanding journal path consistent |
| Stock Transfer | draft → pack → dispatch → receive; discrepancy/correction/cancel rules enforced |
| Purchase | direct supplier bill → stock → AP → supplier payment |
| Expense/Reversal | maker-checker, journal, controlled reversal |
| Branch/Period Closing | blockers enforced; controlled reopen works |
| Payroll/Performance | generate → checker approve → journal; performance visible |
| Reports | canonical registers/ledgers match posted transactions |
| Offline/network failure | no duplicate final transaction after retry; clear error/retry UI |

## Exit criterion

This phase is complete only after compiler gates PASS and critical device UAT flows PASS against staging. Migration remains blocked until then.
