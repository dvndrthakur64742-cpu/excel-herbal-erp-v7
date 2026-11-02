<?php
namespace ExcelHerbal\ERP7\Sales;

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Finance\AccountingService;
use ExcelHerbal\ERP7\Policy\PrepaidOrderRules as Money;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Audit;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\Guard;

/**
 * Refund evidence intake/review ONLY. No money is transferred by this service.
 * No credit note, stock ledger or accounting entry is created, and the linked
 * prepaid sale remains posted. Never display "evidence_verified" as "refunded".
 */
final class PrepaidRefundEvidenceService {
    private static function returnRow(Actor $a,int $id,bool $lock):array {
        $db=Db::wpdb();
        $r=$db->get_row($db->prepare(
            'SELECT * FROM '.Db::table('prepaid_return_requests').
            ' WHERE id=%d AND company_id=%d'.($lock?' FOR UPDATE':''),
            $id,$a->companyId
        ),ARRAY_A);
        if(!$r)throw new DomainException('Prepaid return not found.','prepaid_return_not_found',404);
        Guard::branch($a,(int)$r['branch_id'],Capabilities::SALES_VIEW);
        return $r;
    }

    public static function list(Actor $a,int $returnId):array {
        $r=self::returnRow($a,$returnId,false);
        $db=Db::wpdb();
        return (array)$db->get_results($db->prepare(
            'SELECT id,return_id,order_payment_id,method,amount,evidence_reference,status,'.
            'submitted_by,submitted_at,verified_by,verified_at,verification_reference'.
            ' FROM '.Db::table('prepaid_refund_evidence').
            ' WHERE company_id=%d AND return_id=%d ORDER BY id',
            $a->companyId,(int)$r['id']
        ),ARRAY_A);
    }

    /** Log supporting documentation; does not prove the refund was disbursed. */
    public static function submit(Actor $a,int $returnId,int $originalPaymentId,string $amount,string $reference):array {
        Guard::cap($a,Capabilities::REVERSAL_CREATE);
        $reference=trim($reference);
        if(strlen($reference)<6||strlen($reference)>120)
            throw new DomainException('Refund evidence reference must be 6–120 characters.','refund_reference_required',422);
        $minor=Money::minor($amount);
        if($minor<1)throw new DomainException('Refund evidence amount must be positive.','refund_amount_invalid',422);
        return Transaction::run(function()use($a,$returnId,$originalPaymentId,$minor,$reference){
            $r=self::returnRow($a,$returnId,true);
            $branch=(int)$r['branch_id'];
            Guard::branch($a,$branch,Capabilities::REVERSAL_CREATE);
            if($r['status']!=='refund_pending')
                throw new DomainException('Refund evidence requires an independently approved physical return.','prepaid_return_state_invalid',409);
            $db=Db::wpdb();
            $payment=$db->get_row($db->prepare(
                'SELECT * FROM '.Db::table('prepaid_sales_order_payments').
                ' WHERE id=%d AND company_id=%d AND branch_id=%d AND order_id=%d FOR UPDATE',
                $originalPaymentId,$a->companyId,$branch,(int)$r['order_id']
            ),ARRAY_A);
            if(!$payment||$payment['status']!=='confirmed'||
               !in_array($payment['method'],['cash','upi'],true))
                throw new DomainException('Confirmed original Cash/UPI payment not found for this return.','refund_original_payment_invalid',409);
            if(Money::minor((string)$payment['amount'])!==$minor)
                throw new DomainException('Full-return evidence must exactly match the original payment.','refund_amount_mismatch',409);
            $account=AccountingService::paymentAccount($a,(int)$payment['payment_account_id']);
            if(strtolower((string)$account['subtype'])!==$payment['method'])
                throw new DomainException('Original payment account/method mismatch.','refund_payment_account_invalid',409);
            $t=Db::table('prepaid_refund_evidence');
            Db::mustInsert($db,$t,[
                'company_id'=>$a->companyId,'branch_id'=>$branch,
                'return_id'=>$returnId,'order_payment_id'=>$originalPaymentId,
                'payment_account_id'=>(int)$payment['payment_account_id'],
                'method'=>(string)$payment['method'],'amount'=>Money::format($minor),
                'evidence_reference'=>$reference,'status'=>'evidence_submitted',
                'submitted_by'=>$a->employeeId,'submitted_at'=>Db::now()
            ],'Refund evidence already registered for payment/reference.','refund_evidence_duplicate');
            $id=(int)$db->insert_id;
            Audit::add($a,'sales.refund.evidence.submit','prepaid_refund_evidence',$id,[
                'branch_id'=>$branch,'return_id'=>$returnId,'original_payment_id'=>$originalPaymentId,
                'method'=>$payment['method'],'amount'=>Money::format($minor)
            ]);
            return ['id'=>$id,'return_id'=>$returnId,'status'=>'evidence_submitted',
                'refund_disbursed'=>false,'credit_note_posted'=>false,'stock_posted'=>false];
        });
    }

    /**
     * Independent MANUAL evidence check. This is not a bank API confirmation.
     * Cash requires reversal-approval authority; UPI requires bank-reconcile
     * authority and an actual evidence reference to be checked operationally.
     */
    public static function verify(Actor $a,int $id,string $verificationReference):array {
        $verificationReference=trim($verificationReference);
        if(strlen($verificationReference)<6||strlen($verificationReference)>120)
            throw new DomainException('Independent verification reference must be 6–120 characters.','refund_verification_reference_required',422);
        return Transaction::run(function()use($a,$id,$verificationReference){
            $db=Db::wpdb();$t=Db::table('prepaid_refund_evidence');
            $ev=$db->get_row($db->prepare(
                "SELECT * FROM {$t} WHERE id=%d AND company_id=%d FOR UPDATE",$id,$a->companyId
            ),ARRAY_A);
            if(!$ev)throw new DomainException('Refund evidence not found.','refund_evidence_not_found',404);
            $required=$ev['method']==='upi'?Capabilities::BANK_RECONCILE:Capabilities::REVERSAL_APPROVE;
            Guard::branch($a,(int)$ev['branch_id'],$required);
            $r=self::returnRow($a,(int)$ev['return_id'],true);
            if($r['status']!=='refund_pending'||$ev['status']!=='evidence_submitted')
                throw new DomainException('Refund evidence is not awaiting verification.','refund_evidence_state_invalid',409);
            if((int)$ev['submitted_by']===$a->employeeId)
                throw new DomainException('Refund evidence needs an independent checker.','maker_checker_required',409);
            if($ev['method']==='upi')
                AccountingService::bankAccount($a,(int)$ev['payment_account_id']);
            Db::mustUpdate($db,$t,[
                'status'=>'evidence_verified','verification_reference'=>$verificationReference,
                'verified_by'=>$a->employeeId,'verified_at'=>Db::now()
            ],['id'=>$id,'company_id'=>$a->companyId]);
            Audit::add($a,'sales.refund.evidence.verify','prepaid_refund_evidence',$id,[
                'branch_id'=>(int)$ev['branch_id'],'return_id'=>(int)$r['id'],
                'method'=>$ev['method'],'manual_only'=>true
            ]);
            return ['id'=>$id,'return_id'=>(int)$r['id'],'status'=>'evidence_verified',
                'manual_evidence_only'=>true,'refund_disbursed'=>false,'credit_note_posted'=>false,
                'stock_posted'=>false];
        });
    }
}
