# Excel Herbal ERP — Delivery status scorecard

Date: 2026-11-03. Source: `feature/v7-v15-staging-source-ci-20261031`.
All completion counts are **equal-weight milestone counts**, not estimated engineering hours, developer velocity, production readiness or a claim that the ERP is deployed. CI-tested source is not a hosted employee UAT.

## Twelve critical milestones and evidence standard

Each milestone counts only when its stated technical criterion has implementation plus automated regression/synthetic integration coverage; production release milestones require actual runtime proof. Partially done work remains open in this conservative score.

| # | Milestone | State on 2026-11-03 | Acceptance qualifier |
|---:|---|---|---|
| 1 | Single WordPress V7 source foundation, REST contracts and CI | CI-verified development | PHP contracts, snapshot checks, packaging |
| 2 | Authentication, branches, employee/product masters, authority scopes | CI-verified development | Backend security, hierarchy and master tests |
| 3 | Daily stock order, independent review, physical receipt, stock ledger/transfer | CI-verified development | PHP/MariaDB synthetic and Flutter API tests |
| 4 | B2C prepaid order checkout and operational sales workflows | CI-verified development | Prepaid/receipt/invoice/ledger synthetic integration; real tender UAT still open |
| 5 | Payroll processing and salary structures with checker approval | CI-verified development | Salary history and payroll overlap tests; actual payroll UAT still open |
| 6 | Reward and promotion request/review, non-posting evidence and candidate link | CI-verified development | Checker separation; no salary/payment/access mutation; actual execution is separate |
| 7 | Reward-to-payroll allocation, payment settlement and points posting | OPEN | Immutable attribution, payroll item update, journals, duplicate-proof payment, reversals |
| 8 | Approved eligibility policy and controlled HR promotion/increment execution | OPEN | Qualifying points/days, effective designation/salary, authority projection, rollback |
| 9 | Tax-compliant GST invoice, credit notes and real prepaid refund disbursement | OPEN | Tax basis, journal/stock reversals, evidence, bank reconciliation |
| 10 | V7/V15 legacy data reconciliation and reusable single-plugin migration | OPEN | Data ownership, additive migrations, reconciliation, revert plan |
| 11 | Authenticated persistent Office browser, Windows and Android user acceptance | OPEN | Real roles, devices, failure/network tests, daily branch end-to-end signoff |
| 12 | Production files+DB backup, restore, rollback rehearsal and controlled live rollout | OPEN | Verified disaster recovery and signed deployment validation |

## Count and interpretation

- CI-verified development milestones: **6 of 12 (50%)**.
- Open critical milestones: **6 of 12 (50%)**.
- This is a transparent **milestone-count progress indicator** for the twelve critical workstreams. It is *not* 50% of coding hours or 50% production readiness. Remaining milestones can take disproportionate time.
- **Zero live rollout/restore/UAT gates have been declared complete.** None of the last six milestones may be treated as shipped by passing isolated CI.
- Direct `/performance/rewards/{id}/pay` was deliberately removed from Flutter rather than fabricated. The `POST /performance/rewards/{id}/payroll-link-proposal` creates an **unfunded candidate only**; no payroll item, salary, points or journal is updated. A reward remains unpaid even with an identical already-paid payroll bonus.

## Release rule

Do not install review ZIP on Office, run DB migration against persistent data, transfer employee/payroll data between V7 and V15, or ship mobile/Web assets until gates 7–12 pass with signed evidence. Employee, branch and product masters desired afresh should be migrated/archived only through an approved ownership policy, never silently dropped.
