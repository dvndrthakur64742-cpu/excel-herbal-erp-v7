<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP8\B2B;

/**
 * UAT ONLY: issue one immutable sale/payment-intent pair from a SERVER-produced
 * canonical checkout preview. This DOES NOT verify payment, invoice, or post GL.
 * Caller must recompute the preview using CanonicalRetailerCheckoutPreview and
 * supply authenticated company/branch/actor. NEVER accept a browser preview.
 */
interface ImmutableRetailerIntentGateway
{
    public function atomic(callable $operation): array;
    /** Must serialize this company/request key under an InnoDB lock. */
    public function lockRequest(int $companyId, string $requestKey): void;
    public function canIssue(int $companyId,int $branchId,int $actorId,?int $employeeId,string $channel): bool;
    /** Return original immutable pair under transaction lock if issued before. */
    public function existingPair(int $companyId,string $requestKey): ?array;
    /** Save sale, linked payment intent and immutable request receipt atomically. */
    public function createPair(array $snapshot,string $requestKey,?string $merchantOrderId): array;
}

final class ImmutableRetailerIntentIssuer
{
    public function __construct(private ImmutableRetailerIntentGateway $gateway) {}

    public function issue(array $context,array $serverPreview): array
    {
        foreach(['company_id','branch_id','actor_id'] as $field){
            if(!isset($context[$field])||!is_int($context[$field])||$context[$field]<=0)
                throw new RetailerSaleError('Authenticated positive '.$field.' required.');
        }
        $key=$context['request_key']??null;
        if(!is_string($key)||!preg_match('/^[a-f0-9]{32,64}$/D',$key))
            throw new RetailerSaleError('Server-allocated idempotency key required.');
        // Verify the digest, rather than taking any caller-provided digest as authority.
        foreach(['company_id','branch_id','retailer_id','canonical_party_id','actor_id'] as $field){
            if($field==='actor_id')continue;
            if(!is_int($serverPreview[$field]??null)||$serverPreview[$field]<=0)
                throw new RetailerSaleError('Invalid canonical preview identity: '.$field);
        }
        if($context['company_id']!==$serverPreview['company_id']||$context['branch_id']!==$serverPreview['branch_id'])
            throw new RetailerSaleError('Preview company or branch differs from authenticated context.');
        $allowed=['company_id','branch_id','retailer_id','canonical_party_id','channel','employee_id',
            'business_at','payment_mode','gross_paise','lines'];
        $snapshot=[];
        foreach($allowed as $field){
            if(!array_key_exists($field,$serverPreview))throw new RetailerSaleError('Incomplete canonical preview: '.$field);
            $snapshot[$field]=$serverPreview[$field];
        }
        $digest=hash('sha256',json_encode($snapshot,JSON_THROW_ON_ERROR));
        if(!is_string($serverPreview['preview_digest']??null)
            ||!hash_equals($digest,$serverPreview['preview_digest']))
            throw new RetailerSaleError('Preview digest differs from immutable server pricing.');
        if(($serverPreview['posting_allowed']??null)!==false
            ||($serverPreview['stock_reserved']??null)!==false
            ||($serverPreview['credit_allowed']??null)!==false
            ||($serverPreview['retailer_outstanding_paise']??null)!==0
            ||($serverPreview['release_status']??null)!=='preview_only'
            ||($serverPreview['requires_locked_revalidation']??null)!==true
            ||($serverPreview['payment_verification_status']??null)!=='not_verified_by_preview'
            ||($serverPreview['tax_invoice_status']??null)!=='policy_not_approved')
            throw new RetailerSaleError('Only fail-closed, unposted canonical previews can be paired for UAT.');
        if(!in_array($snapshot['channel'],['field','counter'],true)
            ||!in_array($snapshot['payment_mode'],['cash','upi'],true)
            ||($snapshot['channel']==='field'&&(!is_int($snapshot['employee_id'])||$snapshot['employee_id']<=0))
            ||($snapshot['channel']==='counter'&&$snapshot['employee_id']!==null)
            ||!is_int($snapshot['gross_paise'])||$snapshot['gross_paise']<=0)
            throw new RetailerSaleError('Invalid channel, custodian or full-pay tender.');
        if(!is_string($snapshot['business_at'])
            ||!preg_match('/^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$/D',$snapshot['business_at']))
            throw new RetailerSaleError('Business timestamp required.');
        $date=\DateTimeImmutable::createFromFormat('!Y-m-d H:i:s',$snapshot['business_at']);
        if(!$date||$date->format('Y-m-d H:i:s')!==$snapshot['business_at'])
            throw new RetailerSaleError('Invalid business timestamp.');
        $lines=$snapshot['lines'];
        if(!is_array($lines)||count($lines)<1||count($lines)>200)throw new RetailerSaleError('Invalid immutable product lines.');
        $sum=0;$seen=[];
        foreach($lines as $line){
            if(!is_array($line))throw new RetailerSaleError('Invalid immutable product line.');
            foreach(['product_id','batch_id','quantity_pcs','commercial_revision_id','unit_price_paise','line_total_paise'] as $f){
                $min=$f==='batch_id'?0:1;
                if(!is_int($line[$f]??null)||$line[$f]<$min)throw new RetailerSaleError('Invalid immutable line '.$f);
            }
            $slot=$line['product_id'].':'.$line['batch_id'];
            if(isset($seen[$slot]))throw new RetailerSaleError('Duplicate immutable product and batch.');
            $seen[$slot]=true;
            if($line['quantity_pcs']>intdiv(PHP_INT_MAX,$line['unit_price_paise'])
                ||$line['line_total_paise']!==$line['quantity_pcs']*$line['unit_price_paise']
                ||$sum>PHP_INT_MAX-$line['line_total_paise'])throw new RetailerSaleError('Price or quantity overflow.');
            $sum+=$line['line_total_paise'];
        }
        if($sum!==$snapshot['gross_paise'])throw new RetailerSaleError('Canonical quote lines do not equal the full sale amount.');
        $c=$context['company_id'];$b=$context['branch_id'];$a=$context['actor_id'];
        return $this->gateway->atomic(function()use($c,$b,$a,$key,$snapshot,$digest):array{
            $this->gateway->lockRequest($c,$key);
            if(!$this->gateway->canIssue($c,$b,$a,$snapshot['employee_id'],$snapshot['channel']))
                throw new RetailerSaleError('Server-side retailer sale issuing permission denied.');
            $prior=$this->gateway->existingPair($c,$key);
            if($prior!==null){
                $this->assertPair($prior,$snapshot,$digest);
                return $this->publicResult($prior);
            }
            // Random, server-side UAT-only order reference. Real merchant order
            // issuance must come from an approved PSP, not this preview process.
            $order=$snapshot['payment_mode']==='upi'?'EH8-UAT-'.bin2hex(random_bytes(16)):null;
            $saved=$this->gateway->createPair($snapshot,$key,$order);
            $this->assertPair($saved,$snapshot,$digest);
            return $this->publicResult($saved);
        });
    }

