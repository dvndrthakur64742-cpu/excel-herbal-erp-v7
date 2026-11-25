<?php
namespace ExcelHerbal\ERP7\Sales;

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Policy\PrepaidOrderRules as Money;

/** Read-only reconciliation of this return's actual linked refund journals.
 * Not the company-wide GL balance. Never issues a tax document or posts money.
 */
final class RefundClearingReconciliation {
    private static function rows(object $db,string $sql):array {
        $rows=$db->get_results($sql,ARRAY_A);
        if(($db->last_error??'')!==''||!is_array($rows))
            throw new DomainException('Refund ledger reconciliation unavailable.','refund_reconciliation_unavailable',503);
        return $rows;
    }
    private static function amount(mixed $v):?int {
        try{return Money::minor($v);}catch(DomainException $e){return null;}
    }
    public static function inspect(array $r,array $payments,array $evidence,array $check):array {
        $db=Db::wpdb();$company=(int)$r['company_id'];$branch=(int)$r['branch_id'];
        $order=(int)$r['order_id'];$sale=(int)$r['sale_id'];$expected=self::amount($r['refund_amount']);
        $blockers=[];$add=static function(string $code)use(&$blockers){$blockers[$code]=true;};
        $o=Db::table('prepaid_sales_orders');$s=Db::table('counter_sales');$j=Db::table('journal_entries');
        $invoiceRows=self::rows($db,$db->prepare("SELECT s.id,s.sale_no,s.sale_date,s.gross_amount AS invoice_amount,s.paid_amount,s.outstanding_amount,
            s.journal_entry_id,o.order_no,o.gross_amount AS order_gross,o.discount_amount,o.net_amount
            FROM {$o} o JOIN {$s} s ON s.id=o.sale_id AND s.company_id=o.company_id AND s.branch_id=o.branch_id
            JOIN {$j} j ON j.id=s.journal_entry_id AND j.company_id=s.company_id AND j.branch_id=s.branch_id
            WHERE o.company_id=%d AND o.branch_id=%d AND o.id=%d AND s.id=%d AND o.status='posted' AND s.status='posted'
            AND j.source_type='counter_sale' AND j.source_id=s.id AND j.status='posted' AND j.reversal_of IS NULL
            AND NOT EXISTS(SELECT 1 FROM {$j} rev WHERE rev.company_id=j.company_id AND rev.reversal_of=j.id)",
            $company,$branch,$order,$sale));
        $invoice=count($invoiceRows)===1?$invoiceRows[0]:null;
        if(!$invoice||$expected===null||$expected<=0||self::amount($invoice['net_amount'])!==$expected||
           self::amount($invoice['invoice_amount'])!==$expected||self::amount($invoice['paid_amount'])!==$expected||
           self::amount($invoice['outstanding_amount'])!==0)$add('original_invoice_invalid');
        $lines=$invoice?self::rows($db,$db->prepare("SELECT product_id,batch_id,quantity,unit_price,line_total,purchase_cost_snapshot
            FROM ".Db::table('counter_sale_lines')." WHERE sale_id=%d ORDER BY id",$sale)):[];
        $lineTotal=0;foreach($lines as $line){$value=self::amount($line['line_total']);if($value===null){$add('invoice_line_amount_invalid');continue;}$lineTotal+=$value;}
        if(!$lines||$lineTotal!==$expected)$add('invoice_line_total_mismatch');
        $accounts=Db::table('accounts');$jl=Db::table('journal_lines');
        $clearingRows=self::rows($db,$db->prepare("SELECT id,type,active FROM {$accounts} WHERE company_id=%d AND code='REFUND_CLEARING'",$company));
        $clearing=count($clearingRows)===1&&$clearingRows[0]['type']==='asset'?(int)$clearingRows[0]['id']:0;
        $configurationReady=$clearing>0&&(int)$clearingRows[0]['active']===1;
        if(!$configurationReady)$add('refund_clearing_account_not_configured');
        // A single original payment must have exactly one independently verified
        // evidence row; use the existing eligibility rules for that tender.
        $proofs=[];foreach($evidence as $ev)$proofs[(int)$ev['order_payment_id']][]=$ev;
        $seen=[];$tenders=[];$posted=0;$cash=0;$upi=0;$ledgerInvalid=false;
        foreach($payments as $p){
            $pid=(int)$p['id'];$amount=self::amount($p['amount']);$method=(string)$p['method'];
            if(isset($seen[$pid])){$add('duplicate_original_payment');$ledgerInvalid=true;continue;}$seen[$pid]=true;
            $item=['original_payment_id'=>$pid,'method'=>$method,'amount'=>$p['amount'],'journal_id'=>null,'status'=>'not_recorded'];
            $evs=$proofs[$pid]??[];
            if(!$evs){$tenders[]=$item;continue;}
            $single=$r;$single['refund_amount']=$p['amount'];
            $eligible=PrepaidRefundEvidencePreflight::check($single,[$p],$evs)['evidence_complete'];
            // Check both source types, including wrong-branch and reversed rows.
            // Never use MAX(id) to mask a duplicate posting.
            $evIds=array_map(static fn($e)=>(int)$e['id'],$evs);
            $ids=implode(',',array_map('intval',$evIds));
            $journals=self::rows($db,$db->prepare("SELECT id,branch_id,source_type,source_id,status,reversal_of,entry_date,
                (SELECT COUNT(*) FROM {$j} rev WHERE rev.company_id=x.company_id AND rev.reversal_of=x.id) AS reversal_count
                FROM {$j} x WHERE company_id=%d AND source_type IN ('external_cash_refund','external_upi_refund') AND source_id IN ({$ids}) ORDER BY id",$company));
            if(!$journals){$tenders[]=$item;continue;}
            $journal=count($journals)===1?$journals[0]:null;
            $valid=$eligible&&$amount!==null&&$amount>0&&$clearing>0&&$journal&&
                (int)$journal['branch_id']===$branch&&$journal['source_type']==='external_'.$method.'_refund'&&
                $journal['status']==='posted'&&$journal['reversal_of']===null&&(int)$journal['reversal_count']===0;
            if($valid){
                $rows=self::rows($db,$db->prepare("SELECT l.id,l.account_id,l.debit,l.credit,a.company_id,a.type,a.subtype
                    FROM {$jl} l LEFT JOIN {$accounts} a ON a.id=l.account_id WHERE l.journal_entry_id=%d ORDER BY l.id",(int)$journal['id']));
                $debit=0;$credit=0;$creditLine=0;$account=(int)$p['payment_account_id'];
                if(count($rows)!==2||$account===$clearing)$valid=false;
                foreach($rows as $line){
                    $d=self::amount($line['debit']);$c=self::amount($line['credit']);
                    if((int)$line['company_id']!==$company||$line['type']!=='asset'||$d===null||$c===null){$valid=false;continue;}
                    if((int)$line['account_id']===$clearing&&$c===0&&$d===$amount)$debit+=$d;
                    elseif((int)$line['account_id']===$account&&strtolower((string)$line['subtype'])===$method&&$d===0&&$c===$amount){$credit+=$c;$creditLine=(int)$line['id'];}
                    else $valid=false;
                }
                $valid=$valid&&$debit===$amount&&$credit===$amount;
                if($valid&&$method==='upi'){
                    $matches=self::rows($db,$db->prepare("SELECT l.debit,l.credit,l.reference,l.txn_date,b.company_id,b.branch_id,b.bank_account_id
                        FROM ".Db::table('bank_statement_lines')." l JOIN ".Db::table('bank_reconciliations')." b ON b.id=l.reconciliation_id
                        WHERE l.matched_journal_line_id=%d AND l.status='matched'",$creditLine));
                    $m=count($matches)===1?$matches[0]:null;
                    $valid=$m&&(int)$m['company_id']===$company&&(int)$m['branch_id']===$branch&&(int)$m['bank_account_id']===$account&&
                        self::amount($m['debit'])===$amount&&self::amount($m['credit'])===0&&
                        $m['reference']===$evs[0]['evidence_reference']&&$m['txn_date']===substr($journal['entry_date'],0,10);
                }
            }
            if(!$valid){$item['status']='review_required';$ledgerInvalid=true;$add('refund_journal_invalid');}
            else{$item['status']='recorded';$item['journal_id']=(int)$journal['id'];$posted+=$amount;if($method==='cash')$cash+=$amount;else $upi+=$amount;}
            $tenders[]=$item;
        }
        foreach($proofs as $pid=>$evs)if(!isset($seen[$pid])){$ledgerInvalid=true;$add('unexpected_refund_evidence');}
        if(!$check['evidence_complete'])$add('refund_evidence_incomplete');
        if($expected===null||$posted>$expected){$ledgerInvalid=true;$add('refund_posted_total_invalid');}
        $validTotals=!$ledgerInvalid&&!isset($blockers['original_invoice_invalid'])&&!isset($blockers['invoice_line_amount_invalid'])&&!isset($blockers['invoice_line_total_mismatch']);
        $state=!$validTotals?'review_required':($posted===0?'not_recorded':($posted===$expected?'refund_recorded':'partially_recorded'));
        // No credit-note source exists yet: a matched payment is not a credit
        // note, tax adjustment, or final settlement of the clearing account.
        return ['invoice'=>$invoice,'invoice_line_count'=>count($lines),'invoice_line_total'=>Money::format($lineTotal),
            'status'=>$state,'expected_amount'=>$expected===null?null:Money::format($expected),
            'recorded_amount'=>$validTotals?Money::format($posted):null,
            'cash_recorded'=>$validTotals?Money::format($cash):null,'upi_recorded'=>$validTotals?Money::format($upi):null,
            'remaining_to_record'=>$validTotals?Money::format($expected-$posted):null,
            'linked_clearing_debit'=>$validTotals?Money::format($posted):null,
            'credit_note_status'=>'not_implemented','credit_note_id'=>null,
            'gst_snapshot_available'=>false,'clearing_account_configured'=>$configurationReady,
            'blockers'=>array_keys($blockers),'tenders'=>$tenders,'read_only'=>true];
    }
}
