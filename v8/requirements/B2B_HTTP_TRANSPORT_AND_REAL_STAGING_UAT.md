# V8 B2B — HTTP Transport and Real WordPress Staging Acceptance Gates

## 1. Automated tests we can run with no WordPress deployment

`v8/backend/tests/b2b_wordpress_http_smoke.py` starts a loopback-only
PHP built-in HTTP server and sends **actual HTTP requests** to the
canonical V7 `Api::register()` -> `Api::respond()` ->
`ApiContract::validate()` -> `ApiDispatch` ->
`B2BStagingRestProbe` path. It uses
`v8/backend/tests/b2b_wordpress_http_router.php`, a **synthetic WordPress
route + actor-resolver adapter**, not an installed WordPress site and not
real bearer-token verification. No external API, email, payment, private
database, production host or financial writer is contacted.

The test covers HTTP 401 (missing/invalid synthetic bearer), 403
(BM/FSE/unauthorized branch), 422 (bad/missing branch), 404 (POST not
registered; production/staging development-flag misuse and wrong database)
and 200 finance-only read. It checks the 14-table InnoDB metadata contract
and that no UAT-only POST, real bank/cash settlement proof or production
approval is claimed. Non-InnoDB and missing source tables return
`structural_preflight_possible=false`. Responses are JSON over actual
loopback HTTP and include the real V7 response envelope and request ID.

**This does not prove real WordPress authentication, live mobile flows,
database SQL adapters, actual UPI settlement or physical Cash handover.**
The pre-existing real disposable MariaDB tests cover financial data
integrity separately. The HTTP harness is a transport test only.

## 2. Real WordPress development HTTPS role UAT — manual, opt-in only

A separate script, `.github/scripts/b2b-dev-http-role-uat.ps1`, is available
to run **only after an isolated WordPress development site on a fresh
disposable `v8_test` database exists**. It is never part of automatic
GitHub CI. The script:

- requires an HTTPS V7 API base and explicitly refuses
  `office.excelherbal.in`, `excelherbal.in`, and `www.excelherbal.in`
- requires `-ConfirmedDisposableV8Test`, exact installed Git source-head
  and two distinct verified branch IDs
- first checks `/health` for `environment=development`, exact
  source-head and installed schema
- uses two fresh synthetic accounts: one authorized **accounting-view**
  actor and one **non-finance** limited actor; creates only temporary
  login sessions, and revokes both in a `finally` cleanup
- verifies 401 anonymous, 403 restricted user, 403 different branch,
  422 bad ID and 200 for authorized finance actor
- verifies all 14 InnoDB sources are detected and every payment/posting,
  bank/cash verification and release flag remains **false**
- writes redacted JSON pass/fail evidence (no passwords or bearer tokens)
- does NOT create B2B sale, payment, stock, GL, actual transfer,
  notification, GST document or refund.

Suggested syntax (execute manually **only after authorization and
environment review**; do not save secrets in shell history or GitHub):

```powershell
& '.github/scripts/b2b-dev-http-role-uat.ps1' `
  -ApiBase 'https://isolated-dev-host.example/wp-json/excel-herbal-erp/v7' `
  -ExpectedSourceHead '<40-character installed commit SHA>' `
  -AuthorizedBranchId 31 -ForbiddenBranchId 999 `
  -FinanceMobile $env:B2B_UAT_FINANCE_MOBILE `
  -FinancePassword $env:B2B_UAT_FINANCE_PASSWORD `
  -LimitedMobile $env:B2B_UAT_LIMITED_MOBILE `
  -LimitedPassword $env:B2B_UAT_LIMITED_PASSWORD `
  -ConfirmedDisposableV8Test
```

This example is illustrative; actual host, SHA, branch IDs and test
credentials must come from a **verified disposable UAT** installation.

## 3. Still requires explicit owner approval

Even a fully green HTTP suite is **not** authorization to enable B2B
WordPress POST endpoints. Remaining blockers: approved GST/HSN/discount
and reversal policies, trusted payment provider and independent physical
cashier evidence, canonical transaction locks and idempotency, real
browser/mobile role UAT, migration/rollback rehearsal, Accounts and pilot
sign-off, and owner's explicit deployment approval.

No merge, live WordPress migration, financial posting or automated
message dispatch is performed by these tests.
