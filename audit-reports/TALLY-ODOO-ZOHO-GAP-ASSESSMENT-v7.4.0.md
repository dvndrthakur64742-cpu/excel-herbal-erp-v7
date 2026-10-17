# Excel Herbal ERP V7 — TallyPrime / Odoo / Zoho ERP Gap Assessment

Assessment date: 2026-10-17  
Repository: `dvndrthakur64742-cpu/excel-herbal-erp-v7`  
Status: BUILD/UAT only — this is not production approval.

## Executive assessment

Excel Herbal ERP is a purpose-built, branch- and hierarchy-scoped distribution ERP with workforce GPS, employee performance points, stock transfers, sales/purchase, finance, payroll, HR lifecycle, and reporting code. The source contains broad workflows, but source presence is not proof of production readiness: current release gates still require a successful exact-head CI run, controlled staging restore, real HTTPS Bearer tests, physical Android GPS pilot, private-document recovery drill, and Accounts/operations reconciliation/sign-off.

The most important differentiation is the business-specific employee experience: employees should see only their own sales and performance/incentive points; prices and monetary totals remain hidden on the employee dashboard. Duty is intended to be server-owned from 10:30 AM to 5:00 PM, with a road map displaying recorded GPS points. This tailored flow is not a like-for-like replacement for every standard feature in the comparator suites.

## Functional comparison

Legend: **Source** = relevant code/workflow exists in this repository; **Partial / UAT** = code exists but end-to-end or operational proof is pending; **Gap / verify** = not certified as implemented from the current evidence. A source-only assessment must not be read as business acceptance.

| Capability | Excel Herbal ERP V7 | TallyPrime | Odoo | Zoho ERP |
|---|---|---|---|---|
| Core accounting / journals / ledger | Source: finance accounts, journals, periods, reversals and reports; staging balance/reconciliation review pending | Core strength: accounting vouchers, ledgers, bill-wise accounting and financial reports | Integrated Accounting app and finance reporting | Core-financials, chart of accounts, journals, banking and period locks |
| Trial Balance, P&L, Balance Sheet | Source; Accounts must reconcile against controlled transactions before acceptance | Standard financial reporting | Standard accounting/reporting apps | Standard financial reporting |
| India tax / GST / e-invoice / e-way bill | Gap / verify: do not claim statutory end-to-end filing as certified without specific integration tests | Strong India compliance feature set documented by vendor | Depends on India localization, edition, configuration and implementation | Vendor advertises India tax compliance; validate exact plan and statutory workflows |
| Sales / counter sales / receipts / receivables | Source; UAT must prove stock, receipts and outstanding balances | Sales vouchers, invoicing and receivables | Sales, CRM and POS apps integrated | Sales and receivables workflows |
| Purchase / suppliers / supplier payments | Source: bills and payments; formal PO → GRN → bill chain needs separate proof | Purchase process, inventory and payables | Purchase + Inventory workflows | Purchase and inventory workflows |
| Stock ledger / batches / transfers / adjustments | Source: stock, transfers, adjustments, quarantine; end-to-end valuation reconciliation pending | Inventory, godowns, batches, costing and transfers | Warehouse operations, routes, barcode, manufacturing integration | Multi-warehouse inventory, transfers, adjustments, stock counts and batch/serial support |
| Manufacturing / BOM / production planning | Gap / verify; not certified production-complete | Inventory/job-work/manufacturing features vary by configuration and scope | Dedicated Manufacturing, BOM and PLM apps | Dedicated Manufacturing and assemblies capabilities |
| CRM / leads / opportunities / customer pipeline | Gap / verify: customer master and sales are not proof of a full CRM pipeline | Check required CRM scope and add-ons/integrations | Dedicated CRM app | CRM and sales-channel integration should be checked against chosen Zoho product/plan |
| HR / employee lifecycle / leave | Source: employee, candidate, joining, separation, leave and documents; UAT pending | Employee records, payroll and attendance reports | Employees, Recruitment, Time Off and other HR apps | People, onboarding, leave/attendance and payroll workflows |
| Payroll / payslips / statutory compliance | Source for payroll engine and approval controls; statutory filing, payout and historical payroll acceptance still need UAT | Payroll and attendance/payslip capabilities documented | Payroll availability/localization depends on country, edition and implementation | Automated payroll, statutory compliance and payslips documented; validate India plan |
| Workforce GPS road route | Custom capability: GPS points, hierarchy-scoped route API and OpenStreetMap route view; physical-device pilot pending | Not a core capability established by the cited standard feature list; likely needs integration/customisation | Field Service/Fleet/Planning apps exist; exact GPS duty-route flow requires configuration/add-ons | Beat management, time tracking and field operations listed; exact road-route duty flow requires product/plan verification |
| Employee-only sales + incentive points; hide prices | Custom requirement; source regression checks cover dashboard monetary-field exclusion | Standard accounting/inventory product, not the same tailored employee dashboard contract | Can be customised with access rights/views | Can be configured across people/sales apps, but exact privacy/points rules need custom configuration |
| Branch / hierarchy access control | Custom source architecture with effective capability + branch + reporting hierarchy; live UAT still required | User/security and multi-company/remote-access capabilities | Multi-company and granular access, depending on edition/configuration | Role-based access and distributed operations; exact hierarchy policy needs configuration |
| Audit / maker-checker / idempotency | Source guardrails and regression tests; real multi-user staging evidence required | Edit Log and audit controls are documented | Approval rules, access rights and audit capabilities vary by app/configuration | Transaction locks, approvals and audit trail features vary by workflow |
| Bank feeds / auto reconciliation / payments | Bank reconciliation source exists; live bank feed and payment-provider integration not certified | Connected Banking and bank reconciliation features documented | Bank synchronization depends on provider/country/configuration | Vendor documents banking feeds and reconciliation; provider coverage varies |
| Offline mobile operation | Not certified; Android GPS pilot is still a release gate | TallyPrime offline/connected access options depend on workflow | Mobile/web access exists; offline behaviour must be validated per app | Mobile/web availability does not imply offline transaction support |
| Integrations / APIs / extensibility | WordPress REST API and Flutter app; integration tests/release gates pending | Import/export, connected services and integrations | Broad modular app ecosystem and external API features depend on edition | APIs/connectors and cross-product integrations; plan-specific verification required |

