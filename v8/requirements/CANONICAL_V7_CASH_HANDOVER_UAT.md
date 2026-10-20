# Canonical V7 Cashier Handover — large development batch (UAT only)

**Built on the existing V7 Chart of Accounts and AccountingService::post**,
not a second general ledger. Independent cashier creates a disposable signed-in
session receipt for an already posted *field Cash* B2B sale with an existing
employee-tagged Cash-in-Transit debit. The independently authorized cashier
then posts one new canonical journal:

| Debit | Credit |
|---|---|
| BRANCH_CASH — full exact amount | EMPLOYEE_CASH_IN_TRANSIT — full exact amount, tagged to original employee |

The full request amount is always loaded from locked original canonical sale
and original tagged GL. Nothing trusts a mobile-supplied actor, price or amount.
Receipt consumption, unique one-per-sale remittance, V7 AccountingService
posting, and idempotency all happen on the SAME wpdb/MariaDB transaction.

**Operational controls:** different seller/cashier identities, separate
server-side finance authorization; branch permission; company/period lock;
business-day closing check; unique receipt/reference, sale and request keys;
GL line validation on replay; journal failure rollback; no stock movements,
duplicate sales or customer credit on handover. Only whole/full remit is
supported; exceptions/shortages require business policy approval.

**Delivery gate:** UAT-only class and DRAFT test tables in disposable
`v8_test`. No production REST action, migration, deployment, payment provider,
or owner approval for tax/HSN and reversals. `AccountingService` merely adds
a source type mapping; it cannot post without the DRAFT source table and a
guarded authorized caller. Live ERP remains unchanged.

**Employee 360:** Finance-only Cash Responsibility tab filters original V7
employee-tagged journal lines to FIELD Cash receipt debits and cashier
handover credits. The canonical account ledger may return a limited history;
no authoritative outstanding balance is inferred from that excerpt. Employee
dashboard and its price visibility remain unchanged.
