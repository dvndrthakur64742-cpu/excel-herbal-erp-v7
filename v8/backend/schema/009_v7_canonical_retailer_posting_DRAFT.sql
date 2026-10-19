-- DEVELOPMENT DESIGN / DISPOSABLE v8_test ONLY; DO NOT APPLY TO LIVE WORDPRESS.
-- Illustrative wp_ prefix: replace only in approved, isolated test database.
-- V7 eh7_stock_balances, eh7_stock_ledger, eh7_accounts, eh7_journal_entries,
-- eh7_journal_lines, eh7_parties, eh7_counter_sales remain authoritative.
-- The tables below are ONE canonical B2B sale source (not a shadow GL).
CREATE TABLE IF NOT EXISTS wp_eh7_b2b_retailer_sales (
 id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
 company_id BIGINT UNSIGNED NOT NULL,branch_id BIGINT UNSIGNED NOT NULL,
 retailer_id BIGINT UNSIGNED NOT NULL,customer_id BIGINT UNSIGNED NOT NULL,
 sale_intent_id BIGINT UNSIGNED NOT NULL,employee_id BIGINT UNSIGNED NULL,
 channel VARCHAR(10) NOT NULL,payment_mode VARCHAR(10) NOT NULL,
 quote_digest CHAR(64) NOT NULL,business_date DATE NOT NULL,
 invoice_total_paise BIGINT NOT NULL,cogs_paise BIGINT NOT NULL,
 outstanding_paise BIGINT NOT NULL DEFAULT 0,status VARCHAR(20) NOT NULL,
 journal_entry_id BIGINT UNSIGNED NULL,created_by BIGINT UNSIGNED NOT NULL,
 created_at DATETIME NOT NULL,
 UNIQUE KEY company_intent (company_id,sale_intent_id),
 KEY branch_customer (company_id,branch_id,customer_id,business_date),
 CHECK (invoice_total_paise>0),CHECK (outstanding_paise=0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS wp_eh7_b2b_retailer_sale_lines (
 id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
 sale_id BIGINT UNSIGNED NOT NULL,line_no SMALLINT UNSIGNED NOT NULL,
 product_id BIGINT UNSIGNED NOT NULL,batch_id BIGINT UNSIGNED NULL,
 quantity_pcs BIGINT UNSIGNED NOT NULL,commercial_revision_id BIGINT UNSIGNED NOT NULL,
 unit_price_paise BIGINT NOT NULL,line_total_paise BIGINT NOT NULL,cogs_paise BIGINT NOT NULL,
 UNIQUE KEY sale_line (sale_id,line_no),KEY sale_product(sale_id,product_id,batch_id),
 CHECK(quantity_pcs>0),CHECK(unit_price_paise>0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS wp_eh7_b2b_checkout_keys (
 company_id BIGINT UNSIGNED NOT NULL,request_key VARCHAR(128) NOT NULL,
 sale_id BIGINT UNSIGNED NULL,sale_intent_id BIGINT UNSIGNED NULL,
 request_fingerprint CHAR(64) NULL,
 PRIMARY KEY(company_id,request_key),UNIQUE KEY one_source(sale_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
-- NOTE: This table is NOT auto-filled by preview, tender screenshots or a checkout request.
-- Every row must be independently verified and written by a server-owned provider/cashier bridge.
-- This table must ONLY be populated by a FUTURE independently authenticated
-- server-side cash collector / PSP reconciliation adapter, never an HTTP body.
-- Until that adapter exists, the canonical writer has no trusted input source.
CREATE TABLE IF NOT EXISTS wp_eh7_b2b_verified_tenders (
 id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
 company_id BIGINT UNSIGNED NOT NULL,branch_id BIGINT UNSIGNED NOT NULL,
 sale_intent_id BIGINT UNSIGNED NOT NULL,payment_intent_id BIGINT UNSIGNED NOT NULL,
 tender_id BIGINT UNSIGNED NOT NULL,quote_digest CHAR(64) NOT NULL,
 channel VARCHAR(10) NOT NULL,employee_id BIGINT UNSIGNED NULL,
 payment_mode VARCHAR(10) NOT NULL,currency CHAR(3) NOT NULL DEFAULT 'INR',
 status VARCHAR(20) NOT NULL DEFAULT 'confirmed',verified_by BIGINT UNSIGNED NOT NULL,
 verified_source VARCHAR(40) NOT NULL,
 amount_paise BIGINT NOT NULL,provider_transaction_id VARCHAR(128) NULL,
 consumed_sale_id BIGINT UNSIGNED NULL,confirmed_at DATETIME NOT NULL,
 UNIQUE KEY once_per_intent (company_id,sale_intent_id),
 UNIQUE KEY once_per_uat_intent (company_id,payment_intent_id),
 UNIQUE KEY once_per_uat_tender (company_id,tender_id),
 UNIQUE KEY provider_replay (company_id,provider_transaction_id),
 UNIQUE KEY consumed_one_sale (consumed_sale_id),
 CHECK (amount_paise>0),CHECK(currency='INR'),CHECK(status='confirmed')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
-- Release-blockers: tax/HSN/discount+reversal approval; authenticated payment
-- ingestion on THIS database+connection; row-locked V7 price/stock assessment;
-- UAT testing of journal balance, negative stock, replay, concurrent attempts;
-- no installation or source-map modification on production.
