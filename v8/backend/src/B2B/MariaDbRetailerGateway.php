<?php
declare(strict_types=1);

namespace ExcelHerbal\ERP8\B2B;

use PDO;
use Throwable;

/**
 * Development-only reference adapter for isolated v8_b2b_* InnoDB tables.
 * Not registered by the V7 WordPress plugin. Requires an authenticated,
 * independently implemented AUTHZ callback; never trust role claims in JSON.
 * The preview product/stock catalog MUST be replaced with the canonical ERP
 * catalog & custody storage before production integration.
 */
final class MariaDbRetailerGateway implements RetailerSaleGateway, RetailerMasterGateway
{
    private bool $active = false;
    private array $lockedTenders = [];

    /** $authorize returns true ONLY for authorized action, company, branch and employee. */
    public function __construct(private PDO $db, private $authorize)
    {
        $this->db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $this->db->setAttribute(PDO::ATTR_EMULATE_PREPARES, false);
        if (!is_callable($authorize)) throw new RetailerSaleError('Server authority callback is required.');
    }

    public function atomic(callable $work): array
    {
        if ($this->active || $this->db->inTransaction()) {
            throw new RetailerSaleError('Nested transaction is not supported.');
        }
        $this->active = true;
        $this->lockedTenders = [];
        try {
            $this->db->beginTransaction();
            $result = $work();
            $this->db->commit();
            return $result;
        } catch (Throwable $e) {
            if ($this->db->inTransaction()) $this->db->rollBack();
            throw $e;
        } finally {
            $this->active = false;
            $this->lockedTenders = [];
        }
    }

    private function requireTransaction(): void
    {
        if (!$this->active || !$this->db->inTransaction()) {
            throw new RetailerSaleError('Database writes require an atomic transaction.');
        }
    }

    private function query(string $sql, array $params = []): \PDOStatement
    {
        $s = $this->db->prepare($sql);
        $s->execute($params);
        return $s;
    }

    public function canManage(int $actorId, int $companyId, int $branchId): bool
    {
        return ($this->authorize)('b2b.retailer.manage', $actorId, $companyId, $branchId, null) === true;
    }

    public function canSell(int $actorId, int $companyId, int $branchId, string $channel, ?int $employeeId): bool
    {
        return ($this->authorize)('b2b.sale.create', $actorId, $companyId, $branchId, $employeeId) === true;
    }

    public function findByKey(int $companyId, int $branchId, string $key): ?array
    {
        $this->requireTransaction();
        $row = $this->query(
            'SELECT * FROM v8_b2b_retailers WHERE company_id=? AND branch_id=? AND idempotency_key=?',
            [$companyId, $branchId, $key]
        )->fetch(PDO::FETCH_ASSOC);
        return $row ?: null;
    }

