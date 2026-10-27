<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP8\B2B;

/**
 * Pure fail-closed integrity bridge: persisted intent lines + reserved trusted
 * tender + fresh canonical V7 read-model assessment. NO stock reservation,
 * GL write, payment capture, or real DB row locks occur in this class.
 * The production posting writer must re-run these checks inside its OWN DB
 * transaction with FOR UPDATE locks and approved statutory invoicing policy.
 */
final class CanonicalQuoteSnapshotRevalidation
{
    public function compare(array $sale,array $reservation,array $identity,array $fresh):array
    {
        foreach(['sale_intent_id','company_id','branch_id','retailer_id','canonical_party_id','invoice_total_paise'] as $k){
            if(!is_int($sale[$k]??null)||$sale[$k]<=0)
                throw new RetailerSaleError('Persisted sale intent missing positive '.$k.'.');
        }
        $lines=$sale['saved_lines']??null;
        if(!is_array($lines)||count($lines)<1||count($lines)>200)
            throw new RetailerSaleError('Persisted immutable quote product lines required.');
        $at=$sale['saved_business_at']??null;
        if(!is_string($at)||!preg_match('/^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$/D',$at)
            ||($dt=\DateTimeImmutable::createFromFormat('!Y-m-d H:i:s',$at))===false
            ||$dt->format('Y-m-d H:i:s')!==$at)
            throw new RetailerSaleError('Persisted immutable business datetime required.');
        $channel=$sale['channel']??null;$employee=$sale['employee_id']??null;
        $mode=$sale['payment_mode']??null;
        if(!in_array($channel,['field','counter'],true)||!in_array($mode,['cash','upi'],true)
            ||($channel==='field'&&(!is_int($employee)||$employee<1))
            ||($channel==='counter'&&$employee!==null))
            throw new RetailerSaleError('Invalid persisted stock custody or payment channel.');
        if(($sale['currency']??null)!=='INR'||($sale['pricing_locked']??null)!==true
            ||($sale['status']??null)!=='awaiting_payment')
            throw new RetailerSaleError('Persisted sale must be an immutable unpaid-intent header.');
        if(($identity['identity_validated']??null)!==true||($identity['credit_allowed']??null)!==false
            ||($identity['posting_allowed']??null)!==false
            ||($identity['outstanding_paise']??null)!==0
            ||($identity['retailer_id']??null)!==$sale['retailer_id']
            ||($identity['canonical_party_id']??null)!==$sale['canonical_party_id']
            ||($identity['company_id']??null)!==$sale['company_id']
            ||($identity['branch_id']??null)!==$sale['branch_id'])
            throw new RetailerSaleError('Canonical customer identity no longer matches retailer intent.');
        if(($fresh['assessment']??null)!=='canonical_read_model_validated'
            ||($fresh['posting_allowed']??null)!==false
            ||($fresh['company_id']??null)!==$sale['company_id']
            ||($fresh['branch_id']??null)!==$sale['branch_id']
            ||($fresh['channel']??null)!==$channel
            ||($fresh['employee_id']??null)!==$employee
            ||($fresh['payment_mode']??null)!==$mode
            ||($fresh['business_date']??null)!==substr($at,0,10)
            ||($fresh['total_paise']??null)!==$sale['invoice_total_paise']
            ||($fresh['paid_paise']??null)!==$sale['invoice_total_paise']
            ||($fresh['retailer_outstanding_paise']??null)!==0)
            throw new RetailerSaleError('Current canonical stock, pricing or accounting state differs from quoted sale.');
        $snapshot=['company_id'=>$sale['company_id'],'branch_id'=>$sale['branch_id'],
            'retailer_id'=>$sale['retailer_id'],'canonical_party_id'=>$sale['canonical_party_id'],
            'channel'=>$channel,'employee_id'=>$employee,'business_at'=>$at,
            'payment_mode'=>$mode,'gross_paise'=>$sale['invoice_total_paise'],'lines'=>$lines];
        $digest=hash('sha256',json_encode($snapshot,JSON_THROW_ON_ERROR));
        if(!is_string($sale['quote_digest']??null)||!hash_equals($digest,$sale['quote_digest']))
            throw new RetailerSaleError('Persisted immutable quote digest and product lines mismatch.');
        $current=$fresh['lines']??null;
        if(!is_array($current)||count($current)!==count($lines))
            throw new RetailerSaleError('Current canonical product lines count differs from immutable quote.');
        $sum=0;$seen=[];
        foreach($lines as $i=>$line){
            if(!is_array($line)||!is_array($current[$i]??null))
                throw new RetailerSaleError('Malformed persisted or canonical product line.');
            $now=$current[$i];
            $fields=['product_id'=>'product_id','batch_id'=>'batch_id','quantity_pcs'=>'qty_pcs',
                'commercial_revision_id'=>'commercial_revision_id',
                'unit_price_paise'=>'unit_price_paise','line_total_paise'=>'line_total_paise'];
            foreach($fields as $a=>$b){
                if(!is_int($line[$a]??null)||!is_int($now[$b]??null)||$line[$a]!==$now[$b])
                    throw new RetailerSaleError('Fresh canonical product, batch, price revision or quantity differs from immutable quote: '.$a);
            }
            if($line['product_id']<1||$line['batch_id']<0||$line['quantity_pcs']<1
                ||$line['commercial_revision_id']<1||$line['unit_price_paise']<1
                ||$line['unit_price_paise']>intdiv(PHP_INT_MAX,$line['quantity_pcs'])
                ||$line['line_total_paise']!==$line['unit_price_paise']*$line['quantity_pcs'])
                throw new RetailerSaleError('Malformed immutable price multiplication.');
            $slot=$line['product_id'].':'.$line['batch_id'];
            if(isset($seen[$slot]))throw new RetailerSaleError('Duplicate quote batch.');
            $seen[$slot]=true;
            if($sum>PHP_INT_MAX-$line['line_total_paise'])throw new RetailerSaleError('Quote money overflow.');
            $sum+=$line['line_total_paise'];
        }
        if($sum!==$sale['invoice_total_paise'])throw new RetailerSaleError('Quoted line total does not reconcile.');
        foreach(['company_id','branch_id','retailer_id','canonical_party_id','channel','employee_id',
            'payment_mode','quote_digest'] as $k){
            if(!array_key_exists($k,$reservation)||$reservation[$k]!==$sale[$k])
                throw new RetailerSaleError('Reserved bank/cash tender is for another sale identity or quote.');
        }
        if(($reservation['sale_intent_id']??null)!==$sale['sale_intent_id']
            ||($reservation['status']??null)!=='reserved'
            ||($reservation['amount_paise']??null)!==$sum
            ||!is_int($reservation['payment_intent_id']??null)||$reservation['payment_intent_id']<1
            ||!is_int($reservation['tender_id']??null)||$reservation['tender_id']<1)
            throw new RetailerSaleError('Reserved payment is missing, reused or does not match invoice.');
        $source=$reservation['verified_source']??null;
        $expected=$mode==='upi'?'bank_settlement':($channel==='field'?'employee_cash_custody':'branch_cashier_cash');
        if($source!==$expected||!is_string($reservation['payment_reference']??null)
            ||trim($reservation['payment_reference'])==='')
            throw new RetailerSaleError('Reserved tender lacks approved Cash/UPI confirmation source.');
        return ['status'=>'snapshot_revalidated_uat_only','sale_intent_id'=>$sale['sale_intent_id'],
            'canonical_party_id'=>$sale['canonical_party_id'],'branch_id'=>$sale['branch_id'],
            'invoice_total_paise'=>$sum,'verified_source'=>$expected,
            'posting_allowed'=>false,'stock_reserved'=>false,'needs_atomic_locked_recheck'=>true];
    }
}
