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

## 2026-10-26 — Live read-only preview verified; mobile closing inputs implementation

- Staging Office web confirmed by authenticated health, `web_runtime.source_head=54b791a327ceccabce9008916fb41b077a89de4f`, SHA-256 `937150f36db3ac154a8437059e15c903bc4648d38d4140ff3d83b9820806e663`. Backend remains `95a9e2806edef95257cd6b6aee6f1d56ca632d6b`. GitHub web deployment run `40096043676` succeeded. **Only read-only web-preview installation is verified, not human business UAT.**
- Current development enhancement: mobile-friendly per-product Return/Wholesale Qty/Rate cards in Evening Closing. This is presentation-only. Original whole-PCS parsing, issued-stock checks, retailer rate constraints, unsaved-draft exit, and canonical Save/Submit REST endpoints are unchanged.
- Flutter widget coverage targets widths 320, 360, 390, 768 and 1366. Exact new commit/run ID and acceptance outcome to be verified before promoting this implementation to `CI_VERIFIED`.
- Office is not sanitized and active mobile sessions are not confirmed zero; therefore **do not auto-deploy this next build**. Actual authenticated Employee/ASM/Manager staging acceptance and cashier/stock reconciliation still require an isolated safe UAT procedure.

## 2026-10-26 — Phase 1 Finance Checker final-post proof-labeling hardening

- Corrected the critical UX distinction between **reported Cash/UPI entries** and **independently verified custody or bank settlement**. The current canonical V7 Final Post records GL/stock/performance but is not evidence that cash was handed to an independent cashier or UPI settled at a bank.
- The Finance Final Post dialog now starts with both Cash and UPI amounts blank (no fabricated all-Cash default), requires the checker to type both amounts explicitly (zero is allowed), validates both parsed numbers and exact source/server sale reconciliation, and requires an explicit acknowledgement of missing independent proof before enabling Final Post.
- The same guard is rechecked before the original `ApiPaths.finalPost(id)` call. The canonical backend POST payload, roles, maker-checker rules and accounting/stock writers **are unchanged**.
- Added accessible disclosure widget tests for 320/390/768/1366px screen widths and 1.25 text scale and CI contract checks. These are development acceptance tests, not real cash-receipt or bank-proof verification.
- No Office deploy or financial mutation. Existing Office staging remains the earlier read-only V8 preview. Human role/device UAT, independent cashier receipt, bank confirmation, rollback drill, sanitized rehearsal and accounting sign-off remain open.

## 2026-10-26 — Daily Order role-visible Additional Stock closing hold

- Source: `DailyOrderWorkflow.additionalClosingHold`; `V8DailyOrderCard`; original authorised `my_work_daily_overview.dart`. The issued cycle clearly shows the missing step when an additional request is `draft`, `submitted` or `approved`. The view is **informational only**; it never grants approval, stock issue, branch access or Final Post rights.
- The original canonical V7 API retains the authoritative pending-additional check; the 2026-10-26 disposable MariaDB lifecycle tested submitted/approved holds without stock, settlement or GL mutations.
- The UI regression suite verifies real card layout at 320/390/768/1366px, original action callbacks, no hold after completed/cancelled additional requests, and source wiring.
- **Provisional engineering planning estimate (not acceptance percentage): roughly 55–60% developed**, based on original 22 October ~55% planning baseline, subsequent UI/regression work and ten scoped workstreams above. This is *not an audited numerator*, and should not be confused with the narrow earlier Finance review 3/5 checkpoints. The proposed 100-point weights remain unapproved and no certified overall completion percentage exists. Production readiness is separately `NOT SIGNED OFF`, with real role/device UAT, cashier receipt, bank UPI proof and safe restoration still open.
- Deployed Office V8 read-only preview stays at source `54b791a327ceccabce9008916fb41b077a89de4f`; development UI additions are NOT automatically deployed. No live business posting or DB mutation.

## 2026-10-26 — Measurable acceptance ratio and project completion discipline

- The Phase 1 field-day checklist in PHASE1_FIELD_DAY_E2E_ACCEPTANCE_20261026.md defines **exactly 10 real-user acceptance gates**: FE request, ASM approval, custody movement, additional stock, evening close, finance post, cashier proof, bank UPI proof, Employee 360 and sanitized staging/restore. **As of this audit 0 of 10 have recorded authenticated human role/device/financial evidence and reviewer sign-off.** Therefore the observed ratio for **THIS 10-gate user acceptance subset alone** is **0/10 = 0% UAT accepted**. This does not mean that 0% of V8 was developed.
- The existing three required automated CI workflows (Flutter, PHP/MariaDB, genuine WP role REST) are a separate **3/3 green on the previous verified source head**. Their new-head status must be checked after the discrepancy correction commit. A 100% passing CI subset is not 100% ERP.
- The proposed weighted overall engineering scope is 100 points spread across 10 workstreams; neither weights nor exhaustive module case denominators are owner-approved/frozen. The **actual audited full-ERP completion percentage remains NOT COMPUTABLE**, rather than a fabricated 58% score. The previous 55–60% is only a provisional development-planning estimate and should never be called actual.
- To publish an auditable actual overall percentage, freeze the feature/acceptance inventory and weights, tag exact source/build, attach automated and authenticated role/device UAT evidence for every weighted gate, and obtain owner/reviewer signoff. Until then, report countable ratios with explicit denominators and unresolved release blockers.
