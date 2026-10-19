-- DISPOSABLE v8_test ONLY, NEVER install on live WordPress/ERP database.
-- Existing UAT prerequisites: 001_b2b_preview_mysql.sql and 004_trusted_tender_intake_UAT.sql
-- Server creates immutable quote and payment link; NO public endpoints or payment provider callback implemented.
CREATE TABLE IF NOT EXISTS v8_b2b_sale_intents_uat (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  company_id BIGINT UNSIGNED NOT NULL, branch_id BIGINT UNSIGNED NOT NULL,
  retailer_id BIGINT UNSIGNED NOT NULL, canonical_party_id BIGINT UNSIGNED NOT NULL,
  channel VARCHAR(10) NOT NULL, employee_id BIGINT UNSIGNED NULL,
  payment_mode VARCHAR(10) NOT NULL, merchant_order_id VARCHAR(128) NULL,
  currency CHAR(3) NOT NULL DEFAULT 'INR',invoice_total_paise BIGINT NOT NULL,
  quote_digest CHAR(64) NOT NULL,pricing_locked TINYINT(1) NOT NULL DEFAULT 1,
  status VARCHAR(24) NOT NULL DEFAULT 'awaiting_payment',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY company_branch (company_id,branch_id,id),
  CHECK (invoice_total_paise > 0), CHECK (payment_mode IN ('cash','upi'))
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS v8_b2b_payment_intent_to_sale_uat (
  payment_intent_id BIGINT UNSIGNED NOT NULL PRIMARY KEY,
  sale_intent_id BIGINT UNSIGNED NOT NULL,company_id BIGINT UNSIGNED NOT NULL,
  branch_id BIGINT UNSIGNED NOT NULL,quote_digest CHAR(64) NOT NULL,
  UNIQUE KEY uq_one_tender_intent_per_sale (company_id,sale_intent_id),
  KEY company_branch (company_id,branch_id)
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS v8_b2b_sale_tender_reservations_uat (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  company_id BIGINT UNSIGNED NOT NULL,branch_id BIGINT UNSIGNED NOT NULL,
  sale_intent_id BIGINT UNSIGNED NOT NULL,payment_intent_id BIGINT UNSIGNED NOT NULL,
  tender_id BIGINT UNSIGNED NOT NULL,retailer_id BIGINT UNSIGNED NOT NULL,
  canonical_party_id BIGINT UNSIGNED NOT NULL,channel VARCHAR(10) NOT NULL,
  employee_id BIGINT UNSIGNED NULL,payment_mode VARCHAR(10) NOT NULL,
  payment_reference VARCHAR(128) NOT NULL,verified_source VARCHAR(40) NOT NULL,
  amount_paise BIGINT NOT NULL,quote_digest CHAR(64) NOT NULL,
  status VARCHAR(24) NOT NULL DEFAULT 'reserved',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_company_sale (company_id,sale_intent_id),
  UNIQUE KEY uq_company_tender (company_id,tender_id),
  UNIQUE KEY uq_payment_intent (payment_intent_id),
  CHECK (amount_paise>0)
) ENGINE=InnoDB;
