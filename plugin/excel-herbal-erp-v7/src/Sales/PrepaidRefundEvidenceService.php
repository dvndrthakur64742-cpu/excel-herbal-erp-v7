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
            "submitted_by,submitted_at,verified_by,verified_at,verification_reference,(SELECT MAX(j.id) FROM ".Db::table('journal_entries')." j WHERE j.company_id=e.company_id AND j.source_type IN ('external_upi_refund','external_cash_refund') AND j.source_id=e.id AND j.status='posted') AS external_journal_id".
            ' FROM '.Db::table('prepaid_refund_evidence').' e'.
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
            // The return row serializes submissions for this return. A lost
            // response can be recovered only by the original submitter.
            $existing=$db->get_row($db->prepare(
                "SELECT * FROM {$t} WHERE company_id=%d AND order_payment_id=%d",
                $a->companyId,$originalPaymentId
            ),ARRAY_A);
            if($existing){
                if((int)$existing['return_id']!==$returnId || (int)$existing['branch_id']!==$branch ||
                   (int)$existing['submitted_by']!==$a->employeeId || $existing['evidence_reference']!==$reference ||
                   Money::minor((string)$existing['amount'])!==$minor || $existing['method']!==$payment['method'] ||
                   (int)$existing['payment_account_id']!==(int)$payment['payment_account_id'])
                    throw new DomainException('Refund evidence already registered for payment/reference.','refund_evidence_duplicate',409);
                return ['id'=>(int)$existing['id'],'return_id'=>$returnId,'status'=>$existing['status'],
                    'refund_disbursed'=>false,'credit_note_posted'=>false,'stock_posted'=>false];
            }
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
            if($r['status']==='refund_pending' && $ev['status']==='evidence_verified' &&
               (int)$ev['verified_by']===$a->employeeId && $ev['verification_reference']===$verificationReference){
                return ['id'=>$id,'return_id'=>(int)$r['id'],'status'=>'evidence_verified',
                    'manual_evidence_only'=>true,'refund_disbursed'=>false,'credit_note_posted'=>false,'stock_posted'=>false];
            }
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
    public static function postExternalUpi(Actor $a,int $id,string $reference):array {
        return self::postExternal($a,$id,$reference,null);
    }

    public static function postExternalCash(Actor $a,int $id,string $reference,string $paidOn):array {
        $date=\ExcelHerbal\ERP7\Core\Input::date($paidOn,'Cash voucher date');
        if($date>Db::today())throw new DomainException('Cash voucher date cannot be in the future.','refund_cash_date_invalid',422);
        return self::postExternal($a,$id,$reference,$date);
    }

    private static function postExternal(Actor $a,int $id,string $reference,?string $cashDate):array {
        $method=$cashDate===null?'upi':'cash';
        $cap=$method==='upi'?Capabilities::BANK_RECONCILE:Capabilities::REVERSAL_APPROVE;
        Guard::cap($a,$cap);
        $reference=trim($reference);
        return Transaction::run(function()use($a,$id,$reference,$cashDate,$method,$cap){
            $db=Db::wpdb();
            $ev=$db->get_row($db->prepare("SELECT * FROM ".Db::table('prepaid_refund_evidence').
                " WHERE company_id=%d AND id=%d FOR UPDATE",$a->companyId,$id),ARRAY_A);
            if(!$ev)throw new DomainException('Refund evidence not found.','refund_evidence_not_found',404);
            $branch=(int)$ev['branch_id'];
            Guard::branch($a,$branch,$cap);
            $r=self::returnRow($a,(int)$ev['return_id'],true);
            if($ev['method']!==$method||$ev['status']!=='evidence_verified'||(int)$ev['verified_by']<1||
               (int)$ev['submitted_by']===(int)$ev['verified_by']||(int)$ev['submitted_by']===$a->employeeId||
               (int)$r['branch_id']!==$branch||$reference===''||$reference!==$ev['evidence_reference'])
                throw new DomainException('An independently verified refund voucher or bank reference is required.','refund_post_evidence_invalid',409);
            $source='external_'.$method.'_refund';
            $prior=$db->get_row($db->prepare("SELECT id,status,entry_date FROM ".Db::table('journal_entries').
                " WHERE company_id=%d AND source_type=%s AND source_id=%d ORDER BY id DESC LIMIT 1 FOR UPDATE",
                $a->companyId,$source,$id),ARRAY_A);
            if($prior){
                if($prior['status']!=='posted'||($cashDate!==null && substr($prior['entry_date'],0,10)!==$cashDate))throw new DomainException('Finance review required for prior posting.','refund_prior_posting',409);
                return ['journal_id'=>(int)$prior['id'],'status'=>'external_payment_recorded'];
            }
            $detail=PrepaidReturnService::detail($a,(int)$r['id']);
            if(!$detail['refund_evidence_check']['evidence_complete'])
                throw new DomainException('Reconcile all original tenders before posting.','refund_evidence_incomplete',409);
            PrepaidReturnService::requirePostedSource($a->companyId,$branch,(int)$r['order_id'],(int)$r['sale_id'],(string)$r['refund_amount']);
            $account=(int)$ev['payment_account_id'];
            $paymentAccount=AccountingService::paymentAccount($a,$account);
            if(strtolower((string)$paymentAccount['subtype'])!==$method)
                throw new DomainException('Refund account must match the original payment method.','refund_payment_account_invalid',409);
            $date=$cashDate;
            $line=null;
            if($method==='upi'){
                $rows=$db->get_results($db->prepare("SELECT l.* FROM ".Db::table('bank_statement_lines')." l JOIN ".
                    Db::table('bank_reconciliations')." b ON b.id=l.reconciliation_id WHERE b.company_id=%d AND b.branch_id=%d
                    AND b.bank_account_id=%d AND l.reference=%s LIMIT 2 FOR UPDATE",$a->companyId,$branch,$account,$reference),ARRAY_A);
                if(count($rows??[])!==1 || $rows[0]['status']!=='unmatched' || Money::minor($rows[0]['debit'])!==Money::minor($ev['amount']) ||
                   Money::minor($rows[0]['credit'])!==0)
                    throw new DomainException('One unmatched bank debit with the same reference and amount is required.','refund_bank_debit_invalid',409);
                $line=$rows[0];$date=$line['txn_date'];
            }
            \ExcelHerbal\ERP7\Finance\BranchDayGuard::assertOpen($a,$branch,$date);
            $clearing=AccountingService::accountByCode($a,'REFUND_CLEARING');
            if($clearing['type']!=='asset'||(int)$clearing['id']===$account)
                throw new DomainException('Configure a separate refund clearing asset account.','refund_clearing_invalid',409);
            $journal=AccountingService::post($a,$branch,$source,$id,$date,[
                ['account_id'=>(int)$clearing['id'],'debit'=>$ev['amount']],
                ['account_id'=>$account,'credit'=>$ev['amount']]
            ],'External '.strtoupper($method).' refund '.$reference);
            if($line!==null){
                $credit=(int)$db->get_var($db->prepare("SELECT id FROM ".Db::table('journal_lines').
                    " WHERE journal_entry_id=%d AND account_id=%d AND credit>0",$journal,$account));
                \ExcelHerbal\ERP7\Finance\FinanceBankService::bankMatch($a,(int)$line['id'],$credit);
            }
            Audit::add($a,'sales.refund.external_'.$method.'_post',$source,$id,['journal_id'=>$journal,'statement_line_id'=>$line===null?null:(int)$line['id'],'payment_reference'=>$reference,'paid_on'=>$date,'branch_id'=>$branch]);
            return ['journal_id'=>$journal,'status'=>'external_payment_recorded'];
        });
    }

}
