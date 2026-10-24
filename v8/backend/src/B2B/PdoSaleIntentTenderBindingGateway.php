<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP8\B2B;

use Closure;
use PDO;
use Throwable;

/** Disposable v8_test-only InnoDB adapter; intentionally no WordPress registration. */
final class PdoSaleIntentTenderBindingGateway implements SaleIntentTenderBindingGateway
{
    private bool $active=false;
    public function __construct(private PDO $db,private Closure $authorization)
    {
        if($db->getAttribute(PDO::ATTR_DRIVER_NAME)!=='mysql'
            ||$db->query('SELECT DATABASE()')->fetchColumn()!=='v8_test')
            throw new RetailerSaleError('Tender binding adapter requires disposable v8_test MySQL/MariaDB.');
        $db->setAttribute(PDO::ATTR_ERRMODE,PDO::ERRMODE_EXCEPTION);
    }
    public function atomic(callable $work):array
    {
        if($this->active||$this->db->inTransaction())throw new RetailerSaleError('Nested binding transaction forbidden.');
        $this->db->beginTransaction();$this->active=true;
        try{$result=$work();if(!is_array($result))throw new RetailerSaleError('Binding result invalid.');
            $this->db->commit();return $result;
        }catch(Throwable $e){if($this->db->inTransaction())$this->db->rollBack();throw $e;}
        finally{$this->active=false;}
    }
    public function lockedSaleIntent(int $company,int $branch,int $saleIntentId):?array
    {
        $this->requireLock();
        $q=$this->db->prepare('SELECT * FROM v8_b2b_sale_intents_uat WHERE id=? AND company_id=? AND branch_id=? FOR UPDATE');
        $q->execute([$saleIntentId,$company,$branch]);$row=$q->fetch(PDO::FETCH_ASSOC);
        if($row===false)return null;
        $row=$this->ints($row,['id','company_id','branch_id','retailer_id','canonical_party_id','invoice_total_paise']);
        $row['employee_id']=$row['employee_id']!==null?(int)$row['employee_id']:null;
        $row['pricing_locked']=(int)$row['pricing_locked']===1;
        return $row;
    }
    public function canBind(int $company,int $branch,int $actor,array $sale):bool
    {
        $this->requireLock();
        return ($this->authorization)($company,$branch,$actor,$sale)===true;
    }
    public function lockedPaymentIntent(int $company,int $branch,int $paymentIntentId):?array
    {
        $this->requireLock();
        $q=$this->db->prepare('SELECT p.*,l.sale_intent_id,l.quote_digest AS linked_quote_digest FROM v8_b2b_payment_intents_uat p JOIN v8_b2b_payment_intent_to_sale_uat l ON l.payment_intent_id=p.id AND l.company_id=p.company_id AND l.branch_id=p.branch_id WHERE p.id=? AND p.company_id=? AND p.branch_id=? FOR UPDATE');
        $q->execute([$paymentIntentId,$company,$branch]);$row=$q->fetch(PDO::FETCH_ASSOC);
        if($row===false)return null;
        $row=$this->ints($row,['id','company_id','branch_id','sale_intent_id','amount_paise']);
        $row['employee_id']=$row['employee_id']!==null?(int)$row['employee_id']:null;
        return $row;
    }
    public function lockedConfirmedEvidence(int $company,int $branch,int $paymentIntentId):?array
    {
        $this->requireLock();
        $q=$this->db->prepare('SELECT e.*,t.status AS tender_status,t.consumed_sale_id,t.payment_reference AS tender_ref,t.amount_paise AS tender_amount,t.payment_mode AS tender_mode,t.verified_source AS tender_source,t.company_id AS tender_company,t.branch_id AS tender_branch FROM v8_b2b_tender_intake_evidence_uat e JOIN v8_b2b_verified_tenders t ON t.id=e.confirmed_tender_id WHERE e.intent_id=? AND e.company_id=? AND e.branch_id=? FOR UPDATE');
        $q->execute([$paymentIntentId,$company,$branch]);$row=$q->fetch(PDO::FETCH_ASSOC);
        if($row===false)return null;
        $row=$this->ints($row,['intent_id','confirmed_tender_id','company_id','branch_id','amount_paise','verified_by','tender_amount','tender_company','tender_branch']);
        $row['employee_id']=$row['employee_id']!==null?(int)$row['employee_id']:null;
        $row['consumed_sale_id']=$row['consumed_sale_id']!==null?(int)$row['consumed_sale_id']:null;
        if($row['tender_company']!==$company||$row['tender_branch']!==$branch
            ||$row['tender_amount']!==$row['amount_paise']
            ||$row['tender_mode']!==$row['payment_mode']
            ||$row['tender_ref']!==$row['payment_reference']
            ||$row['tender_source']!==$row['verified_source'])
            throw new RetailerSaleError('Tender proof and verified tender ledger disagree.');
        $row['status']='confirmed'; // Presence in evidence table is the confirmation; verified tender status separately checked.
        return $row;
    }
    public function existingForSale(int $company,int $saleIntentId):?array
    {
        $this->requireLock();
        $q=$this->db->prepare('SELECT * FROM v8_b2b_sale_tender_reservations_uat WHERE company_id=? AND sale_intent_id=? FOR UPDATE');
        $q->execute([$company,$saleIntentId]);return $this->binding($q);
    }
    public function existingForTender(int $company,int $tenderId):?array
    {
        $this->requireLock();
        $q=$this->db->prepare('SELECT * FROM v8_b2b_sale_tender_reservations_uat WHERE company_id=? AND tender_id=? FOR UPDATE');
        $q->execute([$company,$tenderId]);return $this->binding($q);
    }
    public function saveReservedBinding(array $r):array
    {
        $this->requireLock();
        $q=$this->db->prepare('INSERT INTO v8_b2b_sale_tender_reservations_uat(company_id,branch_id,sale_intent_id,payment_intent_id,tender_id,retailer_id,canonical_party_id,channel,employee_id,payment_mode,payment_reference,verified_source,amount_paise,quote_digest,status) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)');
        $q->execute([$r['company_id'],$r['branch_id'],$r['sale_intent_id'],$r['payment_intent_id'],
            $r['tender_id'],$r['retailer_id'],$r['canonical_party_id'],$r['channel'],$r['employee_id'],
            $r['payment_mode'],$r['payment_reference'],$r['verified_source'],$r['amount_paise'],$r['quote_digest'],'reserved']);
        return $r+['id'=>(int)$this->db->lastInsertId()];
    }
    private function binding($q):?array
    {
        $r=$q->fetch(PDO::FETCH_ASSOC);if($r===false)return null;
        $r=$this->ints($r,['id','company_id','branch_id','sale_intent_id','payment_intent_id','tender_id','retailer_id','canonical_party_id','amount_paise']);
        $r['employee_id']=$r['employee_id']!==null?(int)$r['employee_id']:null;
        return $r;
    }
    private function ints(array $row,array $fields):array
    {foreach($fields as $field){$row[$field]=(int)$row[$field];}return $row;}
    private function requireLock():void
    {if(!$this->active||!$this->db->inTransaction())throw new RetailerSaleError('Tender binding requires an active locked transaction.');}
}
