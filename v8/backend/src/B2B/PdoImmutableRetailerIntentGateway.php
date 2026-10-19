<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP8\B2B;

use Closure;
use PDO;
use Throwable;

/**
 * Disposable v8_test-only implementation. No REST, no live V7 tables or payment.
 * Requires 004, 005 and 006 UAT schema files.
 */
final class PdoImmutableRetailerIntentGateway implements ImmutableRetailerIntentGateway
{
    private bool $inside=false;
    public function __construct(private PDO $db,private Closure $authorize)
    {
        if($db->getAttribute(PDO::ATTR_DRIVER_NAME)!=='mysql'
            ||$db->query('SELECT DATABASE()')->fetchColumn()!=='v8_test')
            throw new RetailerSaleError('Immutable UAT issuance requires disposable v8_test MariaDB.');
        $db->setAttribute(PDO::ATTR_ERRMODE,PDO::ERRMODE_EXCEPTION);
    }
    public function atomic(callable $operation):array
    {
        if($this->inside||$this->db->inTransaction())throw new RetailerSaleError('Nested intent issuance transaction forbidden.');
        $this->db->beginTransaction();$this->inside=true;
        try{
            $out=$operation();
            if(!is_array($out))throw new RetailerSaleError('Invalid immutable issuance result.');
            $this->db->commit();return $out;
        }catch(Throwable $e){if($this->db->inTransaction())$this->db->rollBack();throw $e;}
        finally{$this->inside=false;}
    }
    public function lockRequest(int $companyId,string $requestKey):void
    {
        $this->locked();
        $q=$this->db->prepare('INSERT INTO v8_b2b_intent_issuance_requests_uat(company_id,request_key) VALUES (?,?) ON DUPLICATE KEY UPDATE request_key=request_key');
        $q->execute([$companyId,$requestKey]);
        $q=$this->db->prepare('SELECT request_key FROM v8_b2b_intent_issuance_requests_uat WHERE company_id=? AND request_key=? FOR UPDATE');
        $q->execute([$companyId,$requestKey]);
        if($q->fetchColumn()!==$requestKey)throw new RetailerSaleError('Cannot serialize immutable quote issuance.');
    }
    public function canIssue(int $companyId,int $branchId,int $actorId,?int $employeeId,string $channel):bool
    {
        $this->locked();
        // Resolver must check actor identity, branch authority and field custody.
        return ($this->authorize)($companyId,$branchId,$actorId,$employeeId,$channel)===true;
    }
    public function existingPair(int $companyId,string $requestKey):?array
    {
        $this->locked();
        $sql='SELECT s.id AS sale_intent_id,p.id AS payment_intent_id,s.company_id,s.branch_id,
          s.retailer_id,s.canonical_party_id,s.channel,s.employee_id,s.payment_mode,
          s.merchant_order_id,s.invoice_total_paise,s.quote_digest,s.pricing_locked,s.currency,s.status,
          p.amount_paise AS payment_amount,p.currency AS payment_currency,p.status AS payment_status,
          l.quote_digest AS linked_digest,l.sale_intent_id AS linked_sale
          FROM v8_b2b_intent_issuance_requests_uat r
          JOIN v8_b2b_sale_intents_uat s ON s.id=r.sale_intent_id AND s.company_id=r.company_id
          JOIN v8_b2b_payment_intents_uat p ON p.id=r.payment_intent_id AND p.company_id=r.company_id
          JOIN v8_b2b_payment_intent_to_sale_uat l ON l.payment_intent_id=p.id AND l.sale_intent_id=s.id
          WHERE r.company_id=? AND r.request_key=? FOR UPDATE';
        $q=$this->db->prepare($sql);$q->execute([$companyId,$requestKey]);
        $r=$q->fetch(PDO::FETCH_ASSOC);
        if($r===false){
            // Any broken half-written receipt is a hard failure, never an invitation to duplicate.
            $q=$this->db->prepare('SELECT sale_intent_id,payment_intent_id FROM v8_b2b_intent_issuance_requests_uat WHERE company_id=? AND request_key=? FOR UPDATE');
            $q->execute([$companyId,$requestKey]);$receipt=$q->fetch(PDO::FETCH_ASSOC);
            if($receipt!==false && ($receipt['sale_intent_id']!==null||$receipt['payment_intent_id']!==null))
                throw new RetailerSaleError('Issued intent receipt does not reconcile to sale and payment rows.');
            return null;
        }
        foreach(['sale_intent_id','payment_intent_id','company_id','branch_id','retailer_id','canonical_party_id','invoice_total_paise','payment_amount','linked_sale'] as $f)$r[$f]=(int)$r[$f];
        $r['employee_id']=$r['employee_id']!==null?(int)$r['employee_id']:null;
        $r['pricing_locked']=(int)$r['pricing_locked']===1;
        if($r['payment_amount']!==$r['invoice_total_paise']||$r['linked_sale']!==$r['sale_intent_id']
            ||$r['linked_digest']!==$r['quote_digest']||$r['payment_currency']!=='INR'
            ||$r['payment_status']!=='awaiting_payment')
            throw new RetailerSaleError('Existing payment intent does not match the locked sale.');
        return $r;
    }
    public function createPair(array $s,string $key,?string $order):array
    {
        $this->locked();
        $sale=$this->db->prepare('INSERT INTO v8_b2b_sale_intents_uat
          (company_id,branch_id,retailer_id,canonical_party_id,channel,employee_id,payment_mode,
          merchant_order_id,currency,invoice_total_paise,quote_digest,pricing_locked,status)
          VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)');
        $sale->execute([$s['company_id'],$s['branch_id'],$s['retailer_id'],$s['canonical_party_id'],
            $s['channel'],$s['employee_id'],$s['payment_mode'],$order,'INR',$s['gross_paise'],
            hash('sha256',json_encode($s,JSON_THROW_ON_ERROR)),1,'awaiting_payment']);
        $sid=(int)$this->db->lastInsertId();
        $pay=$this->db->prepare('INSERT INTO v8_b2b_payment_intents_uat
          (company_id,branch_id,channel,employee_id,payment_mode,amount_paise,merchant_order_id,currency,status)
          VALUES (?,?,?,?,?,?,?,?,?)');
        $pay->execute([$s['company_id'],$s['branch_id'],$s['channel'],$s['employee_id'],
            $s['payment_mode'],$s['gross_paise'],$order,'INR','awaiting_payment']);
        $pid=(int)$this->db->lastInsertId();
        $digest=hash('sha256',json_encode($s,JSON_THROW_ON_ERROR));
        $link=$this->db->prepare('INSERT INTO v8_b2b_payment_intent_to_sale_uat
          (payment_intent_id,sale_intent_id,company_id,branch_id,quote_digest) VALUES (?,?,?,?,?)');
        $link->execute([$pid,$sid,$s['company_id'],$s['branch_id'],$digest]);
        $receipt=$this->db->prepare('UPDATE v8_b2b_intent_issuance_requests_uat SET sale_intent_id=?,payment_intent_id=? WHERE company_id=? AND request_key=? AND sale_intent_id IS NULL AND payment_intent_id IS NULL');
        $receipt->execute([$sid,$pid,$s['company_id'],$key]);
        if($receipt->rowCount()!==1)throw new RetailerSaleError('Immutable issuance ownership changed concurrently.');
        return ['sale_intent_id'=>$sid,'payment_intent_id'=>$pid,
            'company_id'=>$s['company_id'],'branch_id'=>$s['branch_id'],
            'retailer_id'=>$s['retailer_id'],'canonical_party_id'=>$s['canonical_party_id'],
            'channel'=>$s['channel'],'employee_id'=>$s['employee_id'],
            'payment_mode'=>$s['payment_mode'],'merchant_order_id'=>$order,
            'currency'=>'INR','invoice_total_paise'=>$s['gross_paise'],
            'quote_digest'=>$digest,'status'=>'awaiting_payment','pricing_locked'=>true];
    }
    private function locked():void
    {if(!$this->inside||!$this->db->inTransaction())throw new RetailerSaleError('Issuance requires an active locked transaction.');}
}
