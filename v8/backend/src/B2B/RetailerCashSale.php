<?php
declare(strict_types=1);

namespace ExcelHerbal\ERP8\B2B;

use InvalidArgumentException;
use RuntimeException;

/** Persistence, locking and trusted payment verification are backend-owned. */
interface RetailerSaleGateway
{
    /** Must be a real ACID database transaction in production. */
    public function atomic(callable $work): array;
    /** Lock/create a UNIQUE (company_id,idempotency_key) record, inside atomic(). */
    public function lockIdempotency(int $companyId, string $key): void;
    public function findByIdempotency(int $companyId, string $key): ?array;
    public function canSell(int $actorId, int $companyId, int $branchId, string $channel, ?int $employeeId): bool;
    public function retailer(int $companyId, int $branchId, int $retailerId): ?array;
    /** Server-stored, effective-dated price snapshot; NEVER accept prices from client. */
    public function product(int $companyId, int $branchId, int $productId): ?array;
    public function availablePcs(int $companyId, int $branchId, int $productId, int $batchId, ?int $custodianId): int;
    /** Verify trusted cash acceptance or provider-side UPI success; screenshots are insufficient. */
    public function confirmedTender(int $companyId, int $branchId, string $mode, string $reference, int $amountPaise): bool;
    /** Atomically save sale + stock ledger + financial journal + party statement + employee remittance. */
    public function record(array $sale, array $stockMoves, array $journalLines): array;
}

final class RetailerSaleError extends RuntimeException {}

final class Paise
{
    /** Rupee decimal with up to 2 digits, stored in integer paise (no floats). */
    public static function parse(mixed $value): int
    {
        if (!is_string($value) && !is_int($value)) {
            throw new RetailerSaleError('Money must be a decimal string or integer.');
        }
        $s = (string)$value;
        if (!preg_match('/^(0|[1-9][0-9]{0,11})(?:\.([0-9]{1,2}))?$/D', $s, $m)) {
            throw new RetailerSaleError('Invalid money; use non-negative rupees with at most two decimals.');
        }
        return ((int)$m[1] * 100) + (int)str_pad($m[2] ?? '', 2, '0');
    }

    /** Purchase cost supports V7's 4-decimal precision; converts total to rounded paise. */
    public static function costTotal(mixed $unitCost, int $quantity): int
    {
        if ((!is_string($unitCost) && !is_int($unitCost)) || $quantity < 1) {
            throw new RetailerSaleError('Invalid product cost.');
        }
        $s = (string)$unitCost;
        if (!preg_match('/^(0|[1-9][0-9]{0,9})(?:\.([0-9]{1,4}))?$/D', $s, $m)) {
            throw new RetailerSaleError('Product cost must have 0–4 decimals.');
        }
        $tenThousandths = (int)$m[1] * 10000 + (int)str_pad($m[2] ?? '', 4, '0');
        return intdiv($tenThousandths * $quantity + 50, 100);
    }

    public static function format(int $paise): string
    {
        return intdiv($paise, 100) . '.' . str_pad((string)($paise % 100), 2, '0', STR_PAD_LEFT);
    }
}

/**
 * Excel Herbal V8 first vertical slice: retailer sales are paid in full with one cash OR UPI tender.
 * No live routes/migrations are registered by this file. Amounts are tax-exclusive pending tax policy.
 * B2B incentive creation and retailer-specific discounts are intentionally NOT implemented.
 */
final class RetailerCashSale
{
    public function __construct(private RetailerSaleGateway $gateway) {}

