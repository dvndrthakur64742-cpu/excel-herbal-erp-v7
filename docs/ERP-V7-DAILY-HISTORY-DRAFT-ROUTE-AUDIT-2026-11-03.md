# Excel Herbal ERP V7 — Daily History, Draft Edit and Flutter Contract Drift

Date: 2026-11-03
Status: Development / review source only. Not deployed to Office.

## Implemented
1. Authenticated `GET /daily/cycles/search` resolves the existing Flutter history dialog. Read-only response contains `items`, `total`, `page`, `page_size` and `has_more`. Filters: branch, status, dates, order ID and employee name/code. Page size is capped at 50 and page at 1000; SQL wildcards are escaped. Always enforces company, authorized branch IDs and the actor's employee reporting-hierarchy scope; self-only actors cannot query colleagues.
2. Authenticated `POST /daily/cycles/{id}/edit-draft` supports the existing Flutter Edit Draft action with mandatory `lines` and idempotency. Only an unsubmitted initial draft may be replaced. The actor must be the beneficiary/creator with appropriate branch capability; whole PCS and unique existing product IDs are enforced. The cycle and request are locked in a transaction; changes roll back on failure; audit event records editing.
3. Updated canonical API route registry, dispatch handlers and `API-CONTRACT-7.3.6.json`. Added synthetic scope, rollback, mutation and contract regression tests to `tests/run.sh`.
4. Fixed Flutter's stale route checker to resolve the canonical PHP plugin source. CI now fails on any new unimplemented Flutter path and on an out-of-date reviewed exception list. Development CI runs `--baseline`; **strict release mode is still failing**, because 11 known route shapes are not implemented.

## Remaining API paths (explicit blockers)
- `/daily/cycles/{id}/cancel`
- `/daily/cycles/{id}/reopen-draft`
- `/daily/requests/{id}/cancel-additional`
- `/daily/requests/{id}/reject`
- `/payroll/salary-structures`
- `/payroll/salary-structures/{id}/approve`
- `/performance/promotions`
- `/performance/promotions/{id}/decision`
- `/performance/rewards`
- `/performance/rewards/{id}/decision`
- `/performance/rewards/{id}/pay`

## Test boundary / release preflight
- Synthetic PHP tests validate authorization conditions and rollback, but are **not** a live employee transaction or hosted DB restore rehearsal.
- GitHub CI tests are not equivalent to real-device and hosted WordPress E2E sign-off.
- Do not activate the staging plugin ZIP or upload a new Flutter bundle over Office until fresh files+DB backup, restore exercise, migration reconciliation, login/branch/UAT and rollback are verified.
- Prepaid refund payout, GST credit-note posting and V7/V15 ownership consolidation remain separate release blockers.
- No live DB, WordPress plugin, Railway service, or native Windows persistent files were modified during these development commits.

## Next technical tranche
Implement cancellation/rejection with explicit reason, exact maker-checker approvals, no issued stock, period-close protection and audit trail; then complete API parity. Advanced payroll/performance routes require dedicated authority and accounting contracts rather than placeholder endpoints.
