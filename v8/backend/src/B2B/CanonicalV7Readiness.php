<?php
declare(strict_types=1);

namespace ExcelHerbal\ERP8\B2B;

/**
 * All reads are from canonical V7 eh7_* data. No writes, payment confirmations,
 * idempotency reservations, invoices, stock movements, or GL entries are made here.
 * Never mistake a successful read-only assessment for permission to post a sale.
 */
interface V7CanonicalReader
{
    public function canInspect(int $actorId, int $companyId, int $branchId, string $channel, ?int $employeeId): bool;
    public function branch(int $companyId, int $branchId): ?array;
    public function employee(int $companyId, int $employeeId): ?array;
    public function closedAccountingPeriod(int $companyId, string $businessDate): bool;
    public function closedBranchDay(int $companyId, int $branchId, string $businessDate): bool;
    public function product(int $companyId, int $productId): ?array;
    public function commercial(int $companyId, int $productId, string $businessAt): ?array;
    public function batch(int $companyId, int $productId, int $batchId): ?array;
    public function stockBucket(int $companyId, int $branchId, int $productId, int $batchId, int $custodianKey): ?array;
    public function accountByCode(int $companyId, string $code): ?array;
}

/**
 * Strict, side-effect-free bridge from V8 domain requests to V7 source masters.
 * This never permits live posting. Source routes/retailer mapping and trusted payment
 * acknowledgements are separate release gates.
 */
final class CanonicalV7Readiness
{
    public function __construct(private V7CanonicalReader $source) {}