    public function create(array $record): array
    {
        $this->requireTransaction();
        $this->query('INSERT INTO v8_b2b_retailers
            (company_id,branch_id,type,shop_name,contact_name,mobile,address,gstin,status,created_by,idempotency_key,request_fingerprint)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?)', [
            $record['company_id'], $record['branch_id'], $record['type'], $record['shop_name'],
            $record['contact_name'], $record['mobile'], $record['address'], $record['gstin'],
            $record['status'], $record['created_by'], $record['idempotency_key'], $record['request_fingerprint'],
        ]);
        $id = (int)$this->db->lastInsertId();
        $row = $this->get((int)$record['company_id'], (int)$record['branch_id'], $id);
        if (!$row) throw new RetailerSaleError('Unable to load registered retailer.');
        return $row;
    }

    public function get(int $companyId, int $branchId, int $retailerId): ?array
    {
        $row = $this->query('SELECT * FROM v8_b2b_retailers WHERE company_id=? AND branch_id=? AND id=? AND type=\'retailer\'',
            [$companyId, $branchId, $retailerId])->fetch(PDO::FETCH_ASSOC);
        return $row ?: null;
    }

    public function list(int $companyId, int $branchId, int $limit = 100): array
    {
        $limit = max(1, min($limit, 100));
        return $this->query("SELECT * FROM v8_b2b_retailers WHERE company_id=? AND branch_id=? AND type='retailer' ORDER BY id DESC LIMIT {$limit}",
            [$companyId, $branchId])->fetchAll(PDO::FETCH_ASSOC);
    }

    public function retailer(int $companyId, int $branchId, int $retailerId): ?array
    {
        return $this->get($companyId, $branchId, $retailerId);
    }

    public function product(int $companyId, int $branchId, int $productId): ?array
    {
        $row = $this->query('SELECT * FROM v8_b2b_catalog_preview WHERE company_id=? AND branch_id=? AND product_id=?',
            [$companyId, $branchId, $productId])->fetch(PDO::FETCH_ASSOC);
        if (!$row) return null;
        $row['batch_required'] = (bool)$row['batch_required'];
        return $row;
    }

    public function availablePcs(int $companyId, int $branchId, int $productId, int $batchId, ?int $custodianId): int
    {
        $this->requireTransaction();
        if ($batchId > 0) {
            $batch = $this->query('SELECT status,expiry_date FROM v8_b2b_batches_preview WHERE company_id=? AND branch_id=? AND product_id=? AND batch_id=? FOR UPDATE',
                [$companyId, $branchId, $productId, $batchId])->fetch(PDO::FETCH_ASSOC);
            if (!$batch || $batch['status'] !== 'active' || ($batch['expiry_date'] !== null && $batch['expiry_date'] < date('Y-m-d'))) {
                throw new RetailerSaleError('Inactive or expired batch cannot be sold.');
            }
        }
        $row = $this->query('SELECT quantity_pcs FROM v8_b2b_stock_bins_preview
            WHERE company_id=? AND branch_id=? AND product_id=? AND batch_id=? AND custodian_key=? FOR UPDATE',
            [$companyId, $branchId, $productId, $batchId, $custodianId ?? 0])->fetch(PDO::FETCH_ASSOC);
        return $row ? (int)$row['quantity_pcs'] : 0;
    }

    public function lockIdempotency(int $companyId, string $key): void
    {
        $this->requireTransaction();
        $this->query('INSERT INTO v8_b2b_sale_keys (company_id,idempotency_key) VALUES (?,?) ON DUPLICATE KEY UPDATE idempotency_key=idempotency_key',
            [$companyId, $key]);
        $this->query('SELECT sale_id FROM v8_b2b_sale_keys WHERE company_id=? AND idempotency_key=? FOR UPDATE',
            [$companyId, $key])->fetch(PDO::FETCH_ASSOC);
    }

    public function findByIdempotency(int $companyId, string $key): ?array
    {
        $this->requireTransaction();
        $row = $this->query('SELECT result_json FROM v8_b2b_sale_keys WHERE company_id=? AND idempotency_key=? FOR UPDATE',
            [$companyId, $key])->fetch(PDO::FETCH_ASSOC);
        if (!$row || $row['result_json'] === null) return null;
        $value = json_decode((string)$row['result_json'], true, 512, JSON_THROW_ON_ERROR);
        if (!is_array($value)) throw new RetailerSaleError('Corrupt idempotency response.');
        return $value;
    }

    public function confirmedTender(int $companyId, int $branchId, string $mode, string $reference, int $amountPaise): bool
    {
        $this->requireTransaction();
        $row = $this->query('SELECT id,amount_paise,status,consumed_sale_id,verified_source FROM v8_b2b_verified_tenders
            WHERE company_id=? AND branch_id=? AND payment_mode=? AND payment_reference=? FOR UPDATE',
            [$companyId, $branchId, $mode, $reference])->fetch(PDO::FETCH_ASSOC);
        if (!$row || $row['status'] !== 'confirmed' || $row['consumed_sale_id'] !== null || (int)$row['amount_paise'] !== $amountPaise) return false;
        // Source identity is inserted by trusted process, NEVER by this sale API.
        if ($mode === 'upi' && $row['verified_source'] !== 'provider') return false;
        if ($mode === 'cash' && $row['verified_source'] !== 'cashier') return false;
        $this->lockedTenders[] = (int)$row['id'];
        return true;
    }

    public function record(array $sale, array $stockMoves, array $journalLines): array
    {
        $this->requireTransaction();
        $company = (int)$sale['company_id']; $branch = (int)$sale['branch_id'];
        $dr = array_sum(array_column($journalLines, 'debit_paise'));
        $cr = array_sum(array_column($journalLines, 'credit_paise'));
        if ($dr !== $cr || $dr < 1 || $sale['invoice_total_paise'] !== $sale['paid_paise'] || $sale['retailer_outstanding_paise'] !== 0) {
            throw new RetailerSaleError('Payment/journal integrity check failed.');
        }
        if (count($this->lockedTenders) !== 1) throw new RetailerSaleError('Exactly one verified payment is required.');
        $this->query('INSERT INTO v8_b2b_sales
            (company_id,branch_id,retailer_id,channel,employee_id,actor_id,idempotency_key,payment_mode,payment_reference,
             invoice_total_paise,paid_paise,outstanding_paise,status)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)', [
            $company, $branch, $sale['retailer_id'], $sale['channel'], $sale['employee_id'],
            $sale['actor_id'], $sale['idempotency_key'], $sale['payment_mode'], $sale['payment_reference'],
            $sale['invoice_total_paise'], $sale['paid_paise'], 0, 'paid_posted',
        ]);
        $saleId = (int)$this->db->lastInsertId();
        $tender = $this->query('UPDATE v8_b2b_verified_tenders SET consumed_sale_id=?
            WHERE id=? AND company_id=? AND branch_id=? AND consumed_sale_id IS NULL AND status=\'confirmed\'',
            [$saleId, $this->lockedTenders[0], $company, $branch]);
        if ($tender->rowCount() !== 1) throw new RetailerSaleError('Payment receipt already consumed.');

        foreach ($sale['lines'] as $i => $line) {
            $this->query('INSERT INTO v8_b2b_sale_lines
                (sale_id,line_no,product_id,batch_id,qty_pcs,unit_price_paise,amount_paise,cost_paise,commercial_snapshot_json)
                VALUES (?,?,?,?,?,?,?,?,?)', [
                $saleId, $i+1, $line['product_id'], $line['batch_id'], $line['qty'],
                $line['unit_sale_price_paise'], $line['amount_paise'], $line['cost_paise'],
                json_encode($line['commercial_snapshot'], JSON_THROW_ON_ERROR),
            ]);
        }
        foreach ($stockMoves as $line) {
            $custodian = $line['custodian_id'] ?? 0;
            $updated = $this->query('UPDATE v8_b2b_stock_bins_preview
                SET quantity_pcs=quantity_pcs+? WHERE company_id=? AND branch_id=? AND product_id=? AND batch_id=?
                AND custodian_key=? AND quantity_pcs + ? >= 0', [
                $line['quantity_delta'], $company, $branch, $line['product_id'], $line['batch_id'], $custodian, $line['quantity_delta'],
            ]);
            if ($updated->rowCount() !== 1) throw new RetailerSaleError('Insufficient stock during locked movement.');
            $this->query('INSERT INTO v8_b2b_stock_movements
                (sale_id,company_id,branch_id,product_id,batch_id,custodian_key,quantity_delta,cost_paise)
                VALUES (?,?,?,?,?,?,?,?)', [
                $saleId, $company, $branch, $line['product_id'], $line['batch_id'], $custodian,
                $line['quantity_delta'], $line['cost_paise'],
            ]);
        }
        foreach ($journalLines as $i => $line) {
            $this->query('INSERT INTO v8_b2b_journal_lines (sale_id,line_no,account_code,debit_paise,credit_paise) VALUES (?,?,?,?,?)', [
                $saleId, $i+1, $line['account'], $line['debit_paise'], $line['credit_paise'],
            ]);
        }
        foreach (['invoice' => $sale['invoice_total_paise'], 'payment' => -$sale['paid_paise']] as $event => $amount) {
            $this->query('INSERT INTO v8_b2b_retailer_statement
                (sale_id,event_type,company_id,branch_id,retailer_id,amount_paise) VALUES (?,?,?,?,?,?)',
                [$saleId, $event, $company, $branch, $sale['retailer_id'], $amount]);
        }
        if ($sale['employee_cash_remittance_paise'] > 0) {
            $this->query('INSERT INTO v8_b2b_employee_remittance
                (sale_id,company_id,branch_id,employee_id,amount_due_paise,amount_remitted_paise,status)
                VALUES (?,?,?,?,?,0,\'pending\')', [
                $saleId, $company, $branch, $sale['employee_id'], $sale['employee_cash_remittance_paise'],
            ]);
        }
        $sale['id'] = $saleId;
        $encoded = json_encode($sale, JSON_THROW_ON_ERROR);
        $updated = $this->query('UPDATE v8_b2b_sale_keys
            SET sale_id=?, request_fingerprint=?, result_json=? WHERE company_id=? AND idempotency_key=? AND sale_id IS NULL',
            [$saleId, $sale['request_fingerprint'], $encoded, $company, $sale['idempotency_key']]);
        if ($updated->rowCount() !== 1) throw new RetailerSaleError('Idempotency posting failed.');
        return $sale;
    }
}