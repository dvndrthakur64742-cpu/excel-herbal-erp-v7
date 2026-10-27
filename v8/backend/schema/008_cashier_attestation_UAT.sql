-- Disposable v8_test ONLY. Depends on 001 + 002 UAT schemas.
-- One independently attested physical cash receipt per paid field sale.
-- Atomic with v8_b2b_verified_branch_receipts and keyed to its receipt ID.
CREATE TABLE IF NOT EXISTS v8_b2b_cashier_receipt_attestations (
  receipt_id BIGINT UNSIGNED NOT NULL PRIMARY KEY,
  company_id BIGINT UNSIGNED NOT NULL,
  branch_id BIGINT UNSIGNED NOT NULL,
  sale_id BIGINT UNSIGNED NOT NULL,
  employee_id BIGINT UNSIGNED NOT NULL,
  cashier_actor_id BIGINT UNSIGNED NOT NULL,
  amount_paise BIGINT NOT NULL,
  cash_receipt_reference VARCHAR(128) NOT NULL,
  verified_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_attested_sale (company_id,sale_id),
  UNIQUE KEY uq_attested_reference (company_id,branch_id,cash_receipt_reference),
  CHECK (amount_paise > 0)
) ENGINE=InnoDB;
