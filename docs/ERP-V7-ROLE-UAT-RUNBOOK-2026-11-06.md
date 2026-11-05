# Excel Herbal ERP V7 — Staff/Manager/Finance UAT Runbook
**Prepared:** 2026-11-05  
**Planned execution:** Friday, 2026-11-06  
**Status:** PLAN ONLY — human role-based end-to-end UAT not executed or certified.  
**Frontend source base:** PR #42 merged, plus return-guidance follow-up (pending CI).  
**Production site:** https://office.excelherbal.in/  
**Safety:** NEVER create financial, stock, payroll, refund or employment transactions in production to test a feature. Run with synthetic users, inventory and transactions in an explicitly isolated/sanitised UAT environment after verifying its host, API, database and role/branch projections. Read-only live checks are separate.

## What to verify before anyone tests
1. Record deployed **frontend folder version** from root HTML; do not infer from GitHub merge or WordPress installer plugin version. Record backend source SHA from the public health endpoint without posting data.
2. Verify tested UAT is an isolated, clearly labelled environment and that its API target and database are **not** production. Confirm no real staff data is present. If not verified, stop transaction tests.
3. Prepare synthetic B2C and distributor customers, main products, two branches, available stock, payment account, and separate user accounts with scoped permissions: Staff, Branch Manager, Finance Maker, Finance Independent Verifier, Head Office Approver.
4. Note actual permissions and assigned branches (job titles never grant access). Do not share real passwords; do not seed real bank/UPI references.
5. On desktop and a 320px phone at 1.6x text, verify all primary task buttons, errors, status receipts and back navigation remain usable.

## Daily staff and manager test cases — score unaided
| ID | Role | Task | Expected / hard stop | Pass target |
|---|---|---|---|---|
| S01 | Staff | Open Home and find Today's Duty | Automatic GPS/duty status visible; no fake manual attendance | <=30s |
| S02 | Staff | Start Daily Order and save draft | Products & PCS self-explanatory; draft ID, no stock posting | <=2min |
| S03 | Staff | Review and submit Daily Order | Explicit quantity summary; next actor shown; no duplicate submission | <=2min |
| S04 | Staff | Reopen issued order for Evening Closing | Correct issued order; no duplicate closing action | <=60s |
| M01 | Branch Manager | Find Pending Daily Orders | Only branch-assigned data; next action clearly stated | <=60s |
| M02 | Branch Manager | Attempt self-approval of own order | Maker-checker denied by server; message explains why | No bypass |
| M03 | Branch Manager | Issue and receive stock with mismatch | Permissioned transitions and discrepancy record; no silent correction | No bypass |

## Sales, Finance and Refund tests — synthetic only
| ID | Role | Task | Expected / hard stop | Pass target |
|---|---|---|---|---|
| F01 | Sales | Create B2C prepaid order | Stock, channel, discount fields validated; only one record created | <=2min |
| F02 | Branch Manager / HO | Approve discount within delegated limit | Larger amount escalates to HO; approver cannot approve own request | No bypass |
| F03 | Sales | Try invoice with payment short by ₹0.01 | Invoice action blocked; remaining 0.01 shown | No invoice |
| F04 | Sales | Try to record more than outstanding payment | Inline validation before submission, no duplicate collection | No overpayment |
| F05 | Finance | Record synthetic UPI payment pending verification | Must not enable invoice while pending | No invoice |
| F06 | Independent Finance | Verify UPI with separate bank evidence | Requires independent authorised verifier; no screenshot-only approval | Audit trail |
| F07 | Sales | Post fully paid approved order | Exactly one invoice and authorised stock/journal effects | 1 invoice |
| F08 | Sales / Finance | Request full return on posted order | Physical receipt & independent decision; no payout or stock return implied | No auto payout |
| F09 | Finance | Submit/verify refund evidence | 'Evidence checked — no payout recorded' remains explicit | No credit note |
| F10 | All | Switch branch during slow order/return fetch | Old branch records disappear immediately; no wrong branch write | No leakage |
| F11 | Cashier | Record pending Cash by malformed API fixture | Fail closed; NOT shown as UPI verification pending | No invoice |

## HR, navigation and mobile tests
| ID | Role | Task | Expected / hard stop | Pass target |
|---|---|---|---|---|
| H01 | HR | Open authorised employee from Organization | One canonical employee record; no duplicate entry form | <=60s |
| H02 | HR | Submit synthetic leave / separation path | Approval status, required details and assigned next actor visible | No silent approval |
| N01 | Staff | Find My Tasks, Notifications, Global Search | All shortcuts open canonical screens; no duplicate drawer clutter | <=45s |
| N02 | Any | Use 320px phone with 1.6x text | No horizontal overflow; task buttons usable and labelled | 0 overflow |
| N03 | Any | Drop internet before final confirmation | No falsely posted invoice/refund; recoverable error / draft | 0 duplicate writes |

## Evidence and release gate
Record for each case: **date/time, UAT URL, frontend build, backend SHA, role/capability projection, branch, tested task ID, result (Pass/Fail/Blocked/Not Run), actual screen outcome, screenshot or sanitized log, defect link and reviewer**. Never capture secrets, account numbers, real customer data or medical information.

**Go / No-Go:** No release sign-off until all finance/stock/maker-checker critical tests pass, unknown-branch and role-scope tests pass, and a first-time staff pilot achieves >=90% task success without coaching. Error reproduction and escalation should work from a single canonical workflow. A green GitHub CI alone does **not** meet this acceptance gate.

## Next-day execution sequence — Friday, 2026-11-06
- 09:30–10:00 IST: verify Live version, isolated UAT credentials, API and data separation. Stop if not isolated.
- 10:00–11:30 IST: Staff + BM synthetic Daily Order, attendance and branch-scoping tests.
- 11:30–13:00 IST: Finance maker/checker, Cash/UPI, underpayment and discount approval tests.
- 14:00–15:00 IST: Returns and manual evidence with explicit no-payout check.
- 15:00–16:00 IST: Mobile UX, accessibility and role-based navigation pilot; log defects by severity.
- 16:00 IST: publish actual UAT pass/fail/blocked scorecard, fix high-severity reproducible defects, and decide next reviewed release. Times are a proposed run plan, **not a scheduled automation or promise of unattended work**.

## Deployment discipline
Use **existing** WordPress UI Refresh Installer slug for any new frontend release, replacing rather than adding a plugin. Review the CI web artifact source SHA/tree against the merged commit; keep existing frontend folder for rollback. Never claim deployment from a GitHub merge or upload alone: inspect Live root HTML and backend health afterwards.
