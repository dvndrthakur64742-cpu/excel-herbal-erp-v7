# Excel Herbal ERP V7 — 7.3.7-rc1 (Staging Candidate)

## Core fixes from 7.3.6-rc1
- Authenticated `/bootstrap` now returns WordPress-local `business_date`, `business_timezone`, ISO UTC `server_timestamp` and root `api_contract`, matching Flutter startup validation.
- Employee listing marks login enabled only when a linked WordPress identity exists; invalid stale links report disabled.
- WordPress Admin Employees & Login save sends the required `X-Idempotency-Key` header and displays structured REST errors.
- ERP credential-management endpoints refuse resetting the password of a linked privileged WordPress administrator; admin credentials remain managed in WordPress.
- No employee accounts or passwords are created or reset automatically during installation.
- Plugin package includes the actual GitHub checkout SHA as `EH7_SOURCE_HEAD`; the original unverified staging archive is no longer the release provenance.
- No database schema migration accompanies these particular fixes.

## Source / UI
The Flutter editable source is tracked alongside the plugin, with build-specific production/UAT API target safety gates. **Flutter Web is a separate CI artifact** and is not installed by this WordPress plugin ZIP.

## Required release gates
1. PHP 8.2/8.3 regression and API checks pass.
2. Flutter analysis, tests and UAT Web build pass against canonical plugin source.
3. Railway isolated UAT normal `/wp-json/` routing and WordPress host-hardening are fixed; old destructive patch reviewed separately.
4. Test synthetic mobile login, token refresh, bootstrap, employee branch access, morning issue, evening reconciliation, cash/verified UPI, and full-prepayment restrictions.
5. Backup/restore exercise, UAT signoff and explicit production deployment approval.

**Release status:** staging only, not production-ready. Do not deploy just because CI passes.
