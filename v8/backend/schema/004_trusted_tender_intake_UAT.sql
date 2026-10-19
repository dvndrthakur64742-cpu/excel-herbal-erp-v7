-- Excel Herbal ERP V8 ISOLATED UAT ONLY. NEVER apply to live office.excelherbal.in.
-- Requires 001_b2b_preview_mysql.sql; NOT canonical company/branch/invoice migrations.
-- Intents are created only by trusted server-side order/pricing logic (not implemented here).
CREATE TABLE IF NOT EXISTS v8_b2b_payment_intents_uat (
 id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
 company_id BIGINT UNSIGNED NOT NULL, branch_id BIGINT UNSIGNED NOT NULL,
 channel VARCHAR(12) NOT NULL, employee_id BIGINT UNSIGNED NULL,
 payment_mode VARCHAR(10) NOT NULL, amount_paise BIGINT NOT NULL,
 merchant_order_id VARCHAR(128) NULL, -- mandatory for UPI intents; generated on server
 currency CHAR(3) NOT NULL DEFAULT 'INR', status VARCHAR(24) NOT NULL DEFAULT 'awaiting_payment',
 created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 KEY scope (company_id,branch_id,id),
 CHECK (amount_paise > 0), CHECK (payment_mode IN ('cash','upi'))
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS v8_b2b_tender_intake_evidence_uat (
 intent_id BIGINT UNSIGNED NOT NULL PRIMARY KEY,
 confirmed_tender_id BIGINT UNSIGNED NOT NULL,
 company_id BIGINT UNSIGNED NOT NULL, branch_id BIGINT UNSIGNED NOT NULL,
 payment_mode VARCHAR(10) NOT NULL, payment_reference VARCHAR(128) NOT NULL,
 amount_paise BIGINT NOT NULL, verified_source VARCHAR(40) NOT NULL,
 verified_by BIGINT UNSIGNED NOT NULL, channel VARCHAR(12) NOT NULL,
 employee_id BIGINT UNSIGNED NULL, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE KEY uq_payment_use_across_branches (company_id,payment_mode,payment_reference),
 UNIQUE KEY uq_one_proof (confirmed_tender_id),
 CHECK (amount_paise > 0)
) ENGINE=InnoDB;
