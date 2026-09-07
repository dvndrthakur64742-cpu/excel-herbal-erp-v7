# Excel Herbal ERP 7 — One-time Clean Setup

This setup path is for a **fresh EH7 installation only**. It is source-ready but must not be executed on the live office site until deployment/cutover is separately approved.

## What activation does

Plugin activation creates/upgrades only the `eh7_*` schema. It does **not** silently create business identities or post business transactions.

## One-time initialization

1. Activate the clean V7 plugin on an approved staging WordPress instance.
2. Sign in as a WordPress administrator and use normal WordPress REST authentication/nonce.
3. Check `GET /wp-json/excel-herbal-erp/v7/setup/status`.
4. When `initialized=false`, call `POST /wp-json/excel-herbal-erp/v7/setup/initialize` once with:

```json
{
  "company_name": "Excel Herbal",
  "branch_code": "HO",
  "branch_name": "Head Office",
  "employee_code": "ADMIN001",
  "employee_name": "First ERP Administrator",
  "mobile": ""
}
```

The values above are examples except the company name; use the approved real employee/branch codes at deployment time.

## Initialization creates

- Company and first Head Office branch.
- First ERP employee identity linked to the currently authenticated WordPress administrator.
- `SYSTEM_ADMIN` role with all current EH7 capabilities.
- Primary branch history and explicit branch authority.
- Canonical ledgers required by the engine: Cash, Bank, UPI, Inventory, AR, AP, Sales, COGS, Stock Variance, Payroll Expense, Payroll Payable and Office Expense.
- A starter Office General Expense head.

It does **not** create historical sales, purchases, stock, payroll, receivables, payables, journals or migration records.

## Safety

- Setup requires WordPress `manage_options`.
- It is protected by a database advisory lock and refuses to run after the first company exists.
- Roles never expand branch authority.
- Further role/capability and employee-role changes use Administration → Access and are audited.
