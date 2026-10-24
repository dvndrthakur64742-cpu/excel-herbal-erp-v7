<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP8\B2B;

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Security\{Actor,Capabilities,Guard};

/**
 * READ ONLY reconciliation of a single canonical retailer sale on disposable
 * v8_test. Not a posting engine, payout approval or statutory tax audit.
 * Reports mismatches WITHOUT silently mutating journals/stock/receipts.
 */
final class V7B2BCrossLedgerAuditUat
{
    public static function inspect(Actor $actor,int $branch,int $saleId):array
    {
        V7CanonicalPostingSinkUat::assertNonProductionEnvironment(Db::wpdb());
        Guard::branch($actor,$branch,Capabilities::ACCOUNTING_VIEW);
        if($saleId<1)throw new RetailerSaleError('Valid canonical sale ID required for UAT audit.');
        $db=Db::wpdb();$company=$actor->companyId;$errors=[];
        $get=static function(string $sql,array $args=[])use($db):?array{
            $q=$db->prepare($sql,...$args);
            if(!is_string($q)||$q==='')throw new RetailerSaleError('UAT audit query preparation failed.');
            $row=$db->get_row($q,ARRAY_A);
            if(!empty($db->last_error))throw new RetailerSaleError('UAT audit source query failed.');
            return is_array($row)?$row:null;
        };
        $all=static function(string $sql,array $args=[])use($db):array{
            $q=$db->prepare($sql,...$args);
            if(!is_string($q)||$q==='')throw new RetailerSaleError('UAT audit row-query preparation failed.');
            $rows=$db->get_results($q,ARRAY_A);
            if(!is_array($rows)||!empty($db->last_error))
                throw new RetailerSaleError('UAT audit rows could not be verified.');
            if(count($rows)>201)throw new RetailerSaleError('UAT audit source exceeds complete result window.');
            return $rows;
        };
        $fail=static function(string $code)use(&$errors):void{
            if(!in_array($code,$errors,true))$errors[]=$code;
        };
        $int=static function(mixed $raw):?int{
            if(!is_int($raw)&&!is_string($raw))return null;
            $s=(string)$raw;
            return preg_match('/^(0|[1-9][0-9]{0,16})$/D',$s)?(int)$s:null;
        };
        $money=static function(mixed $raw):?int {
            try{return Paise::parse($raw);}
            catch(\Throwable){return null;}
        };
        $quantity=static function(mixed $raw):?int{
            if(!is_string($raw)&&!is_int($raw))return null;
            if(!preg_match('/^(0|[1-9][0-9]{0,11})(?:\.([0-9]{1,3}))?$/D',(string)$raw,$m))
                return null;
            return (int)$m[1]*1000+(int)str_pad($m[2]??'',3,'0');
        };
        $sale=$get('SELECT * FROM '.Db::table('b2b_retailer_sales').
            ' WHERE company_id=%d AND branch_id=%d AND id=%d',[$company,$branch,$saleId]);
        if(!$sale)throw new RetailerSaleError('Canonical sale outside company/branch authority or missing.');
        $invoice=$int($sale['invoice_total_paise']??null);
        $cogs=$int($sale['cogs_paise']??null);
        $employee=$sale['employee_id']===null?null:$int($sale['employee_id']);
        $isField=($sale['channel']??null)==='field';
        $isCash=($sale['payment_mode']??null)==='cash';
        if(($sale['status']??null)!=='posted'||$invoice===null||$invoice<1
            ||$cogs===null||$employee===0||($isField&&$employee===null)
            ||(!$isField&&$employee!==null)
            ||!in_array($sale['channel']??null,['field','counter'],true)
            ||!in_array($sale['payment_mode']??null,['cash','upi'],true)
            ||$int($sale['outstanding_paise']??null)!==0
            ||$int($sale['journal_entry_id']??null)===null
            ||$int($sale['journal_entry_id']??null)<1)
            $fail('invalid_posted_sale_header');

        $lines=$all('SELECT * FROM '.Db::table('b2b_retailer_sale_lines').
            ' WHERE sale_id=%d ORDER BY line_no LIMIT 201',[$saleId]);
        $stock=$all('SELECT * FROM '.Db::table('stock_ledger').
            " WHERE company_id=%d AND branch_id=%d AND source_type='b2b_retailer_sale' AND source_id=%d ORDER BY id LIMIT 201",
            [$company,$branch,$saleId]);
        if(!$lines||count($lines)>200||count($stock)!==count($lines))$fail('stock_sale_line_count_mismatch');
        $lineSum=0;$costSum=0;$lineMap=[];
        foreach($lines as $index=>$l){
            $qty=$int($l['quantity_pcs']??null);$unit=$int($l['unit_price_paise']??null);
            $amount=$int($l['line_total_paise']??null);$cost=$int($l['cogs_paise']??null);
            $product=$int($l['product_id']??null);$batch=$l['batch_id']===null?0:$int($l['batch_id']);
            $key=$product.':'.$batch;
            if($qty===null||$qty<1||$unit===null||$unit<1||$amount===null
               ||$cost===null||$product===null||$product<1||$batch===null
               ||$index+1!==$int($l['line_no']??null)||isset($lineMap[$key])
               ||$qty>intdiv(PHP_INT_MAX,$unit)||$amount!==$qty*$unit)
               $fail('invalid_or_duplicate_sale_line');
            if($amount!==null&&$cost!==null){
                if($amount>PHP_INT_MAX-$lineSum||$cost>PHP_INT_MAX-$costSum)
                    $fail('sale_line_amount_overflow');
                else{$lineSum+=$amount;$costSum+=$cost;}
            }
            $lineMap[$key]=['qty'=>$qty,'cost'=>$cost,'seen'=>false];
        }
        if($invoice!==$lineSum||$cogs!==$costSum)
            $fail('invoice_or_cogs_line_total_mismatch');
        foreach($stock as $row){
            $product=$int($row['product_id']??null);$batch=$row['batch_id']===null?0:$int($row['batch_id']);
            $key=$product.':'.$batch;$expected=$lineMap[$key]??null;
            $custodian=$row['custodian_employee_id']===null?null:$int($row['custodian_employee_id']);
            $qty=$quantity($row['quantity']??null);
            if(!$expected||$expected['seen']||($row['direction']??null)!=='OUT'
               ||$qty===null||$qty!==($expected['qty']??null)*1000
               ||$custodian!==$employee
               ||$int($row['company_id']??null)!==$company
               ||$int($row['branch_id']??null)!==$branch)
                $fail('canonical_stock_ledger_mismatch');
            else $lineMap[$key]['seen']=true;
        }
        foreach($lineMap as $record)
            if(!$record['seen'])$fail('missing_canonical_stock_out');

        $issuedSale=$get('SELECT * FROM v8_b2b_sale_intents_uat WHERE company_id=%d AND branch_id=%d AND id=%d',
            [$company,$branch,(int)$sale['sale_intent_id']]);
        if(!$issuedSale||($issuedSale['status']??null)!=='posted'
            ||($issuedSale['quote_digest']??null)!==($sale['quote_digest']??null)
            ||$int($issuedSale['invoice_total_paise']??null)!==$invoice
            ||$int($issuedSale['canonical_party_id']??null)!==$int($sale['customer_id']??null)
            ||($issuedSale['payment_mode']??null)!==($sale['payment_mode']??null))
            $fail('immutable_sale_intent_finalization_mismatch');
        $tenders=$all('SELECT * FROM '.Db::table('b2b_verified_tenders').
            ' WHERE company_id=%d AND branch_id=%d AND sale_intent_id=%d LIMIT 201',
            [$company,$branch,(int)$sale['sale_intent_id']]);
        $tender=count($tenders)===1?$tenders[0]:null;
        $source=$isCash?($isField?'employee_cash_custody':'branch_cashier_cash'):'bank_settlement';
        if(!$tender||$int($tender['consumed_sale_id']??null)!==$saleId
           ||$int($tender['amount_paise']??null)!==$invoice
           ||($tender['status']??null)!=='confirmed'
           ||($tender['verified_source']??null)!==$source
           ||($tender['payment_mode']??null)!==($sale['payment_mode']??null)
           ||($tender['channel']??null)!==($sale['channel']??null)
           ||($tender['quote_digest']??null)!==($sale['quote_digest']??null)
           ||$int($tender['verified_by']??null)<1)
            $fail('canonical_verified_tender_mismatch');
        if($tender){
            $original=$get('SELECT * FROM v8_b2b_verified_tenders WHERE id=%d AND company_id=%d AND branch_id=%d',
                [(int)$tender['tender_id'],$company,$branch]);
            if(!$original||$int($original['consumed_sale_id']??null)!==$saleId
               ||($original['verified_source']??null)!==$source
               ||$int($original['amount_paise']??null)!==$invoice
               ||($original['payment_reference']??null)==='')
                $fail('uat_tender_consumption_mismatch');
            $reservation=$get('SELECT * FROM v8_b2b_sale_tender_reservations_uat'.
                ' WHERE company_id=%d AND branch_id=%d AND sale_intent_id=%d',
                [$company,$branch,(int)$sale['sale_intent_id']]);
            if(!$reservation||($reservation['status']??null)!=='consumed'
               ||$int($reservation['tender_id']??null)!==$int($tender['tender_id']??null)
               ||$int($reservation['amount_paise']??null)!==$invoice
               ||($reservation['payment_reference']??null)!==($original['payment_reference']??null))
                $fail('uat_reservation_finalization_mismatch');
            if($reservation){
                $payment=$get('SELECT * FROM v8_b2b_payment_intents_uat WHERE company_id=%d AND branch_id=%d AND id=%d',
                    [$company,$branch,(int)$reservation['payment_intent_id']]);
                $evidence=$get('SELECT * FROM v8_b2b_tender_intake_evidence_uat WHERE company_id=%d AND branch_id=%d AND intent_id=%d',
                    [$company,$branch,(int)$reservation['payment_intent_id']]);
                if(!$payment||($payment['status']??null)!=='consumed'
                    ||$int($payment['amount_paise']??null)!==$invoice
                    ||($payment['payment_mode']??null)!==($sale['payment_mode']??null)
                    ||!$evidence
                    ||$int($evidence['confirmed_tender_id']??null)!==$int($tender['tender_id']??null)
                    ||$int($evidence['amount_paise']??null)!==$invoice
                    ||($evidence['verified_source']??null)!==$source
                    ||($evidence['payment_reference']??null)!==($reservation['payment_reference']??null)
                    ||$int($evidence['verified_by']??null)<1)
                    $fail('trusted_payment_intent_evidence_mismatch');
            }
        }

        $journal=$get('SELECT * FROM '.Db::table('journal_entries').
            ' WHERE id=%d AND company_id=%d AND branch_id=%d',
            [(int)($sale['journal_entry_id']??0),$company,$branch]);
        if(!$journal||($journal['status']??null)!=='posted'
           ||($journal['source_type']??null)!=='b2b_retailer_sale'
           ||$int($journal['source_id']??null)!==$saleId)
            $fail('canonical_sale_journal_header_mismatch');
        $gl=$all('SELECT a.code,jl.debit,jl.credit,jl.party_type,jl.party_id FROM '.
            Db::table('journal_lines').' jl LEFT JOIN '.Db::table('accounts').
            ' a ON a.id=jl.account_id AND a.company_id=%d WHERE jl.journal_entry_id=%d ORDER BY jl.id LIMIT 201',
            [$company,(int)($sale['journal_entry_id']??0)]);
        $paymentCode=$isCash?($isField?'EMPLOYEE_CASH_IN_TRANSIT':'BRANCH_CASH'):'UPI_CLEARING';
        $expectedGl=[
            $paymentCode=>[$invoice,0], 'SALES'=>[0,$invoice],
            'COGS'=>[$cogs,0], 'INVENTORY'=>[0,$cogs],
        ];
        $glSeen=[];$dr=0;$cr=0;
        if(count($gl)!==4)$fail('canonical_sale_journal_line_count_mismatch');
        foreach($gl as $g){
            $code=(string)($g['code']??'');
            $debit=$money($g['debit']??null);$credit=$money($g['credit']??null);
            if(!isset($expectedGl[$code])||isset($glSeen[$code])||$debit===null||$credit===null
               ||$debit!==$expectedGl[$code][0]||$credit!==$expectedGl[$code][1])
                $fail('canonical_sale_journal_balance_or_mapping_mismatch');
            if($code===$paymentCode&&$isField&&$isCash
               &&(($g['party_type']??null)!=='employee'
                   ||$int($g['party_id']??null)!==$employee))
                $fail('employee_cash_journal_party_mismatch');
            $glSeen[$code]=true;$dr+=$debit??0;$cr+=$credit??0;
        }
        if(count($glSeen)!==4||$dr!==$cr)$fail('canonical_sale_journal_balance_or_mapping_mismatch');

        $remits=$all('SELECT * FROM '.Db::table('b2b_cash_remittances').
            ' WHERE company_id=%d AND branch_id=%d AND sale_id=%d LIMIT 201',
            [$company,$branch,$saleId]);
        $custody=($isField&&$isCash)?'pending_cashier_handover':'not_employee_cash_custody';
        if(!$isField||!$isCash){
            if($remits)$fail('unexpected_cash_handover_for_non_field_cash');
        }elseif(count($remits)>1)$fail('duplicate_cash_handover_source');
        elseif(count($remits)===1){
            $r=$remits[0];$custody='cashier_handover_unverified';
            $receipt=$get('SELECT * FROM '.Db::table('b2b_cashier_receipts_uat').
                ' WHERE company_id=%d AND branch_id=%d AND id=%d',
                [$company,$branch,(int)$r['receipt_id']]);
            if(($r['status']??null)!=='posted'
                ||$int($r['employee_id']??null)!==$employee
                ||$int($r['amount_paise']??null)!==$invoice
                ||!$receipt||($receipt['status']??null)!=='confirmed'
                ||$int($receipt['sale_id']??null)!==$saleId
                ||$int($receipt['employee_id']??null)!==$employee
                ||$int($receipt['amount_paise']??null)!==$invoice
                ||$int($receipt['consumed_remittance_id']??null)!==$int($r['id']??null)
                ||$int($receipt['cashier_employee_id']??null)===null
                ||$int($receipt['cashier_employee_id']??null)===$employee
                ||($int($receipt['cashier_user_id']??null)??0)<1
                ||$int($r['cashier_employee_id']??null)!==$int($receipt['cashier_employee_id']??null)
                ||($int($r['checker_user_id']??null)??0)<1
                ||($int($r['checker_employee_id']??null)??0)<1
                ||$int($r['checker_user_id']??null)===$int($receipt['cashier_user_id']??null)
                ||$int($r['checker_employee_id']??null)===$int($receipt['cashier_employee_id']??null)
                ||$int($r['checker_employee_id']??null)===$employee)
                $fail('cashier_receipt_or_remittance_mismatch');
            $cashGlHeader=$get('SELECT * FROM '.Db::table('journal_entries').
                ' WHERE id=%d AND company_id=%d AND branch_id=%d',
                [(int)($r['journal_entry_id']??0),$company,$branch]);
            if(!$cashGlHeader||($cashGlHeader['status']??null)!=='posted'
                ||($cashGlHeader['source_type']??null)!=='b2b_cash_remittance'
                ||$int($cashGlHeader['source_id']??null)!==$int($r['id']??null))
                $fail('canonical_handover_journal_header_mismatch');
            $cashLines=$all('SELECT a.code,jl.debit,jl.credit,jl.party_type,jl.party_id FROM '.
                Db::table('journal_lines').' jl LEFT JOIN '.Db::table('accounts').
                ' a ON a.id=jl.account_id AND a.company_id=%d WHERE jl.journal_entry_id=%d ORDER BY jl.id LIMIT 201',
                [$company,(int)($r['journal_entry_id']??0)]);
            if(count($cashLines)!==2)$fail('canonical_handover_journal_line_count_mismatch');
            $cashSeen=[];
            foreach($cashLines as $g){
                $code=(string)($g['code']??'');
                if(isset($cashSeen[$code])||!in_array($code,['BRANCH_CASH','EMPLOYEE_CASH_IN_TRANSIT'],true)
                   ||$money($g['debit']??null)!==($code==='BRANCH_CASH'?$invoice:0)
                   ||$money($g['credit']??null)!==($code==='EMPLOYEE_CASH_IN_TRANSIT'?$invoice:0)
                   ||($code==='EMPLOYEE_CASH_IN_TRANSIT'&&
                      (($g['party_type']??null)!=='employee'||$int($g['party_id']??null)!==$employee)))
                    $fail('canonical_handover_gl_mismatch');
                $cashSeen[$code]=true;
            }
            if(count($cashSeen)!==2)$fail('canonical_handover_gl_mismatch');
            if(!$errors)$custody='cashier_handover_reconciled_uat';
        }
        $result=empty($errors);
        return [
            'read_only'=>true,'scope'=>'disposable_v8_test_canonical_v7_only',
            'company_id'=>$company,'branch_id'=>$branch,'sale_id'=>$saleId,
            'retailer_outstanding_paise'=>$int($sale['outstanding_paise']??null),
            'invoice_total_paise'=>$invoice,'cash_custody_state'=>$custody,
            'cross_ledger_consistent'=>$result,'mismatch_codes'=>$errors,
            'physical_cash_verified_in_live_erp'=>false,
            'bank_provider_verified_in_live_erp'=>false,
            'statutory_invoice_reversal_approved'=>false,
            'production_posting_allowed'=>false,
        ];
    }
}
