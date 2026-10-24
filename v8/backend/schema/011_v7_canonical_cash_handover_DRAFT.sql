-- DISPOSABLE v8_test ONLY. No production migration/installer.
-- Independent cashier evidence and ONE canonical V7 GL remittance source.
-- Existing V7 journal_entries + journal_lines are the ONLY financial ledger.
CREATE TABLE IF NOT EXISTS wp_eh7_b2b_cashier_receipts_uat (
 id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
 company_id BIGINT UNSIGNED NOT NULL,branch_id BIGINT UNSIGNED NOT NULL,
 sale_id BIGINT UNSIGNED NOT NULL,employee_id BIGINT UNSIGNED NOT NULL,
 cashier_employee_id BIGINT UNSIGNED NOT NULL,cashier_user_id BIGINT UNSIGNED NOT NULL,
 receipt_reference VARCHAR(128) NOT NULL,amount_paise BIGINT NOT NULL,
 status VARCHAR(20) NOT NULL DEFAULT 'confirmed',
 consumed_remittance_id BIGINT UNSIGNED NULL,received_at DATETIME NOT NULL,
 UNIQUE KEY once_per_sale (company_id,sale_id),
 UNIQUE KEY one_branch_reference (company_id,branch_id,receipt_reference),
 UNIQUE KEY one_remittance (consumed_remittance_id),
 CHECK (amount_paise>0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS wp_eh7_b2b_cash_remittances (
 id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
 company_id BIGINT UNSIGNED NOT NULL,branch_id BIGINT UNSIGNED NOT NULL,
 sale_id BIGINT UNSIGNED NOT NULL,employee_id BIGINT UNSIGNED NOT NULL,
 receipt_id BIGINT UNSIGNED NOT NULL,cashier_employee_id BIGINT UNSIGNED NOT NULL,
 checker_user_id BIGINT UNSIGNED NOT NULL,checker_employee_id BIGINT UNSIGNED NOT NULL,
 amount_paise BIGINT NOT NULL,request_key VARCHAR(128) NOT NULL,
 request_fingerprint CHAR(64) NOT NULL,journal_entry_id BIGINT UNSIGNED NULL,
 status VARCHAR(20) NOT NULL DEFAULT 'pending',created_at DATETIME NOT NULL,
 UNIQUE KEY one_cash_remittance_per_sale (company_id,sale_id),
 UNIQUE KEY one_cash_receipt (receipt_id),
 UNIQUE KEY one_remittance_request (company_id,request_key),
 CHECK (amount_paise>0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
