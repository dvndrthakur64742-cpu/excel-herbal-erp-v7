<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP8\B2B;

/**
 * UAT-only, same-database V8 evidence => canonical V7 verified-tender bridge.
 * The reader MUST hold SELECT FOR UPDATE locks on immutable sale, reservation,
 * payment, intake evidence and original tender before invoking this method.
 * Not a payment verification source, not an HTTP route, not a production SDK.
 */
final class V7UatCanonicalTenderBridge
{
    /**
     * @return array<string,mixed> The canonical tender locked in the caller's transaction.
     */
    public static function ensure(object $db, array $sale, array $reservation,
        array $payment, array $evidence, array $tender): array
    {
        V7CanonicalPostingSinkUat::assertNonProductionEnvironment($db);
        $n=static function (mixed $v):int {
            if ((!is_string($v) && !is_int($v)) || !ctype_digit((string)$v)
                || strlen((string)$v)>18 || (int)$v<1) {
                throw new RetailerSaleError('Invalid locked verified-tender identifier.');
            }
            return (int)$v;
        };
        $co=$n($sale['company_id']??null);$branch=$n($sale['branch_id']??null);
        $saleId=$n($sale['id']??null);$payId=$n($payment['id']??null);
        $tenderId=$n($tender['id']??null);$verifiedBy=$n($evidence['verified_by']??null);
        $amount=$n($sale['invoice_total_paise']??null);
        $digest=$sale['quote_digest']??null;
        $mode=$sale['payment_mode']??null;$channel=$sale['channel']??null;
        $employee=$sale['employee_id']===null?null:$n($sale['employee_id']);
        $source=$mode==='upi'?'bank_settlement':($channel==='field'?'employee_cash_custody':'branch_cashier_cash');
        $reference=$evidence['payment_reference']??null;
        if(!is_string($digest)||!preg_match('/^[a-f0-9]{64}$/D',$digest)
            ||!in_array($mode,['cash','upi'],true)||!in_array($channel,['field','counter'],true)
            ||($channel==='field'&&$employee===null)||($channel==='counter'&&$employee!==null)
            ||!is_string($reference)||!preg_match('/^[A-Za-z0-9][A-Za-z0-9._:\/-]{7,127}$/D',$reference)
            ||($sale['currency']??null)!=='INR'||($payment['currency']??null)!=='INR'
            ||($sale['status']??null)!=='awaiting_payment'||($payment['status']??null)!=='awaiting_payment'
            ||($reservation['status']??null)!=='reserved'||($tender['status']??null)!=='confirmed'
            ||($tender['consumed_sale_id']??null)!==null
            ||($evidence['verified_source']??null)!==$source||($tender['verified_source']??null)!==$source
            ||($evidence['payment_reference']??null)!==($tender['payment_reference']??null)
            ||($reservation['payment_reference']??null)!==$reference
            ||($reservation['quote_digest']??null)!==$digest
            ||($reservation['payment_mode']??null)!==$mode||($reservation['channel']??null)!==$channel
            ||($reservation['verified_source']??null)!==$source
            ||($reservation['employee_id']===null?null:$n($reservation['employee_id']))!==$employee
            ||($evidence['employee_id']===null?null:$n($evidence['employee_id']))!==$employee
            ||($evidence['channel']??null)!==$channel||($evidence['payment_mode']??null)!==$mode
            ||($tender['payment_mode']??null)!==$mode
            ||$n($payment['amount_paise']??null)!==$amount
            ||$n($reservation['amount_paise']??null)!==$amount
            ||$n($evidence['amount_paise']??null)!==$amount
            ||$n($tender['amount_paise']??null)!==$amount
            ||$n($reservation['sale_intent_id']??null)!==$saleId
            ||$n($reservation['payment_intent_id']??null)!==$payId
            ||$n($reservation['tender_id']??null)!==$tenderId
            ||$n($evidence['intent_id']??null)!==$payId
            ||$n($evidence['confirmed_tender_id']??null)!==$tenderId) {
            throw new RetailerSaleError('Locked payment evidence is not eligible for canonical tender promotion.');
        }
        foreach([$reservation,$payment,$evidence,$tender] as $row){
            if($n($row['company_id']??null)!==$co||$n($row['branch_id']??null)!==$branch){
                throw new RetailerSaleError('Cross-company or cross-branch tender promotion denied.');
            }
        }
        $prefix=$db->prefix??null;
        if(!is_string($prefix)||!preg_match('/^[A-Za-z0-9_]{1,60}$/D',$prefix))
            throw new RetailerSaleError('Unsafe canonical table prefix.');
        $table=$prefix.'eh7_b2b_verified_tenders';
        $find=$db->prepare("SELECT * FROM {$table} WHERE company_id=%d AND branch_id=%d AND sale_intent_id=%d FOR UPDATE",$co,$branch,$saleId);
        if(!is_string($find))throw new RetailerSaleError('Cannot prepare canonical verified tender lock.');
        $existing=$db->get_row($find,defined('ARRAY_A')?ARRAY_A:'ARRAY_A');
        if(($db->last_error??'')!=='')throw new RetailerSaleError('Cannot read canonical verified tender.');
        if($existing===null){
            // The only inputs are DB-locked, server-issued evidence; no request/body flags.
            $written=$db->insert($table,[
                'company_id'=>$co,'branch_id'=>$branch,'sale_intent_id'=>$saleId,
                'payment_intent_id'=>$payId,'tender_id'=>$tenderId,
                'quote_digest'=>$digest,'channel'=>$channel,'employee_id'=>$employee,
                'payment_mode'=>$mode,'currency'=>'INR','status'=>'confirmed',
                'verified_by'=>$verifiedBy,'verified_source'=>$source,'amount_paise'=>$amount,
                'provider_transaction_id'=>$reference,'confirmed_at'=>gmdate('Y-m-d H:i:s'),
            ]);
            if($written!==1)throw new RetailerSaleError('Canonical payment promotion failed; rollback entire sale.');
            $existing=$db->get_row($find,defined('ARRAY_A')?ARRAY_A:'ARRAY_A');
            if(($db->last_error??'')!=='')throw new RetailerSaleError('Canonical payment verification read-back failed.');
        }
        if(!is_array($existing)
            ||$n($existing['company_id']??null)!==$co
            ||$n($existing['branch_id']??null)!==$branch
            ||$n($existing['sale_intent_id']??null)!==$saleId
            ||$n($existing['payment_intent_id']??null)!==$payId
            ||$n($existing['tender_id']??null)!==$tenderId
            ||$n($existing['verified_by']??null)!==$verifiedBy
            ||$n($existing['amount_paise']??null)!==$amount
            ||($existing['quote_digest']??null)!==$digest
            ||($existing['channel']??null)!==$channel
            ||($existing['employee_id']===null?null:$n($existing['employee_id']))!==$employee
            ||($existing['payment_mode']??null)!==$mode
            ||($existing['currency']??null)!=='INR'||($existing['status']??null)!=='confirmed'
            ||($existing['verified_source']??null)!==$source
            ||($existing['provider_transaction_id']??null)!==$reference
            ||($existing['consumed_sale_id']??null)!==null) {
            throw new RetailerSaleError('Conflicting canonical tender evidence; no promotion allowed.');
        }
        return $existing;
    }
}
