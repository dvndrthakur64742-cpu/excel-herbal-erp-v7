# Excel Herbal ERP 7 — Greenfield Source Completion RC Verification

Date: 2026-09-03
Scope: approved local source completion and Build/Device-UAT preparation. **No production deployment, migration, live database write or cutover.**

## Source completion closed in this RC

- Canonical payroll lifecycle: Generate → branch-history-aware calculation → Review/Adjust → maker-checker Approve → PAYROLL_PAYABLE → controlled Cash/Bank/UPI Payment → reversal.
- Customer Receipt is specific posted Sale only; Supplier Payment is specific posted Purchase Bill only; customer/supplier advances stay disabled.
- Stock Adjustment posts canonical stock + Inventory/Stock-Variance journal and has controlled reversal.
- Branch authority is independent of Role; zero-authorised-branch identities are blocked from business APIs/navigation.
- Normal employees can bootstrap their own authorised branch projection without receiving Branch Master permission.
- One-time fresh-install setup now creates Company, first Head Office, first ERP administrator identity, canonical accounts and SYSTEM_ADMIN role without posting historical business data.
- Administration Access Management now supports Role creation, capability assignment and existing employee role assignment with audit reason and self-lockout protection.
- Finance masters now support controlled creation of additional ledgers and Expense Heads; Cash/Bank/UPI remain real ledger accounts.
- Batch remains optional per product and owner-decision-required features remain disabled.

## Fresh source verification

- Schema version: `7.1.0-clean-10`.
- Clean schema: **60** canonical `eh7_*` tables.
- REST routes/handlers: **118/118** mapped.
- Flutter API paths: **101/101** mapped, including dynamic routes.
- Workflow contracts: **PASS across all 118 registered routes**.
- PHP syntax: **36/36 PASS**.
- Flutter static integrity: **28 `lib/` Dart files PASS**.
- UAT safety: PASS — default API is non-production; production API is blocked unless separately approved.
- Zero V4/V5/V6/PWA runtime dependency: PASS.
- All seven unresolved owner-policy features remain disabled: supplier return, treasury transfer, supplier advance, employee advance/loan, bad-debt write-off, half-day/late/overtime and direct non-stock supplier invoice.
- Direct business `DELETE FROM` / `$wpdb->delete()` paths: none.
- Committed-secret/keystore scan: PASS.

## External gates still required

1. `flutter pub get`, `flutter analyze`, `flutter test` and Android APK/AAB compilation on a Flutter-enabled build environment.
2. Real device/API UAT against the explicitly approved empty `office.excelherbal.in` EH7 environment, using UAT build mode and controlled test data.
3. Legacy-data migration dry run using actual old schema/data, followed by stock, AR, AP and journal reconciliation.
4. Explicit approval before production deployment/cutover.

This is a **source release candidate**, not a compiled APK/AAB and not a production deployment package.
