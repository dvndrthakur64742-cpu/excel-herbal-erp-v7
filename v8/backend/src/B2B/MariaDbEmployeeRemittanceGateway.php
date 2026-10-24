<?php
declare(strict_types=1);

namespace ExcelHerbal\ERP8\B2B;

use PDO;
use Throwable;

/** Isolated UAT adapter; no WordPress route, no live cashier evidence writer. */
final class MariaDbEmployeeRemittanceGateway implements EmployeeRemittanceGateway
{
    private bool $active = false;
    private ?int $lockedReceipt = null;

    public function __construct(private PDO $db, private $authorize)
    {
        $this->db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $this->db->setAttribute(PDO::ATTR_EMULATE_PREPARES, false);
        if (!is_callable($authorize)) throw new RetailerSaleError('Server cashier authority callback required.');
        $this->requireDisposableDatabase();
    }

    private function requireDisposableDatabase(): void
    {
        if ($this->db->getAttribute(PDO::ATTR_DRIVER_NAME) !== 'mysql'
            || $this->db->query('SELECT DATABASE()')->fetchColumn() !== 'v8_test') {
            throw new RetailerSaleError('Cash remittance UAT must use disposable v8_test only.');
        }
    }

    public function atomic(callable $work): array
    {
        $this->requireDisposableDatabase();
        if ($this->active || $this->db->inTransaction()) throw new RetailerSaleError('Nested remittance transaction denied.');
        $this->active = true;
        $this->lockedReceipt = null;
        try {
            $this->db->beginTransaction();
            $result = $work();
            $this->requireDisposableDatabase();
            $this->db->commit();
            return $result;
        } catch (Throwable $e) {
            if ($this->db->inTransaction()) $this->db->rollBack();
            throw $e;
        } finally {
            $this->active = false;
            $this->lockedReceipt = null;
        }
    }

    private function requireAtomic(): void
    {
        if (!$this->active || !$this->db->inTransaction()) throw new RetailerSaleError('Remittance writes require atomic transaction.');
        $this->requireDisposableDatabase();
    }

    private function sql(string $query, array $args = []): \PDOStatement
    {
        $s = $this->db->prepare($query);
        $s->execute($args);
        return $s;
    }

    public function canConfirmRemittance(int $actorId, int $companyId, int $branchId): bool
    {
        return ($this->authorize)('b2b.remittance.confirm', $actorId, $companyId, $branchId, null) === true;
    }

    public function lockRemittanceKey(int $companyId, string $key): void
    {
        $this->requireAtomic();
        $this->sql('INSERT INTO v8_b2b_remittance_keys (company_id,idempotency_key) VALUES (?,?) ON DUPLICATE KEY UPDATE idempotency_key=idempotency_key', [$companyId,$key]);
        $this->sql('SELECT event_id FROM v8_b2b_remittance_keys WHERE company_id=? AND idempotency_key=? FOR UPDATE', [$companyId,$key])->fetch(PDO::FETCH_ASSOC);
    }

    public function remittanceByKey(int $companyId, string $key): ?array
    {
        $this->requireAtomic();
        $result = $this->sql('SELECT result_json FROM v8_b2b_remittance_keys WHERE company_id=? AND idempotency_key=? FOR UPDATE', [$companyId,$key])->fetch(PDO::FETCH_ASSOC);
        if (!$result || $result['result_json'] === null) return null;
        $value = json_decode((string)$result['result_json'], true, 512, JSON_THROW_ON_ERROR);
        if (!is_array($value)) throw new RetailerSaleError('Corrupt remittance idempotency record.');
        return $value;
    }

    public function pendingCash(int $companyId, int $branchId, int $saleId, int $employeeId): ?array
    {
        $this->requireAtomic();
        $r = $this->sql('SELECT r.amount_due_paise,r.amount_remitted_paise,r.status
             FROM v8_b2b_employee_remittance r JOIN v8_b2b_sales s ON s.id=r.sale_id
             WHERE r.company_id=? AND r.branch_id=? AND r.sale_id=? AND r.employee_id=?
             AND s.company_id=r.company_id AND s.branch_id=r.branch_id
             AND s.channel=\'field\' AND s.payment_mode=\'cash\' AND s.status=\'paid_posted\' FOR UPDATE',
             [$companyId,$branchId,$saleId,$employeeId])->fetch(PDO::FETCH_ASSOC);
        if (!$r) return null;
        return ['amount_due_paise'=>(int)$r['amount_due_paise'], 'amount_remitted_paise'=>(int)$r['amount_remitted_paise'], 'status'=>$r['status']];
    }

