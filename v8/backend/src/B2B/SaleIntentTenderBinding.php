<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP8\B2B;

/**
 * UAT-only bridge from a server-priced retailer sale intent to one independently
 * confirmed tender. Merely RESERVES evidence: it does not invoice, move stock,
 * post a journal, settle employee cash or authorize production posting.
 */
interface SaleIntentTenderBindingGateway
{
    public function atomic(callable $work): array;
    public function lockedSaleIntent(int $company, int $branch, int $saleIntentId): ?array;
    public function canBind(int $company, int $branch, int $actor, array $sale): bool;
    public function lockedPaymentIntent(int $company, int $branch, int $paymentIntentId): ?array;
    /** Row JOINed to the actual verified tender, both locked inside the same transaction. */
    public function lockedConfirmedEvidence(int $company, int $branch, int $paymentIntentId): ?array;
    public function existingForSale(int $company, int $saleIntentId): ?array;
    public function existingForTender(int $company, int $tenderId): ?array;
    public function saveReservedBinding(array $record): array;
}

final class SaleIntentTenderBinding
{
    public function __construct(private SaleIntentTenderBindingGateway $gateway) {}

    /** $context MUST be derived from authenticated server identity, never browser role claims. */
    public function reserve(array $context): array
    {
        foreach (['company_id','branch_id','actor_id','sale_intent_id','payment_intent_id'] as $key) {
            if (!isset($context[$key]) || !is_int($context[$key]) || $context[$key] <= 0) {
                throw new RetailerSaleError('Trusted positive ID required: '.$key);
            }
        }
        $company=$context['company_id'];$branch=$context['branch_id'];
        $saleId=$context['sale_intent_id'];$paymentId=$context['payment_intent_id'];$actor=$context['actor_id'];
        return $this->gateway->atomic(function() use($company,$branch,$saleId,$paymentId,$actor):array {
            $sale=$this->gateway->lockedSaleIntent($company,$branch,$saleId);
            if(!is_array($sale) || ($sale['id']??null)!==$saleId
                || ($sale['company_id']??null)!==$company || ($sale['branch_id']??null)!==$branch
                || ($sale['status']??null)!=='awaiting_payment'
                || ($sale['currency']??null)!=='INR'
                || ($sale['pricing_locked']??null)!==true
                || !isset($sale['invoice_total_paise']) || !is_int($sale['invoice_total_paise'])
                || $sale['invoice_total_paise']<=0) {
                throw new RetailerSaleError('Immutable, locked INR retailer sale intent required.');
            }
            foreach(['retailer_id','canonical_party_id'] as $key) {
                if(!isset($sale[$key])||!is_int($sale[$key])||$sale[$key]<=0)
                    throw new RetailerSaleError('Canonical retailer identity required.');
            }
            $digest=$sale['quote_digest']??null;
            if(!is_string($digest)||!preg_match('/^[a-f0-9]{64}$/D',$digest))
                throw new RetailerSaleError('Server-priced immutable quote digest required.');
            $channel=$sale['channel']??null;$employee=$sale['employee_id']??null;
            $mode=$sale['payment_mode']??null;
            if(!in_array($channel,['field','counter'],true)||!in_array($mode,['cash','upi'],true)
                ||($channel==='field'&&(!is_int($employee)||$employee<=0))
                ||($channel==='counter'&&$employee!==null)) {
                throw new RetailerSaleError('Invalid sale channel, custody or payment mode.');
            }
            if(!$this->gateway->canBind($company,$branch,$actor,$sale))
                throw new RetailerSaleError('Authorized sale-tender binder required.');
            $pay=$this->gateway->lockedPaymentIntent($company,$branch,$paymentId);
            if(!is_array($pay)||($pay['id']??null)!==$paymentId
                ||($pay['company_id']??null)!==$company||($pay['branch_id']??null)!==$branch
                ||($pay['sale_intent_id']??null)!==$saleId
                ||($pay['linked_quote_digest']??null)!==$digest
                ||($pay['status']??null)!=='awaiting_payment'||($pay['currency']??null)!=='INR'
                ||($pay['amount_paise']??null)!==$sale['invoice_total_paise']
                ||($pay['channel']??null)!==$channel||($pay['employee_id']??null)!==$employee
                ||($pay['payment_mode']??null)!==$mode) {
                throw new RetailerSaleError('Payment intent is not bound to this exact priced sale.');
            }
            $saleOrder=$sale['merchant_order_id']??null;
            if($mode==='upi'){
                if(!is_string($saleOrder)||$saleOrder===''||!is_string($pay['merchant_order_id']??null)
                    ||!hash_equals($saleOrder,$pay['merchant_order_id']))
                    throw new RetailerSaleError('UPI merchant order differs from immutable sale intent.');
            } elseif($saleOrder!==null||($pay['merchant_order_id']??null)!==null){
                throw new RetailerSaleError('Cash sale must not silently reuse a UPI merchant order.');
            }
            $proof=$this->gateway->lockedConfirmedEvidence($company,$branch,$paymentId);
            if(!is_array($proof)||($proof['intent_id']??null)!==$paymentId
                ||($proof['company_id']??null)!==$company||($proof['branch_id']??null)!==$branch
                ||($proof['amount_paise']??null)!==$sale['invoice_total_paise']
                ||($proof['payment_mode']??null)!==$mode||($proof['channel']??null)!==$channel
                ||($proof['employee_id']??null)!==$employee||($proof['status']??null)!=='confirmed'
                ||($proof['tender_status']??null)!=='confirmed'
                ||($proof['consumed_sale_id']??null)!==null) {
                throw new RetailerSaleError('Confirmed, unconsumed tender evidence for this sale required.');
            }
            $tenderId=$proof['confirmed_tender_id']??null;
            if(!is_int($tenderId)||$tenderId<=0||!is_int($proof['verified_by']??null)||$proof['verified_by']<=0)
                throw new RetailerSaleError('Confirmed tender or authorized verifier missing.');
            $ref=$proof['payment_reference']??null;
            if(!is_string($ref)||!preg_match('/^[A-Za-z0-9][A-Za-z0-9._:\/\-]{7,127}$/D',$ref))
                throw new RetailerSaleError('Trusted payment evidence reference required.');
            $source=$proof['verified_source']??null;
            $expectedSource=$mode==='upi'?'bank_settlement':($channel==='field'?'employee_cash_custody':'branch_cashier_cash');
            if($source!==$expectedSource)throw new RetailerSaleError('Payment proof does not match collection custody and verification source.');
            $record=[
                'company_id'=>$company,'branch_id'=>$branch,'sale_intent_id'=>$saleId,
                'payment_intent_id'=>$paymentId,'tender_id'=>$tenderId,
                'retailer_id'=>$sale['retailer_id'],'canonical_party_id'=>$sale['canonical_party_id'],
                'channel'=>$channel,'employee_id'=>$employee,'payment_mode'=>$mode,
                'payment_reference'=>$ref,'verified_source'=>$source,
                'amount_paise'=>$sale['invoice_total_paise'],'quote_digest'=>$digest,
                'status'=>'reserved',
            ];
            $existing=$this->gateway->existingForSale($company,$saleId);
            $other=$this->gateway->existingForTender($company,$tenderId);
            foreach([$existing,$other] as $prior){
                if($prior!==null){
                    if(($prior['status']??null)!=='reserved')throw new RetailerSaleError('Existing payment reservation cannot be reused.');
                    foreach($record as $key=>$value)if(($prior[$key]??null)!==$value)
                        throw new RetailerSaleError('Tender already reserved for a different sale or immutable quote.');
                }
            }
            if($existing!==null||$other!==null){
                if($existing===null||$other===null||($existing['id']??null)!==($other['id']??null))
                    throw new RetailerSaleError('Inconsistent tender reservation ownership.');
                return $this->result($existing);
            }
            return $this->result($this->gateway->saveReservedBinding($record));
        });
    }
    private function result(array $record):array
    {
        if(!is_int($record['id']??null)||$record['id']<=0||($record['status']??null)!=='reserved')
            throw new RetailerSaleError('Binding persistence did not confirm a safe reservation.');
        return ['binding_id'=>$record['id'],'sale_intent_id'=>$record['sale_intent_id'],
            'payment_intent_id'=>$record['payment_intent_id'],'tender_id'=>$record['tender_id'],
            'canonical_party_id'=>$record['canonical_party_id'],'amount_paise'=>$record['amount_paise'],
            'status'=>'reserved','posting_allowed'=>false];
    }
}
