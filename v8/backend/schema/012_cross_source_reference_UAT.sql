-- DISPOSABLE v8_test ONLY. Never install or migrate live WordPress.
-- This records independent original-document assertions, NOT sale replacement.
-- A Daily Order is an aggregate; evidence references one original evening line
-- and one B2B sale line. Signed review never automatically deduplicates.
CREATE TABLE IF NOT EXISTS v8_b2b_cross_source_reference_evidence_uat (
 id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
 company_id BIGINT UNSIGNED NOT NULL,
 branch_id BIGINT UNSIGNED NOT NULL,
 employee_id BIGINT UNSIGNED NOT NULL,
 legacy_daily_cycle_id BIGINT UNSIGNED NOT NULL,
 legacy_evening_line_id BIGINT UNSIGNED NOT NULL,
 b2b_sale_id BIGINT UNSIGNED NOT NULL,
 b2b_sale_line_id BIGINT UNSIGNED NOT NULL,
 business_date DATE NOT NULL,
 original_order_reference VARCHAR(128) NOT NULL,
 original_receipt_reference VARCHAR(128) NOT NULL,
 source_document_sha256 CHAR(64) NOT NULL,
 evidence_product_id BIGINT UNSIGNED NOT NULL,
 evidence_quantity_pcs BIGINT UNSIGNED NOT NULL,
 evidence_line_paise BIGINT UNSIGNED NOT NULL,
 witness_user_id BIGINT UNSIGNED NOT NULL,
 reviewer_user_id BIGINT UNSIGNED NOT NULL,
 proof_signature CHAR(64) NOT NULL,
 status VARCHAR(20) NOT NULL DEFAULT 'reviewed',
 created_at DATETIME NOT NULL,
 UNIQUE KEY one_legacy_line (company_id,legacy_evening_line_id),
 UNIQUE KEY one_b2b_line (company_id,b2b_sale_line_id),
 KEY review_lookup (company_id,branch_id,employee_id,legacy_daily_cycle_id,b2b_sale_id),
 CHECK (witness_user_id<>reviewer_user_id),
 CHECK (evidence_quantity_pcs>0),
 CHECK (evidence_line_paise>0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
