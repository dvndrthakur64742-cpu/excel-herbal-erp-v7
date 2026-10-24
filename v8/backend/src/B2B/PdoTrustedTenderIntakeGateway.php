<?php
declare(strict_types=1);

namespace ExcelHerbal\ERP8\B2B;

require_once __DIR__.'/AuthenticatedUpiSettlementSource.php';

use Closure;
use PDO;
use Throwable;

/**
 * Disposable MySQL/MariaDB UAT implementation of trusted tender intake.
 * NOT canonical ERP posting, NOT a WordPress HTTP handler, NOT a payment provider client.
 * Guard both construction and active operations against a live/non-UAT database.
 * UPI verification accepts only a typed authenticated source; null explicitly disables UPI.
 * An arbitrary callable is never accepted for signed/bank proof.
 * Cash/actor/merchant authority callbacks remain UAT-only and must be server-resolved.
 */
final class PdoTrustedTenderIntakeGateway implements TrustedTenderIntakeGateway
{
    private bool $inTransaction=false;
    public function __construct(
        private PDO $db,
        private Closure $cashAuthorization,
        private Closure $upiAuthorization,
        private ?AuthenticatedUpiSettlementSource $verifiedBankLookup,
        private Closure $merchantAccountLookup
    ) {
        if($db->getAttribute(PDO::ATTR_DRIVER_NAME)!=='mysql'){
            throw new RetailerSaleError('InnoDB MySQL/MariaDB driver is required for atomic payment evidence.');
        }
        $db->setAttribute(PDO::ATTR_ERRMODE,PDO::ERRMODE_EXCEPTION);
        $this->requireDisposableDatabase();
    }

    public function atomic(callable $operation):array
    {
        if($this->inTransaction||$this->db->inTransaction())throw new RetailerSaleError('Nested tender intake transactions are forbidden.');
        $this->requireDisposableDatabase();
        $this->db->beginTransaction();$this->inTransaction=true;
        try{
            $result=$operation();
            if(!is_array($result))throw new RetailerSaleError('Tender intake result is invalid.');
            $this->db->commit();return $result;
        }catch(Throwable $e){if($this->db->inTransaction())$this->db->rollBack();throw $e;}
        finally{$this->inTransaction=false;}
    }

    public function lockedIntent(int $companyId,int $branchId,int $intentId):?array
    {
        $this->requireTransaction();
        $q=$this->db->prepare('SELECT * FROM v8_b2b_payment_intents_uat WHERE id=? AND company_id=? AND branch_id=? FOR UPDATE');
        $q->execute([$intentId,$companyId,$branchId]);$r=$q->fetch(PDO::FETCH_ASSOC);
        if($r===false)return null;
        foreach(['id','company_id','branch_id','amount_paise'] as $k)$r[$k]=(int)$r[$k];
        $r['employee_id']=$r['employee_id']!==null?(int)$r['employee_id']:null;
        return $r;
    }

    public function canCollectCash(int $companyId,int $branchId,int $actorId,string $channel,?int $employeeId):bool
    {
        return ($this->cashAuthorization)($companyId,$branchId,$actorId,$channel,$employeeId)===true;
    }

    public function canVerifyUpi(int $companyId,int $branchId,int $actorId):bool
    {
        return ($this->upiAuthorization)($companyId,$branchId,$actorId)===true;
    }

    public function verifiedBankPayment(string $providerLookupKey):?array
    {
        // Inject a pre-reconciled trusted bank record reader, not an unbounded external
        // network call inside the open database transaction.
        $value=$this->verifiedBankLookup?->verifySettlement($providerLookupKey); // null: UPI disabled, always fail closed
        return is_array($value)?$value:null;
    }

    public function merchantAccount(int $companyId,int $branchId):string
    {
        $value=($this->merchantAccountLookup)($companyId,$branchId);
        return is_string($value)?$value:'';
    }

    public function recordConfirmed(array $evidence):array
    {
        $this->requireTransaction();
        $company=$evidence['company_id'];$branch=$evidence['branch_id'];$intentId=$evidence['intent_id'];
        $q=$this->db->prepare('SELECT * FROM v8_b2b_tender_intake_evidence_uat WHERE intent_id=? FOR UPDATE');
        $q->execute([$intentId]);$existing=$q->fetch(PDO::FETCH_ASSOC);
        if($existing!==false){
            foreach(['company_id','branch_id','payment_mode','payment_reference','amount_paise','verified_source','verified_by','channel','employee_id'] as $field){
                $a=$existing[$field];$b=$evidence[$field];
                if($a!==null && in_array($field,['company_id','branch_id','amount_paise','verified_by','employee_id'],true))$a=(int)$a;
                if($a!==$b)throw new RetailerSaleError('Payment intent already has different confirmed evidence.');
            }
            return ['intent_id'=>$intentId,'tender_id'=>(int)$existing['confirmed_tender_id'],
                'payment_reference'=>(string)$existing['payment_reference'],
                'payment_mode'=>(string)$existing['payment_mode'],'amount_paise'=>(int)$existing['amount_paise'],
                'verified_source'=>(string)$existing['verified_source'],'status'=>'confirmed'];
        }
        // Prevent a UPI bank reference being credited across companies or branches;
        // the global unique index is the final guard for concurrent INSERT races.
        $q=$this->db->prepare('SELECT intent_id FROM v8_b2b_tender_intake_evidence_uat WHERE payment_mode=? AND payment_reference=? FOR UPDATE');
        $q->execute([$evidence['payment_mode'],$evidence['payment_reference']]);
        if($q->fetchColumn()!==false)throw new RetailerSaleError('Payment reference already allocated to another intent.');
        $q=$this->db->prepare("INSERT INTO v8_b2b_verified_tenders(company_id,branch_id,payment_mode,payment_reference,amount_paise,verified_source,verified_at,status) VALUES(?,?,?,?,?,?,UTC_TIMESTAMP(),'confirmed')");
        $q->execute([$company,$branch,$evidence['payment_mode'],$evidence['payment_reference'],$evidence['amount_paise'],$evidence['verified_source']]);
        $tenderId=(int)$this->db->lastInsertId();
        $q=$this->db->prepare('INSERT INTO v8_b2b_tender_intake_evidence_uat(intent_id,confirmed_tender_id,company_id,branch_id,payment_mode,payment_reference,amount_paise,verified_source,verified_by,channel,employee_id) VALUES(?,?,?,?,?,?,?,?,?,?,?)');
        $q->execute([$intentId,$tenderId,$company,$branch,$evidence['payment_mode'],$evidence['payment_reference'],$evidence['amount_paise'],$evidence['verified_source'],$evidence['verified_by'],$evidence['channel'],$evidence['employee_id']]);
        return ['intent_id'=>$intentId,'tender_id'=>$tenderId,'payment_reference'=>$evidence['payment_reference'],
            'payment_mode'=>$evidence['payment_mode'],'amount_paise'=>$evidence['amount_paise'],
            'verified_source'=>$evidence['verified_source'],'status'=>'confirmed'];
    }

    private function requireTransaction():void
    {
        if(!$this->inTransaction||!$this->db->inTransaction())throw new RetailerSaleError('Locked tender operation requires transaction.');
        $this->requireDisposableDatabase();
    }

    private function requireDisposableDatabase():void
    {
        if($this->db->query('SELECT DATABASE()')->fetchColumn() !== 'v8_test'){
            throw new RetailerSaleError('Trusted tender intake must use disposable v8_test only.');
        }
    }
}
