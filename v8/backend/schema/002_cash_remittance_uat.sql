-- Excel Herbal V8 UAT-ONLY cash custody reconciliation; NEVER run on production.
-- Depends on 001_b2b_preview_mysql.sql and the existing v8_b2b_employee_remittance table.
-- Cashier evidence must be created by a separate authenticated, audited back-office
-- process; the B2B/employee REST request is NEVER permitted to create its own proof.
CREATE TABLE IF NOT EXISTS v8_b2b_verified_branch_receipts (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  company_id BIGINT UNSIGNED NOT NULL, branch_id BIGINT UNSIGNED NOT NULL,
  sale_id BIGINT UNSIGNED NOT NULL, employee_id BIGINT UNSIGNED NOT NULL,
  cash_receipt_reference VARCHAR(128) NOT NULL,
  amount_paise BIGINT NOT NULL, verified_source VARCHAR(30) NOT NULL,
  verified_at DATETIME NOT NULL, status VARCHAR(20) NOT NULL DEFAULT 'confirmed',
  consumed_event_id BIGINT UNSIGNED NULL,
  UNIQUE KEY uq_v8_branch_receipt (company_id,branch_id,cash_receipt_reference),
  CHECK (amount_paise > 0)
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS v8_b2b_remittance_keys (
  company_id BIGINT UNSIGNED NOT NULL,
  idempotency_key VARCHAR(128) NOT NULL,
  event_id BIGINT UNSIGNED NULL,
  result_json LONGTEXT NULL,
  PRIMARY KEY (company_id,idempotency_key)
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS v8_b2b_remittance_events (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  company_id BIGINT UNSIGNED NOT NULL, branch_id BIGINT UNSIGNED NOT NULL,
  sale_id BIGINT UNSIGNED NOT NULL, employee_id BIGINT UNSIGNED NOT NULL,
  actor_id BIGINT UNSIGNED NOT NULL, amount_paise BIGINT NOT NULL,
  cash_receipt_reference VARCHAR(128) NOT NULL,
  idempotency_key VARCHAR(128) NOT NULL, status VARCHAR(20) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_v8_remittance_one_per_sale (company_id,sale_id),
  UNIQUE KEY uq_v8_remittance_actor_key (company_id,idempotency_key),
  CHECK (amount_paise > 0)
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS v8_b2b_remittance_journal_lines (
  event_id BIGINT UNSIGNED NOT NULL, line_no INT UNSIGNED NOT NULL,
  account_code VARCHAR(40) NOT NULL, debit_paise BIGINT NOT NULL,
  credit_paise BIGINT NOT NULL,
  PRIMARY KEY (event_id,line_no),
  CHECK (debit_paise >= 0), CHECK (credit_paise >= 0)
) ENGINE=InnoDB;