## Current Excel Herbal ERP strengths

1. **Distribution-oriented workflows**: counter sales, receipts, purchase bills/payments, stock transfers, stock adjustments/quarantine and branch-aware reporting exist in source.
2. **Authority model**: source separates capabilities, authorised branches and reporting hierarchy; UI hiding is backed by server guards.
3. **Workforce customisation**: duty window, GPS points/routes, employee-only performance dashboard and incentive points are tailored to the requested operating model.
4. **Accounting controls**: source includes journals, period controls, bank reconciliation, reversals and financial reports; correctness must still be proven against controlled transactions.
5. **Security/regression infrastructure**: PHP/static checks, Flutter tests, disposable MariaDB and release-gate workflows exist; the current exact-head verification is queued, not passed.

## Priority gaps before calling the ERP complete

### P0 — correctness and release safety
- Obtain a **green exact-head CI** result; current run is queued.
- Configure host-level cron to invoke WordPress-Cron reliably, then verify duty attendance materialisation and 5 PM closure on controlled staging. WordPress-Cron is traffic-triggered and is not a hard real-time scheduler by itself.
- Run the physical Android GPS pilot: permissions, background/resume, point acceptance, route rendering, 5 PM cutoff, logout stop.
- Complete backup/restore proof on a controlled staging copy, including a protected backup of the private-document encryption key and a recovery drill.
- Perform HTTPS Bearer login/refresh/revocation and expected 401/403 tests against controlled staging.
- Reconcile Sales, Purchase, Stock, journals, Receivables, Payables, Trial Balance, P&L, Balance Sheet and Finance Reconciliation with known expected values.

### P1 — functional completeness
- Certify the full Purchase Order → Goods Receipt (GRN) → supplier bill → payable flow, including partial receipt, rejection/return, batch/cost and accounting postings.
- Verify GST/HSN/SAC, tax calculation, invoice numbering, e-invoice/IRN, e-way bill and statutory return exports; explicitly document any integrations not implemented.
- Decide and test whether CRM opportunity pipeline, manufacturing/BOM, expiry/lot traceability, barcode, offline sync and automated bank feeds are in scope. Do not market these as complete until implemented and tested.
- Keep salary/rewards/promotion workspaces fail-closed unless their APIs, maker-checker rules, persistence, audit and tests are complete.

### P2 — operations and acceptance
- Resolve environment classification/hardening only after backup/restore evidence.
- Complete private HR document upload/download/revocation/recovery drill.
- Obtain HR, Accounts and operations sign-off using synthetic UAT identities and recorded evidence.
- Keep the PR in draft until exact-head CI passes; production approval and deployment are separate decisions.

## Recommended positioning

Position Excel Herbal ERP as a **custom distribution and field-workforce ERP under build/UAT**, not yet as a feature-for-feature replacement for TallyPrime, Odoo or Zoho ERP. The strongest differentiation is branch/hierarchy controls plus GPS-based workforce operations and the employee privacy contract. Prioritise accounting reconciliation, tax compliance proof, purchase/GRN completion and real-device UAT before expanding into CRM/manufacturing or advanced integrations.

## Public comparator references

- TallyPrime — official features and capabilities: https://help.tallysolutions.com/tallyprime-get-started/
- TallyPrime — official feature/release overview: https://help.tallysolutions.com/tallyprime-features-release-wise/
- Odoo — official app catalogue: https://www.odoo.com/page/all-apps
- Odoo — official documentation application index: https://www.odoo.com/documentation/16.0/applications.html
- Zoho ERP — official feature catalogue: https://www.zoho.com/en-in/erp/all-features/
- Zoho ERP — official product overview: https://www.zoho.com/en-in/erp/

Vendor feature lists describe available product capabilities, not necessarily features included in every edition, subscription or India deployment. Confirm edition, localisation, add-ons and implementation scope before using this matrix for procurement decisions.
