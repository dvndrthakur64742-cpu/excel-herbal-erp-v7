# Excel Herbal ERP V8 — Evidence-Based Progress and Release Ledger

**Created:** 2026-10-24
**Repository:** `dvndrthakur64742-cpu/excel-herbal-erp-v7`
**Branch:** `codex/erp-v8-foundation-20261017` · Draft PR #25
**Baseline examined:** `a1ffde3c11e7a0f81130066d1cb3d8fa3313b5c9`
**Deployment:** This development branch is NOT the running Office frontend. No production rollout is approved.

## Rules for reporting progress (effective now)

1. **Overall engineering percent is UNVERIFIED**, not a rounded count of green CI jobs or git commits. Earlier conversational 35–40%, 40%, 55% or 60% figures had different scopes or estimated methods; none is a certified latest overall task numerator.
2. **Never reduce/restate the overall percent using a different denominator.** Before a percentage is reported, freeze the approved V8 scope, acceptance cases and area weights below. Each earned point requires a linked commit/test **and** the acceptance tier specified by the row.
3. Two separate registers must always be reported: **development implementation** (code plus automated verification) and **staging/production acceptance** (actual installed hash, permitted user-role tasks, device UX, cash/stock/GL evidence and signoff).
4. Status values are `SOURCE_PRESENT`, `CI_VERIFIED`, `UAT_VERIFIED`, `SIGNED_OFF`, `BLOCKED`, or `UNASSESSED`. A CI pass cannot be promoted to UAT merely by another push.
5. Record evidence as: scope item → tested case → exact source HEAD → CI run ID → authenticated branch/role/device UAT → reviewer → date. Unknown or rejected gates count **zero accepted points**; no unverified fractional credits.
6. Weight table is a **proposed denominator**, not a retrospective earned-score table. The owner must approve the frozen scope and weights before an auditable percentage can be calculated.

## Proposed full ERP engineering scope — exactly 100 weights

| Scope | Weight | Development evidence currently present | Main acceptance gap |
|---|---:|---|---|
| Requirements, BRD and cross-module policies | 7 | Business logic register, daily lifecycle and permission rules | Resolve attendance split, tax/HSN/refund/pricing and signoff |
| Organization, roles, hierarchy and tenant boundaries | 9 | Canonical V7 access services and WordPress REST UAT | Complete genuine multi-role/branch denial and escalation UAT |
| Employee 360, HR, payroll, GPS and attendance | 11 | Profile registers, monthly/stock V8 cards, synthetic GPS/finance tests | Payroll policy and role/device GPS/attendance pilot |
| Catalog, procurement and inventory | 12 | Existing V7 stock/purchase engines and Flutter inventory shell | Batch custody/expiry, physical counts, real multi-branch reconciliation |
| Daily Order request, approval, issue and evening settlement | 15 | Original V7 workflow; stage workboard, order selector, canonical writer tests | Real field employee/ASM evening-to-ledger and cashier UAT |
| Counter/field/B2B retailer sales | 14 | Original V7 sales and isolated V8 full Cash/UPI domain UAT | Trusted external tender, GST invoices, returns, role UAT |
| Finance, Tally-style ledger, remittance and closing | 12 | Canonical V7 GL and read-only profile ledger/finance screens | Independent cash handover and bank-verified UPI, full journal reconciliation |
| Branch reporting, approvals and notifications | 6 | Daily/weekly/monthly and regional report UAT suites | Reviewer acceptance and actual delivery adapter if authorised |
| Modern V8 UI/UX and mobile accessibility | 8 | Navigation, Sales, Finance, Daily Orders, Employee360 CI widget tests | All pages/buttons/forms, real mobile/browser screenshots and acceptance |
| Release qualification, backup, security, staging and rollback | 6 | PHP/MariaDB/Flutter/WordPress disposable green pipelines | Safe sanitized rehearsal, active sessions, rollback restore, pilot signoff |
| **TOTAL PROPOSED WEIGHT** | **100** | **NOT A COMPLETION PERCENT** | **Requires measured acceptance** |

## Latest verified development baseline

- 2026-10-24 HEAD `a1ffde3c11e7a0f81130066d1cb3d8fa3313b5c9`: Flutter UI run `40092903409`, PHP/MariaDB `40092903408`, WordPress role REST `40092903385`: success on that exact commit. These are development/test results, NOT proof of installed Office UI, real cashier/bank acceptance or end-to-end business signoff.
- Next enhancement in this series: search and compact-height layout for the **authorised Evening Closing original-order chooser**. The exact corrected commit and CI run IDs must be recorded in follow-up audit before declaring CI-verification.

## Office staging — independent release gate

- WordPress health on 2026-10-24: backend `source_head=95a9e2806edef95257cd6b6aee6f1d56ca632d6b`, Flutter `web_runtime.source_head=7b6448fccdb170228877e0c70e789a2a942f2583`. Neither equals development HEAD.
- `environment=staging`, `host_hardening.status=passed`, but `staging_safety.sanitized=false`, `source_head_match=false` and `active_mobile_sessions_zero=false`.
- Therefore do **not** claim current UI is installed, do not migrate/overwrite Office PHP or DB, and do not infer production completion from CI.
- Release candidate sequence: exact-head artefact → Flutter web compile → authentic branch/role UAT on isolated sanitized preview → financial reconciliations → verified restore plan → owner's explicit deployment and accounting approvals.

## Change control

- Every new development batch updates the relevant row's evidence and blockers; no percent claim until approved weight/acceptance case inventory has been enumerated, executed and counted.
- UI-only work does not alter canonical posting, payroll, GPS duty automation, DB schema, privilege scopes or cash/UPI proof.
- Keep PR #25 Draft until the full signoff protocol is satisfied.
