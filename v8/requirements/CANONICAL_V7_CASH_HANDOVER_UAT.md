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

## 2026-10-22 — Cashier identity and ledger replay hardening

The disposable UAT cashier receipt is bound to the authenticated cashier's
`user_id` and `employee_id`. Before this change, a different finance-authorized
cashier could potentially POST a coworker's valid attestation because only
seller-versus-cashier separation was checked; the remittance fingerprint
referenced the current poster rather than proving the original attester.

- Both `attest()` and `post()` must now agree on the **same authenticated
  cashier user ID and employee ID**. The cashier must remain separate from
  the original employee/sale maker. The actor is server-side and the amount
  comes from the locked original sale, never browser form values.
- Idempotent remittance replay verifies original company/branch, employee,
  cashier employee, receipt ID, original amount, request key and consumed ID.
- Original V7 Cash remittance GL header replay must have the original branch,
  company, remittance source ID and posted state. Read **all** journal lines
  with an account LEFT JOIN so foreign/missing-account lines cannot disappear
  from the proof check. Only the exact original Dr BRANCH_CASH and
  employee-tagged Cr EMPLOYEE_CASH_IN_TRANSIT pair qualifies.
- Read-only B2B cross-ledger audit rejects mismatch between the original
  cashier receipt and posted remittance cashier employee ID.
- Disposable real MariaDB tests separately exercise a second authorized
  cashier before posting and on replay, altered cashier identity, altered
  branch on remittance, and altered GL branch; temporary SQL tampering is
  restored in the isolated UAT database. No live cashier action was invoked.

**Not production-certified:** this is in isolated `v8_test` UAT only, not
physical Cash proof on the Office staging or production ERP. No new HTTP route,
financial writer, migration, deployment or changed real customer records.
