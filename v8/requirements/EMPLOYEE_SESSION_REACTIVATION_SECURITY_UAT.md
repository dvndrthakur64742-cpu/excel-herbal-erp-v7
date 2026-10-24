# Excel Herbal V8 — Employee Reactivation Session Revocation (Development UAT)

## Business rule

An offboarded, inactive or reactivated ERP employee must never gain access
by reusing an access/refresh token issued **before** canonical reactivation.
Restoring the employee's status does not restore old device sessions.
**Fresh login** is mandatory after reactivation.

The canonical WordPress V7 `OrganizationEmployeeService::reactivateEmployee()`
now revokes **all remaining unrevoked** mobile_sessions for the employee's
current linked WordPress user **inside the existing payroll-company lock and
same database transaction**, **before** marking the employee active.
Any failure to revoke is fatal and rolls back reactivation. Stale sessions
from earlier status changes or incomplete cleanup cannot silently survive.

This reinforces rather than replaces existing offboarding's mandatory
session revocation and identity/branch/role permission controls. No
token blacklist or parallel V8 auth service is introduced.

It does not attempt to invalidate unrelated WordPress browser cookies
or externally integrated identity-provider sessions. Offboarding/reactivation
controls for those systems need separate approved policies.

## UAT evidence

The disposable GitHub MariaDB `v8_test` workflow runs actual WordPress
Core + ERP plugin. Synthetic Finance, BM and FSE log in using WordPress
password verification; finance gets real 1-hour access and 30-day refresh
tokens.

The new checks execute on the same Finance identity:

1. Record a real previously issued access and refresh token.
2. Inactivate Finance employee; old token receives 401.
3. Call the **real canonical employee reactivation service**, not a direct
   `UPDATE status='active'`, from a guarded CI-only WP-CLI synthetic
   system-authority fixture.
4. Assert the service reports `fresh_login_required=true`, and revoked
   at least one unrevoked session transactionally.
5. Reuse the original access token: 401; original refresh token: 401.
6. A completely new login issues new tokens and regains only the existing
   authorized read-only staging metadata view; normal logout still revokes
   the new session.

The synthetic mutation script checks GitHub Actions environment, exact
WordPress root, `development` mode, `v8_test` name, company/employee/
branch fixture identifiers and population counts **before** mutations.
No financial postings, actual stock movement, payment, external bank, or
production data are touched.

## Preview deployment paused

Owner postponed Office preview deployment. A separate narrowly scoped
GitHub Action requests cancellation **only** of the exact queued preview
run `39425651918` at head `f6cbe87f55dae1a5c8747ca8065afd0e02b264e7`.
It must check workflow name and SHA before cancellation. Its success is not
assumed until the GitHub API confirms `conclusion=cancelled`.

The read-only Flutter artifact remains as the last certified candidate,
but it is **not** a deployed release. No new preview upload is authorized
by this development batch.
