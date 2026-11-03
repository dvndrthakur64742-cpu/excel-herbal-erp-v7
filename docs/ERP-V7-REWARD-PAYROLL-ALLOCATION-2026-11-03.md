# Excel Herbal ERP — Reward to Payroll Allocation

Date: 2026-11-03. Scope: development branch only; review ZIP is not for Office production.

## Implemented

An independently approved positive cash reward (bonus/incentive/recognition) can be proposed against the exact beneficiary's corrected draft payroll item. The new POST /performance/reward-payroll-link-proposals/{id}/allocate endpoint requires an idempotency token, rewards.approve and payroll.generate capabilities, branch/hierarchy scope, and an allocator different from the reward maker, employee beneficiary and proposal creator.

The atomic allocation verifies the reward amount and approval, active employee and branch, draft calculation version 7.3.5, and the exact payroll item. A preexisting manual bonus or a changed proposal snapshot is rejected. Exact integer-paise arithmetic validates the existing net salary and adds the reward ONCE to bonus and net salary.

The new reward_payroll_allocations table has company-scoped unique keys for reward, payroll item and proposal. The proposal status becomes allocated_unpaid, and the allocation actor is added to payroll_editors so that they cannot approve their own edited payroll run. A one-reward-per-payroll-item limit is intentional until controlled aggregation is designed.

Payroll manual item edits, regeneration and draft deletion are blocked if allocated records exist. Payroll approval and payment separately verify immutable reward/bonus/net snapshots before journal posting. Allocation records are audited, not represented as completed bank transfers.

Finance Settlement Preflight can verify that the draft earnings are attributed to the specific reward. It still always returns payment_ready=false, payment_posted=false and settled=false at reward level. A paid payroll run or an equal bonus does not prove a beneficiary's reward was separately settled.

Schema marker: 7.3.12-reward-payroll-allocated-6.

## Automated evidence

PHP 8.2/8.3 regression, real disposable MariaDB allocation/uniqueness/actor separation/anti-tamper tests, isolated WordPress migration rehearsal, Windows local development QA, WordPress plugin review packaging. Flutter CI is a separate build check. No production user-data migration or hosted user E2E has been claimed.

## Release gates still open

1. Decide multiple cash rewards per payroll item and controlled reversal before payroll pay.
2. Link allocated reward to the approved payroll accrual journal, paid payroll liability discharge, bank/UPI evidence and employee disbursement; reconcile and prevent duplicate settlements.
3. Test HR/Finance reviewer UI with real-role desktop and Android UAT.
4. Finish tax-compliant GST credit-note and real prepaid refund postings.
5. Reconcile V7/V15 source and data ownership in one configurable WordPress plugin.
6. Verify production files/database backup, restore, staged migrations, rollback and safe release.

No Office live ERP installation, real payment, employee salary revision or production data modification occurred during this tranche.