    public function assess(array $input): array
    {
        foreach (['company_id', 'branch_id', 'actor_id'] as $key) {
            if (!isset($input[$key]) || !is_int($input[$key]) || $input[$key] < 1) {
                throw new RetailerSaleError('Trusted context must supply a valid ' . $key . '.');
            }
        }
        $company = $input['company_id'];
        $branch = $input['branch_id'];
        $actor = $input['actor_id'];
        $channel = $input['channel'] ?? null;
        $custodian = $input['employee_id'] ?? null;
        if (!in_array($channel, ['field', 'counter'], true)) {
            throw new RetailerSaleError('Channel must be field or counter.');
        }
        if ($channel === 'field' && (!is_int($custodian) || $custodian < 1)) {
            throw new RetailerSaleError('Field sale requires an employee custodian.');
        }
        if ($channel === 'counter' && $custodian !== null) {
            throw new RetailerSaleError('Counter sale must use branch stock.');
        }
        if (!$this->source->canInspect($actor, $company, $branch, $channel, $custodian)) {
            throw new RetailerSaleError('No authorized company, branch and employee scope.');
        }
        $at = $input['business_at'] ?? null;
        if (!is_string($at) || !preg_match('/^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$/D', $at)) {
            throw new RetailerSaleError('Server-trusted local business datetime is required.');
        }
        $parsed = \DateTimeImmutable::createFromFormat('!Y-m-d H:i:s', $at);
        if ($parsed === false || $parsed->format('Y-m-d H:i:s') !== $at) {
            throw new RetailerSaleError('Invalid business datetime.');
        }
        $businessDate = substr($at, 0, 10);
        $mode = $input['payment_mode'] ?? null;
        if (!in_array($mode, ['cash', 'upi'], true)) {
            throw new RetailerSaleError('Retailer only permits one Cash OR UPI tender; no credit.');
        }
        $paid = Paise::parse($input['paid_amount'] ?? null);
        if ($paid <= 0) throw new RetailerSaleError('Full positive payment is required.');
        $lines = $input['lines'] ?? null;
        if (!is_array($lines) || count($lines) < 1 || count($lines) > 200) {
            throw new RetailerSaleError('Provide 1–200 valid product lines.');
        }
        $sourceBranch = $this->source->branch($company, $branch);
        if (!$sourceBranch || ($sourceBranch['status'] ?? '') !== 'active') {
            throw new RetailerSaleError('Authorized active branch missing in canonical source.');
        }
        if ($this->source->closedAccountingPeriod($company, $businessDate)) {
            throw new RetailerSaleError('Canonical accounting period is closed.');
        }
        if ($this->source->closedBranchDay($company, $branch, $businessDate)) {
            throw new RetailerSaleError('Canonical branch business day is closed.');
        }
        if ($custodian !== null) {
            $employee = $this->source->employee($company, $custodian);
            if (!$employee || ($employee['status'] ?? '') !== 'active') {
                throw new RetailerSaleError('Active employee custodian missing.');
            }
        }
        $total = $totalCost = 0;
        $seen = [];
        $normalized = [];
        foreach ($lines as $line) {
            if (!is_array($line)) throw new RetailerSaleError('Malformed product line.');
            foreach (['product_id', 'batch_id', 'qty'] as $key) {
                $min = $key === 'batch_id' ? 0 : 1;
                if (!isset($line[$key]) || !is_int($line[$key]) || $line[$key] < $min) {
                    throw new RetailerSaleError('Invalid product, batch or whole PCS quantity.');
                }
            }
            if ($line['qty'] > 1000000) throw new RetailerSaleError('Line quantity limit exceeded.');
            $id = $line['product_id'];
            $batchId = $line['batch_id'];
            $qty = $line['qty'];
            $lineKey = $id . ':' . $batchId;
            if (isset($seen[$lineKey])) throw new RetailerSaleError('Duplicate product and batch line.');
            $seen[$lineKey] = true;
            $product = $this->source->product($company, $id);
            if (!$product || ($product['status'] ?? '') !== 'active' || ($product['uom'] ?? '') !== 'PCS') {
                throw new RetailerSaleError('Canonical product must be active and sold in PCS.');
            }
            $batchMode = $product['batch_tracking'] ?? null;
            if (!in_array($batchMode, ['off', 'optional', 'required'], true)) {
                throw new RetailerSaleError('Unknown canonical batch policy.');
            }
            $expiryTracked = ((int)($product['expiry_tracking'] ?? 0)) === 1;
            if ($batchId === 0 && ($batchMode === 'required' || $expiryTracked)) {
                throw new RetailerSaleError('Batch and expiry policy requires a batch.');
            }
            if ($batchId > 0) {
                if ($batchMode === 'off') throw new RetailerSaleError('Non-batch product cannot take a batch.');
                $batch = $this->source->batch($company, $id, $batchId);
                if (!$batch || ($batch['status'] ?? '') !== 'active') {
                    throw new RetailerSaleError('Canonical batch is missing or inactive.');
                }
                $expiry = $batch['expires_on'] ?? null;
                if ($expiryTracked && (!is_string($expiry) || $expiry === '')) {
                    throw new RetailerSaleError('Tracked batch requires an expiry date.');
                }
                if ($expiry !== null && $expiry !== '' && $expiry < $businessDate) {
                    throw new RetailerSaleError('Expired stock cannot be sold.');
                }
            }
            $price = $this->source->commercial($company, $id, $at);
            if (!$price || ($price['status'] ?? '') !== 'active') {
                throw new RetailerSaleError('Effective approved commercial revision is missing.');
            }
            $unitPrice = Paise::parse($price['sale_price'] ?? null);
            $mrp = Paise::parse($price['mrp'] ?? null);
            if ($unitPrice < 1 || $unitPrice > $mrp) throw new RetailerSaleError('Sale price exceeds MRP or is zero.');
            $allocation = 0;
            foreach (['ho_amount', 'bm_profit', 'salary_fund', 'office_expense'] as $field) {
                $allocation += Paise::parse($price[$field] ?? null);
            }
            if ($allocation !== $unitPrice) throw new RetailerSaleError('Product commercial distribution mismatch.');
            $stock = $this->source->stockBucket($company, $branch, $id, $batchId, $custodian ?? 0);
            $quantity = self::wholeStock($stock['quantity'] ?? null);
            if ($quantity < $qty) throw new RetailerSaleError('Insufficient canonical stock in correct custody.');
            $averageCost = $stock['average_unit_cost'] ?? null;
            if (!is_string($averageCost) && !is_int($averageCost)) {
                throw new RetailerSaleError('Canonical stock valuation missing.');
            }
            $cost = Paise::costTotal($averageCost, $qty); // V7 StockService uses average_unit_cost.
            if ($cost === 0 && Paise::costTotal($price['purchase_cost'] ?? null, $qty) > 0) {
                throw new RetailerSaleError('Missing canonical average unit cost; cannot assume purchase cost.');
            }
            if ($unitPrice > intdiv(PHP_INT_MAX, $qty)) throw new RetailerSaleError('Sale amount overflow.');
            $lineTotal = $unitPrice * $qty;
            if ($total > PHP_INT_MAX - $lineTotal || $totalCost > PHP_INT_MAX - $cost) {
                throw new RetailerSaleError('Total amount overflow.');
            }
            $total += $lineTotal;
            $totalCost += $cost;
            $normalized[] = [
                'product_id' => $id, 'batch_id' => $batchId, 'qty_pcs' => $qty,
                'canonical_stock_custodian' => $custodian ?? 0,
                'commercial_revision_id' => (int)($price['id'] ?? 0),
                'unit_price_paise' => $unitPrice, 'line_total_paise' => $lineTotal,
                'canonical_average_cost_4dp' => $averageCost, 'cogs_paise' => $cost,
            ];
        }
        if ($total !== $paid) throw new RetailerSaleError('Retailer requires full Cash/UPI payment with no outstanding.');
        $required = ['SALES' => 'income', 'COGS' => 'expense', 'INVENTORY' => 'asset'];
        if ($mode === 'upi') {
            $cashCode = 'UPI_CLEARING';
            $required[$cashCode] = 'asset';
        } elseif ($channel === 'field') {
            $cashCode = 'EMPLOYEE_CASH_IN_TRANSIT';
            $required[$cashCode] = 'asset';
        } else {
            $cashCode = 'BRANCH_CASH';
            $required[$cashCode] = 'asset';
        }
        $accounts = [];
        foreach ($required as $code => $type) {
            $account = $this->source->accountByCode($company, $code);
            if (!$account || (int)($account['active'] ?? 0) !== 1 || strtolower((string)($account['type'] ?? '')) !== $type) {
                throw new RetailerSaleError('Canonical Chart of Accounts mapping missing or invalid: ' . $code);
            }
            $accounts[$code] = (int)$account['id'];
        }
        // THIS IS A READ-ONLY MODEL, NOT AN ACCOUNTING JOURNAL AND NOT AN INVOICE.
        return [
            'assessment' => 'canonical_read_model_validated',
            'posting_allowed' => false,
            'company_id' => $company, 'branch_id' => $branch, 'channel' => $channel,
            'employee_id' => $custodian, 'business_date' => $businessDate,
            'payment_mode' => $mode, 'total_paise' => $total, 'paid_paise' => $paid,
            'retailer_outstanding_paise' => 0, 'cogs_paise' => $totalCost,
            'canonical_account_ids' => $accounts, 'lines' => $normalized,
            'posting_blockers' => [
                'Retailer identity must map to canonical party/customer records',
                'Trusted payment source and unique single-use proof must be integrated',
                'No double-write: one canonical stock and GL posting owner is required',
                'V7 AccountingService sourceTable does not yet support retailer B2B source',
                'Locked transaction, idempotency, reversals and branch-day recheck remain unimplemented',
                'Tax/invoice and approved B2B pricing policy must be specified',
            ],
        ];
    }

    private static function wholeStock(mixed $value): int
    {
        if (!is_string($value) && !is_int($value)) throw new RetailerSaleError('Canonical stock quantity missing.');
        $s = (string)$value;
        if (!preg_match('/^(0|[1-9][0-9]{0,10})(?:\.(\d{1,3}))?$/D', $s, $m)) {
            throw new RetailerSaleError('Invalid canonical stock quantity.');
        }
        if (isset($m[2]) && (int)$m[2] !== 0) {
            throw new RetailerSaleError('Fractional PCS balance requires reconciliation.');
        }
        return (int)$m[1];
    }
}
