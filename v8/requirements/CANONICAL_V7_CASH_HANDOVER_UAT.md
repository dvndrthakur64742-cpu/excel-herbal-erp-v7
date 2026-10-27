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

## 2026-10-24 — UAT-only separate cashier and finance checker

**Risk found during canonical rollout audit:** the previous isolated `v8_test`
flow allowed the same authenticated cashier who created the physical receipt
to post its GL remittance. Cashier-vs-field-seller separation alone does not
establish independent maker-checker approval.

**Implemented inside disposable UAT only:**
- Original authenticated cashier still uniquely attests the full exact-amount
  posted B2B field Cash sale. Only this human owns the receipt reference;
  self-attestation by original field seller remains forbidden.
- A **different** authenticated Finance checker must independently execute
  `cash_remittance.post` with the authorized branch capability. It is rejected
  when either checker user ID or employee ID equals the original cashier,
  seller or original maker. A cashier holding both privileges still cannot
  approve their own receipt.
- UAT draft remittance source stores `checker_user_id` and
  `checker_employee_id` separately from original
  `cashier_employee_id`/the receipt's `cashier_user_id`. The unique
  source and receipt constraints, exact amount, posted original Cash-in-
  Transit debit, account custody, closed period and atomic V7 journal remain
  unchanged.
- Remittance idempotency hash and replay validation bind source company,
  branch, sale ID, cashier receipt/actor and Finance checker identities;
  a second approved checker cannot adopt the first checker's posted journal.
- The read-only cross-ledger audit rejects a forged checker-as-cashier record
  or altered identity before treating Cash handover as reconciled. Duplicate
  Cash postings, stock movements, performance points, remittances or Cash
  proof consumption remain prohibited.
- Real MariaDB UAT asserts no receipt -> no journal, cashier self-approval
  blocked, unauthorized/second cashier denied, a genuinely independent
  checker posts exactly one debit BRANCH_CASH / credit employee-tagged
  EMPLOYEE_CASH_IN_TRANSIT entry, GL insert failure fully rolls back,
  tampered checker identity fails audit/replay and exact retry is idempotent.

Dedicated disposable GitHub Actions workflow:
`.github/workflows/v8-cashier-finance-checker-real-mariadb-uat.yml`.
This is **not** a production writer or schema migration. It uses only the
runner-local `v8_test` database, has no Office credentials, and cannot mark
physical money delivered in live V7 Daily Orders. Actual employee Cash
handover, bank/PSP source, tax/reversal policy, sanitized staging UAT and
production authorization remain separately gated.

## 2026-10-24 — Signed bank/UPI companion CI gate

The dedicated disposable MariaDB workflow now also executes
`v8/backend/tests/signed_bank_reconciliation_mariadb.php` immediately after
the 129-case canonical Cashier/Finance-checker suite, on the SAME runner-local
`v8_test` service under a distinct company ID. Both suites must print their
non-SKIP audited PASS summary, and any failure blocks the CI job.

The companion UPI test uses a **synthetic, internally HMAC-signed bank-feed
record**, not a bank webhook or authenticated production PSP. It verifies
server-owned signing key, merchant/account binding, exact INR amount and
order/reference linkage, fresh settled status, duplicate transaction race,
wrong-company/branch, tampered records and signer revocation; it must not
fabricate live UPI verification. Neither suite has access to Office credentials
or posts production journals. This is an automated UAT gate only.

## 2026-10-24 — Finance checker must match AUTHOR of actual GL journal

Review identified a second identity-integrity gap in the isolated UAT:
`checker_employee_id` on the cashier remittance was checked against the
receipt and stored source, but the existing `journal_entries.created_by`
field from the real V7 `AccountingService::post` was not compared. An
altered journal header could therefore remain fully debits/credits-balanced
without attribution to its true Finance checker.

**Fail-closed checks:** the remittance idempotency replay now selects
`journal_entries.id, created_by` and requires the author ID to match the
independent authenticated `checker_employee_id` stored on that remittance.
The read-only cross-ledger auditor independently applies this check to the
same ORIGINAL canonical journal, returning
`canonical_handover_journal_header_mismatch` on a discrepancy. No custom
shadow-GL, user-supplied checker flag or new posting is introduced.

The real disposable MariaDB UAT asserts the valid checker is the GL author,
then deliberately changes `created_by` to the original cashier while
leaving the two journal lines balanced, verifies the audit and replay both
reject it, and restores the original synthetic journal. This is *UAT only*.
No WordPress schema, real user, Office ledger or financial record is changed.