    private function assertPair(array $row,array $snapshot,string $digest):void
    {
        foreach(['sale_intent_id','payment_intent_id'] as $f)
            if(!is_int($row[$f]??null)||$row[$f]<=0)throw new RetailerSaleError('Missing immutable intent identifier.');
        $map=['company_id'=>'company_id','branch_id'=>'branch_id','retailer_id'=>'retailer_id',
            'canonical_party_id'=>'canonical_party_id','channel'=>'channel','employee_id'=>'employee_id',
            'payment_mode'=>'payment_mode','invoice_total_paise'=>'gross_paise'];
        foreach($map as $left=>$right)if(!array_key_exists($left,$row)||$row[$left]!==$snapshot[$right])
            throw new RetailerSaleError('Previously issued intent differs from canonical quote.');
        if(($row['saved_business_at']??null)!==$snapshot['business_at']) {
            throw new RetailerSaleError('Persisted immutable business datetime differs from checkout.');
        }
        // Verify line-by-line ACTUAL persisted snapshot, not only a header hash.
        // The trusted gateway must read these rows FOR UPDATE in the same transaction.
        if(!is_array($row['saved_lines']??null)
            ||count($row['saved_lines'])!==count($snapshot['lines'])
            ||$row['saved_lines']!==$snapshot['lines']) {
            throw new RetailerSaleError('Persisted immutable quote lines differ from server priced checkout.');
        }
        if(($row['quote_digest']??null)!==$digest||($row['status']??null)!=='awaiting_payment'
            ||($row['currency']??null)!=='INR'||($row['pricing_locked']??null)!==true)
            throw new RetailerSaleError('Immutable intent is not locked to the original priced quote.');
        $order=$row['merchant_order_id']??null;
        if($snapshot['payment_mode']==='upi'){
            if(!is_string($order)||!preg_match('/^EH8-UAT-[a-f0-9]{32}$/D',$order))
                throw new RetailerSaleError('Missing server-generated UPI merchant order.');
        }elseif($order!==null)throw new RetailerSaleError('Cash intent cannot have UPI merchant order.');
    }
    private function publicResult(array $row):array
    {
        return ['sale_intent_id'=>$row['sale_intent_id'],
            'payment_intent_id'=>$row['payment_intent_id'],
            'canonical_party_id'=>$row['canonical_party_id'],
            'quote_digest'=>$row['quote_digest'],
            'invoice_total_paise'=>$row['invoice_total_paise'],
            'merchant_order_id'=>$row['merchant_order_id'],
            'status'=>'awaiting_payment',
            'payment_verification_status'=>'not_verified',
            'posting_allowed'=>false,'stock_reserved'=>false,'release_status'=>'uat_only'];
    }
}
