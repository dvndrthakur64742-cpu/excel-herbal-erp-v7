# Excel Herbal ERP V8 — Canonical Business Logic / Module Register

**Version:** v8 foundation, 2026-10-17. This is a source-derived roadmap, NOT a statement of implementation completion.

## Authoritative rules

- Company sells herbal products via **Field Sales, Counter Sales and B2B Retailer Sales**; retailer is a customer class, while field/counter are channels. One underlying sale must never be double counted.
- **B2B-PAY-001 approved:** retailer pays full amount immediately with **Cash or UPI**, no credit/outstanding on posted retailer invoice. The backend must reject any incomplete/unverified tender irrespective of UI choice. Split tender remains unapproved and blocked for this first slice.
- Cash received by a field employee creates **employee cash remittance due to branch**, not retailer trade receivable. Retailer balance must stay zero.
- Approved V7 commercial definition: `sale_price = ho_amount + bm_profit + salary_fund + office_expense`. `purchase_cost` and `points` are separate fields; revision effective-date/snapshot preserved. Retailer discounts/points policy not yet authorized.
- Product issue is **not** a sale. Warehouse stock, field-employee custody, returned stock, sold stock and source accounting must reconcile. Unissued/expired/negative stock cannot be sold.
- Employee duty/GPS is server-owned 10:30 AM–5:00 PM, no employee manual start/stop. Manager maps recorded GPS points only within authorized branch and reporting hierarchy; physical GPS permission and outage states need real device tests.
- Employee **dashboard**: only own sales/activity and incentive points; no prices/monetary totals. Profile and management views have separate field-level permissions.
- No historical journal edits: use approved reversals, refunds and source-linked corrections; journal Dr = Cr; require maker-checker where applicable.
- Single source transaction, stable IDs, audit history, unique idempotency keys and rollback on failure; no separate duplicate stock/sales/financial engines.

## Modules and current V8 build status

| Module | Canonical workflow / invariant | V8 first slice |
|---|---|---|
| 01 Organization | Company, head office, branch, reporting hierarchy | Planned; V7 reference only |
| 02 Identity/Access | Effective roles + capability + branch + hierarchy, deny-by-default | Gateway contract only |
| 03 HR Lifecycle | Candidate -> selected -> joined; approval -> offboarding | Planned |
| 04 Employee 360 | Jobs, movements, sales, stock, points, cash, payroll, attendance, GPS, documents | Planned |
| 05 Products/Pricing | Active revision, MRP, split, purchase cost independent, points snapshot | Basic server catalog validation built |
| 06 Procurement | Supplier -> purchase bill -> warehouse stock -> payables | Planned |
| 07 Stock/Ledger | Warehouse, employee custody, batches, valuation, FEFO/expiry | Qty/custody port and validation built; persistence pending |
| 08 Transfers | Draft -> packed -> transit -> received; discrepancy audit | Planned |
| 09 Field Morning | Request -> independent approval -> issue -> custody | Planned; preserve V7 and v14 role insights |
| 10 Field Evening | Sold retail + sold wholesale + returned = issued; cash/UPI reconcile | Planned |
| 11 B2B Retailer | Retailer -> order -> full verified cash/UPI -> invoice -> dispatch -> history | **Domain prototype built**; production gateway/UI pending |
| 12 Counter Sales | Branch stock -> invoice -> payment & ledger | Planned; V7 reference |
| 13 Customer/Retailer Ledger | Party history vs general ledger; retailer zero outstanding; refunds separate | Prototype sale/receipt and journal design |
| 14 Accounting | Chart of accounts, journal, trial balance, P&L, balance sheet | Balanced posting specification built; adapter pending |
| 15 Cash/Bank/UPI | Branch cash, UPI clearing, employee cash-in-transit, bank reconciliation | Abstract journal accounts built; settlement pending |
| 16 Attendance/Leave | Attendance policy separate from GPS; salary grade decisions | **Business policy conflict: pending** |
| 17 GPS/Field Visits | Auto duty 10:30–17, location points, road route, access restriction | Planned; V7 reference |
| 18 Payroll | Proration, Salary Fund, bonuses/deductions, approver & payment | Planned |
| 19 Performance | Performance points and targets; no automatic money conversion | B2B point auto-post intentionally disabled |
| 20 Reporting | Central net sales, stock & finance recon, user-scoped sales and points | Planned |
| 21 Approvals/Audit | Maker/checker, delegated authority, immutable history | Planned |
| 22 Documents/Communication | Tasks, notification, private HR documents | Planned |
| 23 Reversal/Closing | Daily/period locks; refund/reversal maker-checker | Planned |
| 24 UX/Flutter | Single workspaces, employee/manager/admin navigation | Planned |

## Source conflicts to resolve, not guess

1. **Attendance**: V14 manual clock-in and 09:00–18:00 BRD policy vs V7 server-owned 10:30–17:00 attendance and GPS. Keep GPS confirmed; separate attendance remains owner decision.
2. **Unsold stock**: BRD example allows 8 unsold pieces with employee; current V7 evening close expects 8 returned before completion. Decide carry-forward vs mandatory return.
3. **Retailer price**: base list price or special retailer/quantity rate? Which commercial components absorb discount? No unsupported 50:50 assumption for B2B.
4. **Credit for non-retailer**: current V7 can create customer credit sales; B2B retailer must not. Do not silently alter other customers without approval.
5. **Counter/Field overlap**: sales channel, selling employee, retailer ID are different dimensions; one canonical row and source ID.
6. **UPI verification**: cash receipt must have signed operator acknowledgment; UPI must be verified from trusted source rather than payer screenshot.
7. **Refund/return**: when and by whom refunds/credit notes are authorized remains undecided. Original invoice never destructively edited.
8. **Tax and invoicing**: applicable GST/HSN rules, tax-exclusive/inclusive pricing and compliant invoice numbering require owner/accountant confirmation.

## Red flags from v14 audit (not automatically imported)

- Reported shortage-clamping defect; use signed cash variance, never clamp negative to zero.
- Legacy `purchase_cost = ho_amount` coupling; keep independent cost field.
- Legacy permissive same-branch manager review; enforce hierarchy and maker-checker.
- Legacy attendance handlers exposed manual check-in/out against confirmed GPS policy.
- Legacy lack of robust double-entry financial ledgers; reuse clean V7 finance rules, verify live reconciliation.
- v14 has no confirmed first-class retailer master with paid-only B2B settlement; do not assume it is already covered by a free-text wholesale name.

## Acceptance before any UAT deployment

PHP unit tests; MariaDB rollback/retry/concurrency; API RBAC and IDOR; batch expiry & FEFO; complete sale -> customer-paid receipt -> stock OUT -> balanced journal -> points policy decision -> employee cash remittance; counterfeit UPI receipt rejection; customer/refund/reversal flows; finance and stock reconciliation; Flutter analyze/test; role-by-role mobile/browser UAT; backups/restores; owner signoff. Production deployment requires a separate explicit approval.