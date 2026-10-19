-- Excel Herbal ERP V8: isolated BUILD/UAT-only Retailer B2B schema.
-- DO NOT run on office.excelherbal.in; no automatic migration is registered.
-- Tables are stand-alone fixtures; V7 product/company/branch/stock mapping remains an integration gate.
-- MySQL 8 / MariaDB InnoDB, all amounts integer paise, whole PCS.
CREATE TABLE IF NOT EXISTS v8_b2b_retailers (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  company_id BIGINT UNSIGNED NOT NULL, branch_id BIGINT UNSIGNED NOT NULL,
  type VARCHAR(20) NOT NULL DEFAULT 'retailer', shop_name VARCHAR(160) NOT NULL,
  contact_name VARCHAR(120) NULL, mobile VARCHAR(16) NULL,
  address VARCHAR(500) NULL, gstin VARCHAR(15) NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'active', created_by BIGINT UNSIGNED NOT NULL,
  idempotency_key VARCHAR(128) NOT NULL, request_fingerprint CHAR(64) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_v8_retailer_key (company_id,branch_id,idempotency_key),
  KEY idx_v8_retailer_search (company_id,branch_id,status,shop_name)
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS v8_b2b_catalog_preview (
  company_id BIGINT UNSIGNED NOT NULL, branch_id BIGINT UNSIGNED NOT NULL,
  product_id BIGINT UNSIGNED NOT NULL, status VARCHAR(20) NOT NULL DEFAULT 'active',
  mrp VARCHAR(32) NOT NULL, sale_price VARCHAR(32) NOT NULL,
  ho_amount VARCHAR(32) NOT NULL, bm_profit VARCHAR(32) NOT NULL,
  salary_fund VARCHAR(32) NOT NULL, office_expense VARCHAR(32) NOT NULL,
  purchase_cost VARCHAR(32) NOT NULL, points VARCHAR(32) NOT NULL DEFAULT '0',
  batch_required TINYINT(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (company_id,branch_id,product_id)
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS v8_b2b_batches_preview (
  company_id BIGINT UNSIGNED NOT NULL, branch_id BIGINT UNSIGNED NOT NULL,
  product_id BIGINT UNSIGNED NOT NULL, batch_id BIGINT UNSIGNED NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'active', expiry_date DATE NULL,
  PRIMARY KEY (company_id,branch_id,product_id,batch_id)
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS v8_b2b_stock_bins_preview (
  company_id BIGINT UNSIGNED NOT NULL, branch_id BIGINT UNSIGNED NOT NULL,
  product_id BIGINT UNSIGNED NOT NULL, batch_id BIGINT UNSIGNED NOT NULL,
  custodian_key BIGINT UNSIGNED NOT NULL DEFAULT 0, quantity_pcs INT NOT NULL DEFAULT 0,
  PRIMARY KEY (company_id,branch_id,product_id,batch_id,custodian_key),
  CHECK (quantity_pcs >= 0)
) ENGINE=InnoDB;
-- Trusted back-office evidence insertion is NOT exposed by retailer sale endpoints.
-- Cash is acknowledged by authorized cashier; UPI by a verified provider/backend process.
CREATE TABLE IF NOT EXISTS v8_b2b_verified_tenders (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  company_id BIGINT UNSIGNED NOT NULL, branch_id BIGINT UNSIGNED NOT NULL,
  payment_mode VARCHAR(10) NOT NULL, payment_reference VARCHAR(128) NOT NULL,
  amount_paise BIGINT NOT NULL, verified_source VARCHAR(40) NOT NULL,
  verified_at DATETIME NOT NULL, status VARCHAR(20) NOT NULL DEFAULT 'confirmed',
  consumed_sale_id BIGINT UNSIGNED NULL,
  UNIQUE KEY uq_v8_tender_proof (company_id,branch_id,payment_mode,payment_reference),
  CHECK (amount_paise > 0)
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS v8_b2b_sale_keys (
  company_id BIGINT UNSIGNED NOT NULL, idempotency_key VARCHAR(128) NOT NULL,
  request_fingerprint CHAR(64) NULL, sale_id BIGINT UNSIGNED NULL,
  result_json LONGTEXT NULL, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (company_id,idempotency_key)
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS v8_b2b_sales (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  company_id BIGINT UNSIGNED NOT NULL, branch_id BIGINT UNSIGNED NOT NULL,
  retailer_id BIGINT UNSIGNED NOT NULL, channel VARCHAR(12) NOT NULL,
  employee_id BIGINT UNSIGNED NULL, actor_id BIGINT UNSIGNED NOT NULL,
  idempotency_key VARCHAR(128) NOT NULL, payment_mode VARCHAR(10) NOT NULL,
  payment_reference VARCHAR(128) NOT NULL,
  invoice_total_paise BIGINT NOT NULL, paid_paise BIGINT NOT NULL,
  outstanding_paise BIGINT NOT NULL DEFAULT 0, status VARCHAR(24) NOT NULL,
  posted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_v8_sale_key (company_id,idempotency_key),
  KEY idx_v8_sale_retailer (company_id,branch_id,retailer_id,posted_at),
  CHECK (outstanding_paise = 0), CHECK (invoice_total_paise = paid_paise)
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS v8_b2b_sale_lines (
  sale_id BIGINT UNSIGNED NOT NULL, line_no INT UNSIGNED NOT NULL,
  product_id BIGINT UNSIGNED NOT NULL, batch_id BIGINT UNSIGNED NOT NULL,
  qty_pcs INT NOT NULL, unit_price_paise BIGINT NOT NULL,
  amount_paise BIGINT NOT NULL, cost_paise BIGINT NOT NULL,
  commercial_snapshot_json LONGTEXT NOT NULL,
  PRIMARY KEY (sale_id,line_no)
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS v8_b2b_stock_movements (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  sale_id BIGINT UNSIGNED NOT NULL, company_id BIGINT UNSIGNED NOT NULL,
  branch_id BIGINT UNSIGNED NOT NULL, product_id BIGINT UNSIGNED NOT NULL,
  batch_id BIGINT UNSIGNED NOT NULL, custodian_key BIGINT UNSIGNED NOT NULL,
  quantity_delta INT NOT NULL, cost_paise BIGINT NOT NULL,
  KEY idx_v8_stock_source (sale_id)
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS v8_b2b_journal_lines (
  sale_id BIGINT UNSIGNED NOT NULL, line_no INT UNSIGNED NOT NULL,
  account_code VARCHAR(40) NOT NULL, debit_paise BIGINT NOT NULL,
  credit_paise BIGINT NOT NULL, PRIMARY KEY (sale_id,line_no),
  CHECK (debit_paise >= 0), CHECK (credit_paise >= 0)
) ENGINE=InnoDB;
-- Retailer statement: invoice Dr + payment Cr; NOT employee cash remittance.
CREATE TABLE IF NOT EXISTS v8_b2b_retailer_statement (
  sale_id BIGINT UNSIGNED NOT NULL, event_type VARCHAR(20) NOT NULL,
  company_id BIGINT UNSIGNED NOT NULL, branch_id BIGINT UNSIGNED NOT NULL,
  retailer_id BIGINT UNSIGNED NOT NULL, amount_paise BIGINT NOT NULL,
  PRIMARY KEY (sale_id,event_type),
  KEY idx_v8_statement_retailer (company_id,branch_id,retailer_id)
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS v8_b2b_employee_remittance (
  sale_id BIGINT UNSIGNED NOT NULL PRIMARY KEY,
  company_id BIGINT UNSIGNED NOT NULL, branch_id BIGINT UNSIGNED NOT NULL,
  employee_id BIGINT UNSIGNED NOT NULL, amount_due_paise BIGINT NOT NULL,
  amount_remitted_paise BIGINT NOT NULL DEFAULT 0, status VARCHAR(20) NOT NULL DEFAULT 'pending',
  CHECK (amount_due_paise >= amount_remitted_paise)
) ENGINE=InnoDB;