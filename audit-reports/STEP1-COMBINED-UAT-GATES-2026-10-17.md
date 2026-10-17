# Step 1 combined UAT candidate — 2026-10-17

**Release status: BLOCKED.** This note documents a non-deployed, non-merged candidate combining the Reports/GPS development from PR #21 with Daily Orders, stock integrity and Finance reversal safeguards from PR #23.

## Exact-head automated acceptance
- [ ] GitHub ERP correction verification successful **for this integration branch SHA** (PHP regression, disposable MariaDB, Flutter analyze/tests, web compile).
- [ ] Route/API contract checks and RBAC/privacy regressions PASS.
- [ ] Candidate artifact SHA manifest independently verified.
- [ ] Combined UI authenticated screen-smoke PASS.

## Business workflow acceptance
- [ ] Daily Order request/draft/approval, warehouse availability preflight, stock issue into employee custody, additional stock and Evening Closing.
- [ ] Stock ledger, warehouse/custodian balances and original issuance reconcile per request; finance journals balanced.
- [ ] Reversal authorization correctly filters branch-scoped and company-wide records; maker-checker enforced.
- [ ] GPS 10:30–17:00 automatic duty and employee dashboard Sales/Points role-policy UAT.
- [ ] Accounts independently signs the business report packet; named Operational Owner, HR and Accounts pilot sign-offs.

## Deployment readiness
- [ ] Verify staging site's current plugin and web bundle SHAs and target environment.
- [ ] Current target database and files safely backed up, **restore verified** and rollback rehearsed.
- [ ] Exact combined release candidate verified with no competing/duplicate active ERP plugin.
- [ ] Explicit release sign-off, documented rollback and post-deployment smoke/monitoring.

No checklist box here is automatically marked PASS merely because a previous standalone PR passed. Do not automatically deploy this branch or change business records.
