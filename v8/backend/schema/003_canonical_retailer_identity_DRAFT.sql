-- DRAFT / DESIGN REVIEW ONLY — DO NOT RUN ON office.excelherbal.in.
-- Replace wp_ with the site-specific WordPress prefix ONLY in a separately approved
-- migration. Table is a classification of canonical V7 customer parties, not a duplicate
-- name/contact/credit/ledger master.
-- Existing positive customer receivables require accountant resolution before linking.
-- Verified tender and statutory invoicing are separate release gates.
CREATE TABLE wp_eh8_retailer_party_links (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  company_id BIGINT UNSIGNED NOT NULL,
  branch_id BIGINT UNSIGNED NOT NULL,
  party_id BIGINT UNSIGNED NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'active',
  created_by BIGINT UNSIGNED NOT NULL,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NULL,
  PRIMARY KEY(id),
  UNIQUE KEY uq_retailer_company_party(company_id, party_id),
  KEY branch_status(company_id, branch_id, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
-- No foreign keys by default because eh7_parties is managed by existing WP/DB schema.
-- Registration writer MUST lock canonical party and validate same company/branch/type,
-- authorization, status, and absence of open receivable in one transaction.
