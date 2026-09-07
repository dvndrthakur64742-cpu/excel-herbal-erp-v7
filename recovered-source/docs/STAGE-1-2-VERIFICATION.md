# Excel Herbal ERP V7.1 — Stage 1 + Stage 2 Verification

Date: 2026-09-03
Status: CLEAN SOURCE / STATIC GATES PASS / FLUTTER COMPILER GATE BLOCKED BY RUNTIME

## Verified clean-core facts

- Backend namespace: `ExcelHerbal\\ERP7`
- REST namespace: `/wp-json/excel-herbal-erp/v7`
- Database prefix: `eh7_*`
- Clean schema tables: 60
- Registered REST handlers: 103/103 mapped to real handlers
- Flutter API path contracts: 89/89 matched
- PHP lint: 34/34 PASS
- Flutter source files: 28 Dart files
- Flutter static integrity: PASS
- Android scaffold: present
- PWA / service worker: absent
- Legacy V4/V5/V6 runtime tokens: absent
- Batch policy: optional
- Customer Receipts are sale-specific (`sale_id` required); customer advances and FIFO multi-sale allocation are disabled.
- Supplier Payments are purchase-bill-specific; supplier advances remain disabled.
- Future-dated primary employee Branch Transfers are rejected until scheduled transfer execution exists.

## Authority and control rules verified in source

- Assigned branch plus explicit active additional branch authorities only.
- Future-dated branch authority is not effective before `valid_from`.
- One effective branch hides the selector; multiple effective branches show it.
- Role does not expand branch authority.
- State-changing API calls require idempotency keys.
- Posted accounting/stock transactions use controlled reversals rather than deletion.
- Branch Closing preflight blocks open Daily Orders, open transfers, pending adjustments, quarantine, pending expenses, pending reversals, employee custody stock and negative stock.
- Accounting Period close requires authority over all active branches and a closed Branch Day at period end for every active branch.
- Reopened accounting periods re-close the same canonical period record rather than creating a duplicate period.

## Flutter business UI available in source

- Login / secure session / token refresh
- Home / My Work / Actions / Tasks / Profile
- Attendance, Field Visit, Leave, Daily Order
- Team Daily Order approval + stock issue
- Sales + Counter Sale + Customer Receipt + Customer Master create
- Inventory Transfer / receive / discrepancy / cancel / adjustment / quarantine
- Direct Supplier Bill + Supplier Payment + Supplier Master create
- Finance / Expenses / Branch Closing / Periods / Bank Reconciliation / Reversals
- Payroll / Performance
- Reports Centre
- Organization Masters: Branch create, Employee create, Employee branch transfer/history, additional Branch Authority, Product create, Commercial Revision/history
- Communication and Administration

## Not yet verified

The current execution runtime does not contain Flutter/Dart SDK. Therefore the following are **not** marked PASS:

- `flutter analyze`
- `flutter test`
- Android APK/AAB compilation
- physical-device UAT
- live WordPress/MySQL end-to-end transaction tests
- old-system data migration and reconciliation
- production deployment/cutover

No production deployment is included in this checkpoint.
