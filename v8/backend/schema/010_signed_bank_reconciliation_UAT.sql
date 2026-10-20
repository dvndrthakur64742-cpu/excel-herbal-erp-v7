-- DISPOSABLE v8_test ONLY. Do NOT install as a production WordPress table.
-- Records MUST be ingested by a separately authenticated bank-reconciliation worker;
-- ERP user requests, browser callbacks and unverified payment screenshots are untrusted.
CREATE TABLE IF NOT EXISTS v8_b2b_signed_bank_reconciliation_uat (
  lookup_key VARCHAR(128) NOT NULL PRIMARY KEY,
  company_id BIGINT UNSIGNED NOT NULL,
  branch_id BIGINT UNSIGNED NOT NULL,
  status VARCHAR(24) NOT NULL,
  currency CHAR(3) NOT NULL,
  amount_paise BIGINT NOT NULL,
  merchant_account VARCHAR(128) NOT NULL,
  merchant_order_id VARCHAR(128) NOT NULL,
  transaction_id VARCHAR(128) NOT NULL,
  observed_at DATETIME NOT NULL,
  key_id VARCHAR(64) NOT NULL,
  signature CHAR(64) NOT NULL,
  UNIQUE KEY one_settlement_reference (merchant_account,transaction_id),
  -- A UPI/bank reference cannot be reused even by a different ERP company or destination account.
  UNIQUE KEY one_global_bank_reference (transaction_id),
  KEY company_scope (company_id,branch_id),
  CHECK (amount_paise>0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
