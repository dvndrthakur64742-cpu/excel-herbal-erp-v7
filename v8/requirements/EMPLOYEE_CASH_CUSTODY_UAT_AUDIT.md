# Employee Cash Responsibility / Cashier Handover UAT Audit

Read-only UAT adapter `UatEmployeeCashCustodyHistory` is built on existing
preview sales, employee cash responsibility, independent cashier attestation,
receipt consumption and remittance journal records in disposable `v8_test`.
No new stock table, ledger table, sales header or public WordPress route.

For each original field-Cash retailer sale:
- Before handover: employee_cash_pending, remitted zero.
- Only a consumed cashier receipt with independent actor and exact full
  remittance, matching balanced two-line custody journal, can report
  cashier_remittance_evidenced.
- Missing/tampered evidence: reconciliation_mismatch, remitted zero.
- Handover NEVER creates another retailer sale or retail income.
- Finance viewer must be permitted by a trusted server-side authority.
- All UAT readers and remittance writers reject wrong DB and schema switch.

**Release gate:** This is NOT canonical V7 GL posting and not real bank
deposit verification. Existing V7 Cash-in-Transit debit at sale can be posted
through canonical B2B UAT, but its corresponding V7 GL reclassification on
cashier handover is NOT implemented here. That requires owner-approved
canonical source type, reversal policy, period close rules, maker/checker
and real WordPress MariaDB UAT. No production deployment or PR merge.
