# Excel Herbal ERP V7 — live read-only post-install smoke audit
Date: 2026-11-04 (IST)
Host: https://office.excelherbal.in (production business URL)
Method: authenticated WPVibe GET REST requests and read-only WordPress SELECT queries.
No POST, login-password tests, mutations, or real user data exported.

## Installation and continuity verified
- Active WordPress plugin: 7.3.12-rc1
- Embedded reviewed source Git SHA: 6c201cde385645ad3748f495d4e8a190544b549c
- Installed ERP schema: 7.3.12-reward-payroll-allocated-6
- 5 additive Reward/Payroll/Promotion tables are present (structure, not business UAT).
- 27 active employees; 441 attendance records; 502 audit events; 24 unrevoked mobile sessions.
- WordPress Environment: staging on actual Office URL. Production/host environment mismatch remains a configuration-review item.
- Health staging_safety.source_head_match=false is the *synthetic staging sanitization marker* (not proof plugin Git SHA mismatch). Do NOT sanitize or revoke sessions on the Office host.

## Authenticated live read-only API tests
- GET /health — ok=true, plugin SHA/version/schema confirmed
- GET /setup/status — ok=true
- GET /me — ok=true, a linked employee/role was resolved (identifiers withheld)
- GET /organization/branches — ok=true, 7 branch entries
- GET /inventory/stock — ok=true, data available (raw rows omitted)
- GET /workforce/attendance/today — ok=true (person-specific contents withheld)
- GET /payroll/runs — ok=true, 0 entries
- GET /finance/expenses — ok=true, 0 entries
- GET /sales/orders — HTTP 403 branch_forbidden when no branch_id supplied
- GET /sales/payment-accounts — HTTP 403 branch_forbidden when no branch_id supplied
- GET /sales/returns — parameter_required for branch_id when missing

## Development fixes prepared after observation (NOT yet deployed)
- In ApiDispatch use readBranch($r,$a) for 3 GET Sales handlers so omitted branch falls back to actor's assigned branch.
- In ApiContract make returns GET branch selector optional, with integer validation for any supplied branch.
- PrepaidOrderService, PrepaidReturnService, and paymentAccounts still enforce real capabilities and branch checks; no cross-branch access bypass.
- Expose non-mutating DeploymentDiagnostics::status in health to show WordPress environment mismatch on actual production host without misinterpreting staging sanitization marker.
- New standalone PHP contract tests verify branch fallback, 403 on unauthorized branch, input validation, production/UAT environment diagnostics, and no mutating diagnostics.

## Pending, not asserted complete
Real Android/Web role-based UAT, bank evidence and UPI settlement, payroll and refund posting; no active-mobile-token validation or rollback certification from this audit. Do not claim that installed schema means all business modules are certified. DO NOT mark current dev fixes installed until a new verified plugin ZIP is uploaded.
