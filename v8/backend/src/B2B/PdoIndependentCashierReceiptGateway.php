<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP8\B2B;

use PDO;
use PDOStatement;
use Throwable;

/** Dedicated disposable v8_test adapter. Intentionally NOT wired into WordPress. */
final class PdoIndependentCashierReceiptGateway implements IndependentCashierReceiptGateway
{
    private bool $inAtomic=false;
    public function __construct(private PDO $db, private $authorize)
    {
        $this->db->setAttribute(PDO::ATTR_ERRMODE,PDO::ERRMODE_EXCEPTION);
        $this->db->setAttribute(PDO::ATTR_EMULATE_PREPARES,false);
        if (!is_callable($authorize)) throw new RetailerSaleError('Server cashier RBAC required.');
        if ($this->db->query('SELECT DATABASE()')->fetchColumn() !== 'v8_test') {
            throw new RetailerSaleError('Cashier UAT gateway refuses any database other than v8_test.');
        }
    }
    private function locked():void
    {
        if (!$this->inAtomic || !$this->db->inTransaction())
            throw new RetailerSaleError('Cashier evidence must be written under its own transaction.');
    }
    private function query(string $sql,array $params=[]):PDOStatement
    {
        $stmt=$this->db->prepare($sql);
        $stmt->execute($params);
        return $stmt;
    }
    public function atomic(callable $work):array
    {
        if ($this->inAtomic || $this->db->inTransaction()) throw new RetailerSaleError('Nested cashier evidence transaction forbidden.');
        $this->inAtomic=true;
        try {
            $this->db->beginTransaction();
            $result=$work();
            $this->db->commit();
            return $result;
        } catch(Throwable $e) {
            if ($this->db->inTransaction())$this->db->rollBack();
            throw $e;
        } finally { $this->inAtomic=false; }
    }
    public function canAttest(int $actor,int $company,int $branch):bool
    {
        $this->locked();
        return ($this->authorize)('b2b.cashier.receipt.attest',$actor,$company,$branch)===true;
    }
    public function lockedFieldCash(int $company,int $branch,int $sale,int $employee):?array
    {
        $this->locked();
        $row=$this->query('SELECT s.channel,s.payment_mode,s.status sale_status,s.actor_id sale_actor_id,
                 r.amount_due_paise,r.amount_remitted_paise,r.status custody_status
            FROM v8_b2b_employee_remittance r
            JOIN v8_b2b_sales s ON s.id=r.sale_id AND s.company_id=r.company_id AND s.branch_id=r.branch_id
            WHERE r.company_id=? AND r.branch_id=? AND r.sale_id=? AND r.employee_id=?
                AND s.employee_id=r.employee_id FOR UPDATE',[$company,$branch,$sale,$employee])->fetch(PDO::FETCH_ASSOC);
        if (!$row)return null;
        foreach(['sale_actor_id','amount_due_paise','amount_remitted_paise'] as $key)$row[$key]=(int)$row[$key];
        return $row;
    }
    private function signedReceipt(string $where,array $params):?array
    {
        $this->locked();
        $row=$this->query('SELECT r.id,r.company_id,r.branch_id,r.sale_id,r.employee_id,
               r.amount_paise,r.cash_receipt_reference,r.verified_source,r.status,r.consumed_event_id,
               a.cashier_actor_id
            FROM v8_b2b_verified_branch_receipts r
            INNER JOIN v8_b2b_cashier_receipt_attestations a
               ON a.receipt_id=r.id AND a.company_id=r.company_id AND a.branch_id=r.branch_id
               AND a.sale_id=r.sale_id AND a.employee_id=r.employee_id
               AND a.cash_receipt_reference=r.cash_receipt_reference AND a.amount_paise=r.amount_paise
            WHERE '.$where.' FOR UPDATE',$params)->fetch(PDO::FETCH_ASSOC);
        if(!$row)return null;
        foreach(['id','company_id','branch_id','sale_id','employee_id','amount_paise','cashier_actor_id'] as $key)$row[$key]=(int)$row[$key];
        $row['consumed_event_id']=$row['consumed_event_id']===null?null:(int)$row['consumed_event_id'];
        return $row;
    }
    public function existingByReference(int $company,int $branch,string $reference):?array
    {
        return $this->signedReceipt('r.company_id=? AND r.branch_id=? AND r.cash_receipt_reference=?',[$company,$branch,$reference]);
    }
    public function existingBySale(int $company,int $sale):?array
    {
        return $this->signedReceipt('r.company_id=? AND r.sale_id=?',[$company,$sale]);
    }
    public function storeAttestedReceipt(array $record):array
    {
        $this->locked();
        $company=$record['company_id'];$branch=$record['branch_id'];$sale=$record['sale_id'];
        $employee=$record['employee_id'];$actor=$record['cashier_actor_id'];
        $amount=$record['amount_paise'];$reference=$record['cash_receipt_reference'];
        $this->query("INSERT INTO v8_b2b_verified_branch_receipts
           (company_id,branch_id,sale_id,employee_id,cash_receipt_reference,amount_paise,verified_source,verified_at,status)
           VALUES (?,?,?,?,?,?,'cashier',UTC_TIMESTAMP(),'confirmed')",
           [$company,$branch,$sale,$employee,$reference,$amount]);
        $id=(int)$this->db->lastInsertId();
        if($id<=0)throw new RetailerSaleError('Cashier receipt insert failed.');
        $this->query('INSERT INTO v8_b2b_cashier_receipt_attestations
          (receipt_id,company_id,branch_id,sale_id,employee_id,cashier_actor_id,amount_paise,cash_receipt_reference)
          VALUES (?,?,?,?,?,?,?,?)',[$id,$company,$branch,$sale,$employee,$actor,$amount,$reference]);
        return $record+['id'=>$id,'consumed_event_id'=>null];
    }
}