    public function post(array $request): array
    {
        foreach (['company_id', 'actor_id', 'branch_id', 'retailer_id'] as $key) {
            if (!isset($request[$key]) || !is_int($request[$key]) || $request[$key] < 1) {
                throw new RetailerSaleError("Invalid {$key}.");
            }
        }
        $company = $request['company_id'];
        $branch = $request['branch_id'];
        $actor = $request['actor_id'];
        $retailerId = $request['retailer_id'];
        $key = $request['idempotency_key'] ?? null;
        if (!is_string($key) || !preg_match('/^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$/D', $key)) {
            throw new RetailerSaleError('An idempotency key of 8–128 safe characters is required.');
        }
        $channel = $request['channel'] ?? null;
        if (!in_array($channel, ['counter', 'field'], true)) {
            throw new RetailerSaleError('Sales channel must be counter or field.');
        }
        $employeeId = $request['employee_id'] ?? null;
        if ($channel === 'field' && (!is_int($employeeId) || $employeeId < 1)) {
            throw new RetailerSaleError('Field sales require an employee custodian.');
        }
        if ($channel === 'counter' && $employeeId !== null) {
            throw new RetailerSaleError('Counter sales must use branch stock, not employee custody.');
        }
        $mode = $request['payment_mode'] ?? null;
        if (!in_array($mode, ['cash', 'upi'], true)) {
            throw new RetailerSaleError('Retailer payment allows only cash OR UPI; no credit or split tender.');
        }
        $paymentRef = $request['payment_reference'] ?? null;
        if (!is_string($paymentRef) || trim($paymentRef) === '' || strlen($paymentRef) > 128) {
            throw new RetailerSaleError('A verifiable payment reference is required.');
        }
        $paid = Paise::parse($request['paid_amount'] ?? null);
        if ($paid < 1) {
            throw new RetailerSaleError('Retailer payment must be greater than zero.');
        }
        $lines = $request['lines'] ?? null;
        if (!is_array($lines) || !$lines || count($lines) > 200) {
            throw new RetailerSaleError('Provide 1–200 sale lines.');
        }
        $normalized = [];
        $seen = [];
        foreach ($lines as $line) {
            if (!is_array($line)) throw new RetailerSaleError('Malformed sale line.');
            foreach (['product_id', 'batch_id', 'qty'] as $field) {
                if (!isset($line[$field]) || !is_int($line[$field]) || $line[$field] < ($field === 'batch_id' ? 0 : 1)) {
                    throw new RetailerSaleError("Invalid {$field}; products are whole PCS.");
                }
            }
            if ($line['qty'] > 1000000) throw new RetailerSaleError('Line quantity exceeds safety limit.');
            $sku = $line['product_id'] . ':' . $line['batch_id'];
            if (isset($seen[$sku])) throw new RetailerSaleError('Duplicate product/batch lines are not allowed.');
            $seen[$sku] = true;
            $normalized[] = [
                'product_id' => $line['product_id'],
                'batch_id' => $line['batch_id'],
                'qty' => $line['qty'],
            ];
        }
        usort($normalized, static fn($a, $b) => [$a['product_id'], $a['batch_id']] <=> [$b['product_id'], $b['batch_id']]);
        $fingerprint = hash('sha256', json_encode([
            $company, $actor, $branch, $retailerId, $channel, $employeeId, $mode, $paymentRef, $paid, $normalized,
        ], JSON_THROW_ON_ERROR));

        return $this->gateway->atomic(function () use ($company, $branch, $actor, $retailerId, $key, $fingerprint, $channel, $employeeId, $mode, $paymentRef, $paid, $normalized): array {
            $this->gateway->lockIdempotency($company, $key);
            $prior = $this->gateway->findByIdempotency($company, $key);
            if ($prior !== null) {
                if (($prior['request_fingerprint'] ?? '') !== $fingerprint) {
                    throw new RetailerSaleError('Idempotency key reused with a different request.');
                }
                return $prior;
            }
            if (!$this->gateway->canSell($actor, $company, $branch, $channel, $employeeId)) {
                throw new RetailerSaleError('Actor lacks authorized branch, hierarchy or action scope.');
            }
            $retailer = $this->gateway->retailer($company, $branch, $retailerId);
            if (!$retailer || ($retailer['type'] ?? '') !== 'retailer' || ($retailer['status'] ?? '') !== 'active') {
                throw new RetailerSaleError('An active retailer in the authorized branch is required.');
            }
            $total = $totalCost = 0;
            $details = $stockMoves = [];
            foreach ($normalized as $line) {
                $product = $this->gateway->product($company, $branch, $line['product_id']);
                if (!$product || ($product['status'] ?? '') !== 'active') {
                    throw new RetailerSaleError('Product is missing or inactive.');
                }
                $price = Paise::parse($product['sale_price'] ?? null);
                $mrp = Paise::parse($product['mrp'] ?? null);
                if ($price < 1 || $price > $mrp) {
                    throw new RetailerSaleError('Sale price must be positive and not exceed MRP.');
                }
                $allocated = 0;
                foreach (['ho_amount', 'bm_profit', 'salary_fund', 'office_expense'] as $field) {
                    $allocated += Paise::parse($product[$field] ?? null);
                }
                if ($allocated !== $price) {
                    throw new RetailerSaleError('HO + BM + Salary Fund + Office Expense must equal Sale Price.');
                }
                if (($product['batch_required'] ?? false) && $line['batch_id'] === 0) {
                    throw new RetailerSaleError('Batch-tracked product requires a batch.');
                }
                $available = $this->gateway->availablePcs(
                    $company, $branch, $line['product_id'], $line['batch_id'], $employeeId
                );
                if ($available < $line['qty']) {
                    throw new RetailerSaleError('Insufficient authorized stock in the correct custody bucket.');
                }
                $amount = $price * $line['qty'];
                $cost = Paise::costTotal($product['purchase_cost'] ?? null, $line['qty']);
                $total += $amount;
                $totalCost += $cost;
                $details[] = $line + [
                    'unit_sale_price_paise' => $price,
                    'amount_paise' => $amount,
                    'cost_paise' => $cost,
                    'commercial_snapshot' => array_intersect_key($product, array_flip([
                        'mrp', 'sale_price', 'ho_amount', 'bm_profit', 'salary_fund', 'office_expense', 'purchase_cost', 'points',
                    ])),
                ];
                $stockMoves[] = [
                    'branch_id' => $branch,
                    'product_id' => $line['product_id'],
                    'batch_id' => $line['batch_id'],
                    'custodian_id' => $employeeId,
                    'quantity_delta' => -$line['qty'],
                    'cost_paise' => $cost,
                ];
            }
            if ($total !== $paid) {
                throw new RetailerSaleError('Full verified payment is mandatory; no retailer credit/outstanding.');
            }
            if (!$this->gateway->confirmedTender($company, $branch, $mode, $paymentRef, $paid)) {
                throw new RetailerSaleError('Tender not confirmed by a trusted backend source.');
            }
            // Field cash belongs to the EMPLOYEE CASH-IN-TRANSIT control account until branch remittance.
            // It is NOT customer outstanding. Product commercial split is management allocation, not a journal by itself.
            $debitAccount = $mode === 'upi' ? 'UPI_CLEARING' : ($channel === 'field' ? 'EMPLOYEE_CASH_IN_TRANSIT' : 'BRANCH_CASH');
            $journal = [
                ['account' => $debitAccount, 'debit_paise' => $total, 'credit_paise' => 0],
                ['account' => 'SALES_REVENUE', 'debit_paise' => 0, 'credit_paise' => $total],
                ['account' => 'COST_OF_GOODS_SOLD', 'debit_paise' => $totalCost, 'credit_paise' => 0],
                ['account' => 'STOCK_INVENTORY', 'debit_paise' => 0, 'credit_paise' => $totalCost],
            ];
            $dr = array_sum(array_column($journal, 'debit_paise'));
            $cr = array_sum(array_column($journal, 'credit_paise'));
            if ($dr !== $cr) throw new RetailerSaleError('Unbalanced journal; fail closed.');

            return $this->gateway->record([
                'company_id' => $company,
                'branch_id' => $branch,
                'retailer_id' => $retailerId,
                'channel' => $channel,
                'employee_id' => $employeeId,
                'idempotency_key' => $key,
                'request_fingerprint' => $fingerprint,
                'payment_mode' => $mode,
                'payment_reference' => $paymentRef,
                'invoice_total_paise' => $total,
                'paid_paise' => $paid,
                'retailer_outstanding_paise' => 0,
                'employee_cash_remittance_paise' => $channel === 'field' && $mode === 'cash' ? $paid : 0,
                'points_posted' => false, // pending owner-defined B2B points policy
                'status' => 'paid_posted',
                'lines' => $details,
            ], $stockMoves, $journal);
        });
    }
}