    public function confirmedBranchReceipt(int $companyId, int $branchId, int $saleId, int $employeeId, string $reference, int $amountPaise): bool
    {
        $this->requireAtomic();
        // A bare 'cashier' string is NOT payment proof: require a separate,
        // independently-authorized signed attestation for this exact receipt.
        $r = $this->sql('SELECT r.id FROM v8_b2b_verified_branch_receipts r
             JOIN v8_b2b_cashier_receipt_attestations a
               ON a.receipt_id=r.id AND a.company_id=r.company_id AND a.branch_id=r.branch_id
               AND a.sale_id=r.sale_id AND a.employee_id=r.employee_id
               AND a.amount_paise=r.amount_paise AND a.cash_receipt_reference=r.cash_receipt_reference
             JOIN v8_b2b_sales s ON s.id=r.sale_id AND s.company_id=r.company_id
               AND s.branch_id=r.branch_id AND s.employee_id=r.employee_id
             WHERE r.company_id=? AND r.branch_id=? AND r.sale_id=? AND r.employee_id=?
             AND r.cash_receipt_reference=? AND r.amount_paise=? AND r.verified_source=\'cashier\'
             AND r.status=\'confirmed\' AND r.consumed_event_id IS NULL
             AND a.cashier_actor_id<>s.actor_id FOR UPDATE',
             [$companyId,$branchId,$saleId,$employeeId,$reference,$amountPaise])->fetch(PDO::FETCH_ASSOC);
        $this->lockedReceipt = $r ? (int)$r['id'] : null;
        return $this->lockedReceipt !== null;
    }

    public function recordCashRemittance(array $record, array $journal): array
    {
        $this->requireAtomic();
        $company = (int)$record['company_id'];
        $branch = (int)$record['branch_id'];
        $sale = (int)$record['sale_id'];
        $employee = (int)$record['employee_id'];
        $amount = (int)$record['amount_paise'];
        if ($this->lockedReceipt === null || $amount < 1 || count($journal) !== 2
            || $journal[0] !== ['account'=>'BRANCH_CASH','debit_paise'=>$amount,'credit_paise'=>0]
            || $journal[1] !== ['account'=>'EMPLOYEE_CASH_IN_TRANSIT','debit_paise'=>0,'credit_paise'=>$amount]) {
            throw new RetailerSaleError('Unverified or unbalanced remittance journal.');
        }
        $this->sql('INSERT INTO v8_b2b_remittance_events
            (company_id,branch_id,sale_id,employee_id,actor_id,amount_paise,cash_receipt_reference,idempotency_key,status)
            VALUES (?,?,?,?,?,?,?,?,\'posted\')',
            [$company,$branch,$sale,$employee,$record['actor_id'],$amount,$record['cash_receipt_reference'],$record['idempotency_key']]);
        $event = (int)$this->db->lastInsertId();
        $cash = $this->sql('UPDATE v8_b2b_employee_remittance
            SET amount_remitted_paise=?,status=\'settled\'
            WHERE company_id=? AND branch_id=? AND employee_id=? AND sale_id=?
              AND status=\'pending\' AND amount_due_paise=? AND amount_remitted_paise=0',
            [$amount,$company,$branch,$employee,$sale,$amount]);
        if ($cash->rowCount() !== 1) throw new RetailerSaleError('Cash already settled or amount mismatched.');
        $receipt = $this->sql('UPDATE v8_b2b_verified_branch_receipts SET consumed_event_id=?
            WHERE id=? AND company_id=? AND branch_id=? AND consumed_event_id IS NULL AND status=\'confirmed\'',
            [$event,$this->lockedReceipt,$company,$branch]);
        if ($receipt->rowCount() !== 1) throw new RetailerSaleError('Cash receipt already consumed.');
        foreach ($journal as $i=>$line) {
            $this->sql('INSERT INTO v8_b2b_remittance_journal_lines (event_id,line_no,account_code,debit_paise,credit_paise)
                VALUES (?,?,?,?,?)', [$event,$i+1,$line['account'],$line['debit_paise'],$line['credit_paise']]);
        }
        $record['id'] = $event;
        $updated = $this->sql('UPDATE v8_b2b_remittance_keys SET event_id=?,result_json=?
            WHERE company_id=? AND idempotency_key=? AND event_id IS NULL',
            [$event,json_encode($record, JSON_THROW_ON_ERROR),$company,$record['idempotency_key']]);
        if ($updated->rowCount() !== 1) throw new RetailerSaleError('Remittance idempotency write failed.');
        return $record;
    }
}
