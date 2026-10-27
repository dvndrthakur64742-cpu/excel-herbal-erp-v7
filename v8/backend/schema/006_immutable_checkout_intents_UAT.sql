-- ISOLATED v8_test UAT ONLY. NEVER APPLY TO REAL WORDPRESS, V7 OR PRODUCTION DB.
-- Requires 004_trusted_tender_intake_UAT.sql and 005_sale_intent_tender_binding_UAT.sql.
-- All sale/payment/tender objects are non-posting preview and verification staging.
CREATE TABLE IF NOT EXISTS v8_b2b_intent_issuance_requests_uat (
  company_id BIGINT UNSIGNED NOT NULL,
  request_key VARCHAR(64) NOT NULL,
  sale_intent_id BIGINT UNSIGNED NULL,
  payment_intent_id BIGINT UNSIGNED NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY(company_id,request_key),
  UNIQUE KEY uq_sale_intent_issued (sale_intent_id),
  UNIQUE KEY uq_payment_intent_issued (payment_intent_id),
  CHECK ((sale_intent_id IS NULL AND payment_intent_id IS NULL) OR
         (sale_intent_id IS NOT NULL AND payment_intent_id IS NOT NULL))
) ENGINE=InnoDB;
