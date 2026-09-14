# ERP 7 — Compensation / Reward / Promotion Contract (v7.3.5 candidate)

## Boundary

This is an additive v7 contract. v14 is business-logic reference only; no v14 source code is merged. Website↔ERP integration remains untouched.

Live baseline verified before this contract: backend `7.3.4`, contract `7.3.4-contract-1`, schema `7.3.4-hr-lifecycle-1`.

## Salary structures

Proposed API:

- `GET /payroll/salary-structures`
- `POST /payroll/salary-structures`
- `POST /payroll/salary-structures/{id}/approve`

Required fields / semantics:

- company, employee and branch scope are server-resolved/validated;
- effective date/month is explicit;
- fixed components: monthly basic, HRA, fixed allowance, other fixed;
- every monetary input is a non-negative magnitude;
- fixed monthly total must be greater than zero;
- draft → approved/effective requires maker-checker;
- an approved structure is historical/immutable; correction creates a new version;
- no overlapping approved effective structure for the same employee/date;
- payroll freezes the salary structure/version used for every item.

Salary approval must not grant a Role, capability, Branch Authority, Reporting Manager, or designation.

## Reward / incentive / penalty ledger

Proposed API:

- `GET /performance/rewards`
- `POST /performance/rewards`
- `POST /performance/rewards/{id}/decision`
- `POST /performance/rewards/{id}/pay`

Supported business classes:

- incentive
- bonus
- recognition/appreciation
- penalty
- explicit points adjustment

Rules:

- reason is mandatory;
- monetary amount is stored as a positive magnitude;
- a deduction is represented by explicit `penalty`, never by a hidden negative bonus/allowance;
- negative points are accepted only by the explicit points-adjustment/penalty workflow;
- creator cannot approve the same adjustment;
- employee and Branch must be in the actor's authorised scope;
- approved points post once using a stable source/correlation identity;
- monetary rewards/penalties enter payroll/accounting once and are idempotent;
- a points-only adjustment never creates a cash-payment transition;
- rejected/revoked adjustments never affect payroll, points or accounting;
- every create/decision/pay action is audited.

## Promotion / increment

Proposed API:

- `GET /performance/promotions`
- `POST /performance/promotions`
- `POST /performance/promotions/{id}/decision`

Eligibility is a preflight only. Approval is always explicit.

The company training ladder can supply effective-dated eligibility thresholds (points, working days and average points). Thresholds are server data, not client authority rules.

Promotion/increment rules:

- current employee/designation must be active and in authorised scope;
- next designation must be explicit; never infer an arbitrary manager/designation;
- points/days/average metrics are frozen into an eligibility snapshot at request/decision time;
- maker-checker is mandatory;
- promotion approval may create/change the primary designation only through the existing controlled designation workflow;
- promotion never creates Reporting Manager, Branch Authority, Role or capability grants;
- blank Reporting Manager remains unresolved until an authoritative mapping is supplied;
- salary increment creates a new effective salary-structure version; historical payroll is never rewritten;
- temporary/additional designation is not treated as authority;
- all decisions are audited.

## Required capabilities

New sensitive permissions must remain separate from broad performance viewing:

- `salary.view`
- `salary.manage`
- `salary.approve`
- `rewards.view`
- `rewards.manage`
- `rewards.approve`
- `rewards.pay`
- `promotion.view`
- `promotion.request`
- `promotion.approve`

Existing `performance.view`, `performance.manage`, `payroll.generate`, `payroll.approve`, and `payroll.pay` remain unchanged.

## Required backend invariants before deployment

1. salary negative/zero-invalid cases fail closed;
2. salary overlapping approved effective period is blocked;
3. salary maker-checker blocks self-approval;
4. reward/penalty reason is mandatory;
5. negative money cannot encode a penalty;
6. reward self-approval is blocked;
7. reward wrong-branch/cross-scope action is blocked;
8. reward/points posting is idempotent;
9. paid/rejected state transitions are race-safe;
10. promotion eligibility does not auto-promote;
11. promotion self-approval is blocked;
12. promotion does not mutate Reporting Manager/Branch Authority/Role/capability;
13. unresolved manager mappings are never guessed;
14. salary increment creates a new effective version rather than changing historical payroll;
15. audit rows exist for create/approve/reject/pay/promotion/increment actions.

## Current source status

Flutter route constants and pure guardrail tests are being added first. Backend v7.3.5 must be built from the exact v7.3.4 source tree (or a cryptographically verified equivalent) before it is treated as an installable replacement. A reconstructed older package must not replace live v7.3.4.
