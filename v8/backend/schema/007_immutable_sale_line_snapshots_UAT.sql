-- V8 ISOLATED v8_test UAT ONLY; DO NOT run on WordPress/ERP live database.
-- Created inside the same transaction as the sale and payment intents.
-- Every product/batch/price revision is immutable for replay checks; stock must still be
-- revalidated under FOR UPDATE by the future approved production posting writer.
CREATE TABLE IF NOT EXISTS v8_b2b_sale_intent_lines_uat (
 company_id BIGINT UNSIGNED NOT NULL,
 branch_id BIGINT UNSIGNED NOT NULL,
 sale_intent_id BIGINT UNSIGNED NOT NULL,
 line_no SMALLINT UNSIGNED NOT NULL,
 product_id BIGINT UNSIGNED NOT NULL,
 batch_id BIGINT UNSIGNED NOT NULL DEFAULT 0,
 quantity_pcs BIGINT UNSIGNED NOT NULL,
 commercial_revision_id BIGINT UNSIGNED NOT NULL,
 unit_price_paise BIGINT UNSIGNED NOT NULL,
 line_total_paise BIGINT UNSIGNED NOT NULL,
 PRIMARY KEY (sale_intent_id,line_no),
 UNIQUE KEY uq_once_per_batch (sale_intent_id,product_id,batch_id),
 KEY scope (company_id,branch_id,sale_intent_id),
 CHECK (quantity_pcs>0),
 CHECK (unit_price_paise>0),
 CHECK (line_total_paise>0)
) ENGINE=InnoDB;
-- Business-local date/time must also be persisted rather than supplied again by browser.
-- The earlier 005 sale-intent header did not have this field.
CREATE TABLE IF NOT EXISTS v8_b2b_issued_sale_context_uat (
 sale_intent_id BIGINT UNSIGNED NOT NULL PRIMARY KEY,
 company_id BIGINT UNSIGNED NOT NULL,
 branch_id BIGINT UNSIGNED NOT NULL,
 business_at DATETIME NOT NULL,
 quote_digest CHAR(64) NOT NULL,
 KEY scope(company_id,branch_id,sale_intent_id)
) ENGINE=InnoDB;
