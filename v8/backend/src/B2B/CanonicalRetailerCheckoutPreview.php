<?php
declare(strict_types=1);

namespace ExcelHerbal\ERP8\B2B;

/**
 * Read-only integration of the V7 retailer/customer identity and canonical V7
 * stock/commercial read models. This is NOT a price approval, invoice, payment
 * intent, stock reservation, or permission to post a sale.
 *
 * Caller MUST supply server-resolved actor/company/branch/employee, business_at
 * and must enforce authorization. A preview is ALWAYS stale by the time it is
 * displayed and must be recomputed under row locks by the final writer.
 */
final class CanonicalRetailerCheckoutPreview
{
    public function __construct(
        private CanonicalRetailerIdentity $identity,
        private CanonicalV7Readiness $readiness
    ) {}

    public function compose(array $trusted): array
    {
        // Resolve customer credit/branch first; NEVER preview an unlinked shop.
        $shop = $this->identity->resolve($trusted);
        $stock = $this->readiness->assess($trusted);
        if (($shop['identity_validated'] ?? null) !== true || ($shop['credit_allowed'] ?? null) !== false
            || ($shop['outstanding_paise'] ?? null) !== 0
            || ($shop['posting_allowed'] ?? null) !== false
            || ($stock['assessment'] ?? null) !== 'canonical_read_model_validated'
            || ($stock['posting_allowed'] ?? null) !== false) {
            throw new RetailerSaleError('Canonical preview source is not fail-closed.');
        }
        foreach (['company_id', 'branch_id'] as $key) {
            if (!isset($trusted[$key]) || !is_int($trusted[$key]) || $trusted[$key] < 1
                || ($shop[$key] ?? null) !== $trusted[$key]
                || ($stock[$key] ?? null) !== $trusted[$key]) {
                throw new RetailerSaleError('Canonical retailer/stock company or branch mismatch.');
            }
        }
        foreach (['retailer_id', 'actor_id'] as $key) {
            if (!isset($trusted[$key]) || !is_int($trusted[$key]) || $trusted[$key] < 1) {
                throw new RetailerSaleError('Canonical checkout lacks trusted '.$key.'.');
            }
        }
        if ($shop['retailer_id'] !== $trusted['retailer_id']
            || !is_int($shop['canonical_party_id'] ?? null)
            || $shop['canonical_party_id'] <= 0
            || ($stock['channel'] ?? null) !== ($trusted['channel'] ?? null)
            || ($stock['employee_id'] ?? null) !== ($trusted['employee_id'] ?? null)
            || ($stock['payment_mode'] ?? null) !== ($trusted['payment_mode'] ?? null)
            || !in_array($stock['payment_mode'], ['cash', 'upi'], true)
            || !in_array($stock['channel'], ['field', 'counter'], true)) {
            throw new RetailerSaleError('Canonical checkout identity, channel or tender mismatch.');
        }
        $gross = $stock['total_paise'] ?? null;
        if (!is_int($gross) || $gross < 1 || ($stock['paid_paise'] ?? null) !== $gross
            || ($stock['retailer_outstanding_paise'] ?? null) !== 0) {
            throw new RetailerSaleError('Only fully paid Cash/UPI retailer checkout can be previewed.');
        }
        $lines = $stock['lines'] ?? null;
        if (!is_array($lines) || $lines === [] || count($lines) > 200) {
            throw new RetailerSaleError('Canonical checkout requires product lines.');
        }
        $display = [];
        $sum = 0;
        foreach ($lines as $line) {
            if (!is_array($line)) throw new RetailerSaleError('Malformed canonical stock line.');
            foreach (['product_id', 'batch_id', 'qty_pcs', 'commercial_revision_id', 'unit_price_paise', 'line_total_paise'] as $key) {
                if (!isset($line[$key]) || !is_int($line[$key]) || $line[$key] < ($key === 'batch_id' ? 0 : 1)) {
                    throw new RetailerSaleError('Invalid canonical checkout line: '.$key);
                }
            }
            if ($line['qty_pcs'] > intdiv(PHP_INT_MAX, $line['unit_price_paise'])
                || $line['line_total_paise'] !== $line['qty_pcs']*$line['unit_price_paise']
                || $sum > PHP_INT_MAX - $line['line_total_paise']) {
                throw new RetailerSaleError('Canonical checkout line amount overflow/mismatch.');
            }
            $sum += $line['line_total_paise'];
            $display[] = [
                'product_id' => $line['product_id'],
                'batch_id' => $line['batch_id'],
                'quantity_pcs' => $line['qty_pcs'],
                'commercial_revision_id' => $line['commercial_revision_id'],
                'unit_price_paise' => $line['unit_price_paise'],
                'line_total_paise' => $line['line_total_paise'],
            ];
        }
        if ($sum !== $gross) throw new RetailerSaleError('Canonical checkout lines do not reconcile.');
        $date = $stock['business_date'] ?? null;
        if (!is_string($date) || !preg_match('/^\d{4}-\d\d-\d\d$/D', $date)
            || $date !== substr((string)($trusted['business_at'] ?? ''), 0, 10)) {
            throw new RetailerSaleError('Canonical checkout business date mismatch.');
        }
        // The digest detects *preview* change; it is not an authority token.
        // No COGS, salary-fund splits or GL account IDs are sent to the UI.
        $snapshot = [
            'company_id' => $trusted['company_id'],
            'branch_id' => $trusted['branch_id'],
            'retailer_id' => $shop['retailer_id'],
            'canonical_party_id' => $shop['canonical_party_id'],
            'channel' => $stock['channel'],
            'employee_id' => $stock['employee_id'],
            'business_at' => $trusted['business_at'],
            'payment_mode' => $stock['payment_mode'],
            'gross_paise' => $gross,
            'lines' => $display,
        ];
        $digest = hash('sha256', json_encode($snapshot, JSON_THROW_ON_ERROR));
        return $snapshot + [
            'shop_name' => $shop['shop_name'],
            'preview_digest' => $digest,
            'credit_allowed' => false,
            'retailer_outstanding_paise' => 0,
            'payment_verification_status' => 'not_verified_by_preview',
            'tax_invoice_status' => 'policy_not_approved',
            'stock_reserved' => false,
            'posting_allowed' => false,
            'requires_locked_revalidation' => true,
            'release_status' => 'preview_only',
        ];
    }
}
