# Excel Herbal ERP V7 — Engineering Delivery Gates (2026-10-31)

## Canonical architecture
- WordPress PHP plugin remains the authority for domain logic and database transactions.
- Flutter Web/mobile client uses versioned REST contracts; never reimplements pricing/permissions.
- GitHub source is reviewed via pull requests. No direct changes to production from unreviewed commits.
- Railway "Excel Herbal ERP - Isolated UAT" is a disposable TEST environment, never the authoritative live customer database.
- WPVibe is for authorized WordPress inspection, migration verification, and post-deployment health checks.

## Approved business invariants
1. Channels: B2C, B2B and distributor; distributor rates use per-order quantity slabs.
2. Separate Head Office and branch stock with custody and transfer ledgers.
3. Normal sales can pass automatically; discounts require branch manager / Head Office approval as configured.
4. Cash or verified UPI only; **100% confirmed payment before final invoice posting**.
5. GPS check-in/check-out; exceptions only with Head Office approval.
6. Field sales: morning issue -> independent review -> approval -> employee receipt -> custody movement -> evening returns -> sold quantity reconciliation.
7. Maker/reviewer/approver separation; branch-scoped access; no double posting on retries.
8. Every state transition must create durable audit evidence.

## Merge gates
- Code lint/static analysis passing for modified PHP, Dart and SQL.
- Database migration has tested forward path, existing-row preservation and an emergency rollback/restore plan.
- Contract tests for authentication, permissions, bootstrap, stock custody, cash/UPI, invoice prepayment, returns and approval.
- All monetary amounts decimal; idempotency keys and concurrency protection required.
- No passwords, tokens, credentials, real employee/customer PII or production database snapshots in Git.
- PR lists changed modules, migration IDs, tests and proof, UI impacts and release notes.
- At least one reviewer approval before merge; no deployment solely from local ZIP naming.
- Use sanitized UAT data and check WordPress health + Flutter login before rollout.

## Deployment gates
1. Build a versioned release artifact from a reviewed Git commit; checksum and manifest.
2. Deploy to isolated UAT first, run smoke/regression tests and verify data reconciliation.
3. Capture backup and restore test; rehearse rollback.
4. Production deploy only with explicit go-ahead, maintenance window and health-check plan.
5. Monitor API errors, session failures, stock mismatches, duplicate invoices and failed UPI reconciliation.

## Current observations (inspection 2026-10-31)
- GitHub repository: dvndrthakur64742-cpu/excel-herbal-erp-v7 (public, main).
- Railway isolated UAT project exists, with existing staged changes that must be reviewed before acceptance.
- Railway WordPress-UAT service was online during inspection, and WordPress-UAT-Deploy was offline.
- WPVibe daily fair-use quota was exhausted; WordPress production validation has NOT run.
- This document is an engineering policy proposal, not evidence that CI, deployment, or product implementation has passed.

## Work queue
P0: inventory canonical code/version; reconcile GitHub vs local 7.3.6-rc1 staging ZIP; fix bootstrap/mobile login; repair employee identity links.
P1: pricing slabs, discount matrix, full-payment invoice gate and verified UPI flow.
P2: stock transfer/receipt, morning issue, evening return and accounting reconciliation.
P3: GPS exceptions, payroll/reporting, accessible responsive UI and release candidate certification.
