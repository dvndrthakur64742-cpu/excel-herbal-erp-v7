<?php
declare(strict_types=1);

namespace ExcelHerbal\ERP8\B2B;

/**
 * WordPress V7 canonical master-data adapter. READ ONLY, no SQL writes or locks.
 * Instantiation must happen behind V7 authentication and branch/employee authorization.
 * It is not registered as a REST route and never claims authorization itself.
 */
final class WpV7CanonicalReader implements V7CanonicalReader
{
    private string $prefix;

    /** @param callable $authorize trusted server callback (actor,company,branch,channel,employee) -> bool */
    public function __construct(private object $wpdb, private $authorize)
    {
        if (!is_callable($authorize)) throw new RetailerSaleError('Canonical scope authorization callback is required.');
        $prefix = $this->wpdb->prefix ?? null;
        if (!is_string($prefix) || !preg_match('/^[A-Za-z0-9_]{1,60}$/D', $prefix)) {
            throw new RetailerSaleError('Unsafe WordPress database prefix.');
        }
        $this->prefix = $prefix . 'eh7_';
    }

    public function canInspect(int $actorId, int $companyId, int $branchId, string $channel, ?int $employeeId): bool
    {
        return ($this->authorize)($actorId, $companyId, $branchId, $channel, $employeeId) === true;
    }

    private function read(string $table, string $where, array $params): ?array
    {
        $sql = 'SELECT * FROM ' . $this->prefix . $table . ' WHERE ' . $where . ' LIMIT 1';
        $prepared = $this->wpdb->prepare($sql, ...$params);
        if (!is_string($prepared)) throw new RetailerSaleError('Canonical query preparation failed.');
        // ARRAY_A is a WordPress-defined constant, not required by isolated PHP tests.
        $row = $this->wpdb->get_row($prepared, defined('ARRAY_A') ? constant('ARRAY_A') : 'ARRAY_A');
        if (trim((string)($this->wpdb->last_error ?? '')) !== '') {
            throw new RetailerSaleError('Canonical query failed; no posting allowed.');
        }
        return is_array($row) ? $row : null;
    }

    public function branch(int $companyId, int $branchId): ?array
    {
        return $this->read('branches', 'company_id=%d AND id=%d', [$companyId, $branchId]);
    }
    public function employee(int $companyId, int $employeeId): ?array
    {
        return $this->read('employees', 'company_id=%d AND id=%d', [$companyId, $employeeId]);
    }
    public function closedAccountingPeriod(int $companyId, string $businessDate): bool
    {
        return $this->read('accounting_periods', "company_id=%d AND status='closed' AND %s BETWEEN period_start AND period_end", [$companyId, $businessDate]) !== null;
    }
    public function closedBranchDay(int $companyId, int $branchId, string $businessDate): bool
    {
        return $this->read('branch_closings', "company_id=%d AND branch_id=%d AND business_date=%s AND status='closed'", [$companyId, $branchId, $businessDate]) !== null;
    }
    public function product(int $companyId, int $productId): ?array
    {
        return $this->read('products', 'company_id=%d AND id=%d', [$companyId, $productId]);
    }
    public function commercial(int $companyId, int $productId, string $businessAt): ?array
    {
        // Unlike the preview table, V7 uses effective-dated revisions.
        return $this->read('product_commercial_revisions', "company_id=%d AND product_id=%d AND status='active' AND effective_from<=%s ORDER BY effective_from DESC,id DESC", [$companyId, $productId, $businessAt]);
    }
    public function batch(int $companyId, int $productId, int $batchId): ?array
    {
        return $this->read('batches', 'company_id=%d AND product_id=%d AND id=%d', [$companyId, $productId, $batchId]);
    }
    public function stockBucket(int $companyId, int $branchId, int $productId, int $batchId, int $custodianKey): ?array
    {
        return $this->read('stock_balances', 'company_id=%d AND branch_id=%d AND product_id=%d AND batch_key=%d AND custodian_key=%d', [$companyId, $branchId, $productId, $batchId, $custodianKey]);
    }
    public function accountByCode(int $companyId, string $code): ?array
    {
        return $this->read('accounts', 'company_id=%d AND code=%s', [$companyId, $code]);
    }
}
