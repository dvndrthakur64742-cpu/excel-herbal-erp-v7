<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP8\B2B;

use ExcelHerbal\ERP7\Security\{Actor,Capabilities,Guard};

/**
 * Development v8_test ONLY. Binds immutable UAT sale/payment/tender rows to
 * one canonical V7 locked, freshly-priced assessment on the SAME wpdb connection.
 * Called ONLY from within V7CanonicalPostingSinkUat::post's transaction.
 * This is not a payment provider and cannot be registered as a REST endpoint.
 */
final class V7UatLockedCheckoutReader
{
    public function __invoke(Actor $actor,array $context,object $db):array
    {
        V7CanonicalPostingSinkUat::assertNonProductionEnvironment($db);
        if(!isset($context['actor_id'],$context['company_id'],$context['branch_id'],$context['retailer_id'],$context['sale_intent_id'])
            ||$context['actor_id']!==$actor->userId||$context['company_id']!==$actor->companyId)
            throw new RetailerSaleError('UAT locked context must match WordPress actor and company.');
        $company=$context['company_id'];$branch=$context['branch_id'];$id=$context['sale_intent_id'];
        Guard::branch($actor,$branch,Capabilities::SALES_CREATE);
        $sale=$this->row($db,'SELECT * FROM v8_b2b_sale_intents_uat WHERE company_id=%d AND branch_id=%d AND id=%d FOR UPDATE',[$company,$branch,$id]);
        if(!$sale||!$this->eq($sale,'retailer_id',$context['retailer_id'])
            ||($sale['status']??null)!=='awaiting_payment'||(int)($sale['pricing_locked']??0)!==1
            ||($sale['currency']??null)!=='INR'||!in_array($sale['channel']??null,['field','counter'],true)
            ||!in_array($sale['payment_mode']??null,['cash','upi'],true))
            throw new RetailerSaleError('Stored retailer quote missing, unpriced or immutable identity mismatch.');
        $channel=$sale['channel'];$mode=$sale['payment_mode'];$employee=$this->nullableId($sale['employee_id']??null);
        if(($channel==='field'&&$employee===null)||($channel==='counter'&&$employee!==null))
            throw new RetailerSaleError('Immutable quote channel and employee custody differ.');
        $contextRow=$this->row($db,'SELECT * FROM v8_b2b_issued_sale_context_uat WHERE company_id=%d AND branch_id=%d AND sale_intent_id=%d FOR UPDATE',[$company,$branch,$id]);
        if(!$contextRow||!hash_equals((string)$sale['quote_digest'],(string)$contextRow['quote_digest']))
            throw new RetailerSaleError('Immutable business time does not match the issued quote.');
        $businessAt=$contextRow['business_at']??null;
        if(!is_string($businessAt)||!preg_match('/^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$/D',$businessAt)
            ||($date=\DateTimeImmutable::createFromFormat('!Y-m-d H:i:s',$businessAt))===false
            ||$date->format('Y-m-d H:i:s')!==$businessAt)
            throw new RetailerSaleError('Invalid immutable business timestamp.');
        $raw=$this->rows($db,'SELECT * FROM v8_b2b_sale_intent_lines_uat WHERE company_id=%d AND branch_id=%d AND sale_intent_id=%d ORDER BY line_no FOR UPDATE',[$company,$branch,$id]);
        if(!$raw||count($raw)>200)throw new RetailerSaleError('Missing immutable priced product lines.');
        $lines=[];$requestLines=[];$seq=1;$total=0;
        foreach($raw as $r){
            if((int)$r['line_no']!==$seq++)throw new RetailerSaleError('Unordered or missing immutable quote line.');
            $line=[];
            foreach(['product_id','batch_id','quantity_pcs','commercial_revision_id','unit_price_paise','line_total_paise'] as $field){
                $line[$field]=$this->positiveInt($r[$field]??null,$field==='batch_id');
            }
            if($line['unit_price_paise']>intdiv(PHP_INT_MAX,$line['quantity_pcs'])
                ||$line['line_total_paise']!==$line['unit_price_paise']*$line['quantity_pcs']
                ||$total>PHP_INT_MAX-$line['line_total_paise'])
                throw new RetailerSaleError('Stored quote arithmetic mismatch.');
            $total+=$line['line_total_paise'];$lines[]=$line;
            $requestLines[]=['product_id'=>$line['product_id'],'batch_id'=>$line['batch_id'],'qty'=>$line['quantity_pcs']];
        }
        $invoice=$this->positiveInt($sale['invoice_total_paise']??null);
        if($total!==$invoice)throw new RetailerSaleError('Issued product total differs from sale intent.');
        $snapshot=['company_id'=>$company,'branch_id'=>$branch,'retailer_id'=>(int)$sale['retailer_id'],
            'canonical_party_id'=>$this->positiveInt($sale['canonical_party_id']),'channel'=>$channel,
            'employee_id'=>$employee,'business_at'=>$businessAt,'payment_mode'=>$mode,
            'gross_paise'=>$invoice,'lines'=>$lines];
        $digest=hash('sha256',json_encode($snapshot,JSON_THROW_ON_ERROR));
        if(!hash_equals($digest,(string)$sale['quote_digest']))throw new RetailerSaleError('Persisted quote digest tampered.');
        // Reserve, issued-payment intent, independent attestation and confirmed
        // tender must all be row-locked before a canonical proof can be trusted.
        $reservation=$this->row($db,'SELECT * FROM v8_b2b_sale_tender_reservations_uat WHERE company_id=%d AND branch_id=%d AND sale_intent_id=%d FOR UPDATE',[$company,$branch,$id]);
        if(!$reservation||($reservation['status']??null)!=='reserved'
            ||!$this->eq($reservation,'retailer_id',(int)$sale['retailer_id'])
            ||!$this->eq($reservation,'canonical_party_id',(int)$sale['canonical_party_id'])
            ||!$this->eq($reservation,'amount_paise',$invoice)
            ||($reservation['quote_digest']??null)!==$digest
            ||($reservation['payment_mode']??null)!==$mode
            ||($reservation['channel']??null)!==$channel
            ||$this->nullableId($reservation['employee_id']??null)!==$employee)
            throw new RetailerSaleError('Payment reservation not bound to immutable sale.');
        $payId=$this->positiveInt($reservation['payment_intent_id']);$tenderId=$this->positiveInt($reservation['tender_id']);
        $link=$this->row($db,'SELECT * FROM v8_b2b_payment_intent_to_sale_uat WHERE company_id=%d AND branch_id=%d AND payment_intent_id=%d FOR UPDATE',[$company,$branch,$payId]);
        $payment=$this->row($db,'SELECT * FROM v8_b2b_payment_intents_uat WHERE company_id=%d AND branch_id=%d AND id=%d FOR UPDATE',[$company,$branch,$payId]);
        if(!$link||!$payment||!$this->eq($link,'sale_intent_id',$id)
            ||($link['quote_digest']??null)!==$digest||($payment['status']??null)!=='awaiting_payment'||$payment['currency']!=='INR'
            ||($payment['payment_mode']??null)!==$mode||($payment['channel']??null)!==$channel
            ||!$this->eq($payment,'amount_paise',$invoice)
            ||$this->nullableId($payment['employee_id']??null)!==$employee
            ||($sale['merchant_order_id']??null)!==($payment['merchant_order_id']??null))
            throw new RetailerSaleError('Issued payment intent does not match reserved sale.');
        $e=$this->row($db,'SELECT * FROM v8_b2b_tender_intake_evidence_uat WHERE company_id=%d AND branch_id=%d AND intent_id=%d FOR UPDATE',[$company,$branch,$payId]);
        $t=$this->row($db,'SELECT * FROM v8_b2b_verified_tenders WHERE company_id=%d AND branch_id=%d AND id=%d FOR UPDATE',[$company,$branch,$tenderId]);
        $proofSource=$mode==='upi'?'bank_settlement':($channel==='field'?'employee_cash_custody':'branch_cashier_cash');
        if(!$e||!$t||!$this->eq($e,'confirmed_tender_id',$tenderId)
            ||$this->positiveInt($e['verified_by']??null)<1
            ||!$this->eq($e,'amount_paise',$invoice)||!$this->eq($t,'amount_paise',$invoice)
            ||($e['payment_mode']??null)!==$mode||($t['payment_mode']??null)!==$mode
            ||($e['verified_source']??null)!==$proofSource||($t['verified_source']??null)!==$proofSource
            ||($e['payment_reference']??null)!==($t['payment_reference']??null)
            ||($reservation['payment_reference']??null)!==($e['payment_reference']??null)
            ||($e['channel']??null)!==$channel
            ||$this->nullableId($e['employee_id']??null)!==$employee
            ||($t['status']??null)!=='confirmed'||($t['consumed_sale_id']??null)!==null)
            throw new RetailerSaleError('Verified tender evidence cannot authorize canonical sale.');
        $canonical=$this->row($db,'SELECT * FROM '.$this->prefix($db).'eh7_b2b_verified_tenders WHERE company_id=%d AND branch_id=%d AND sale_intent_id=%d FOR UPDATE',[$company,$branch,$id]);
        if(!$canonical||!$this->eq($canonical,'id',$this->positiveInt($canonical['id']??null))
            ||!$this->eq($canonical,'payment_intent_id',$payId)||!$this->eq($canonical,'tender_id',$tenderId)
            ||($canonical['quote_digest']??null)!==$digest||($canonical['payment_mode']??null)!==$mode
            ||($canonical['verified_source']??null)!==$proofSource
            ||!$this->eq($canonical,'amount_paise',$invoice)
            ||($canonical['provider_transaction_id']??null)!==($e['payment_reference']??null)
            ||($canonical['currency']??null)!=='INR'||($canonical['status']??null)!=='confirmed'
            ||($canonical['channel']??null)!==$channel
            ||$this->nullableId($canonical['employee_id']??null)!==$employee
            ||$canonical['consumed_sale_id']!==null
            ||!$this->eq($canonical,'verified_by',$this->positiveInt($e['verified_by']??null)))
            throw new RetailerSaleError('Canonical same-database tender proof differs from attested payment.');
        // Fresh live V7 price, stock, batch, accounts; ALL reads FOR UPDATE.
        $canonicalSource=new V7UatRowLockReader($db,$actor,$branch);
        $assessment=(new CanonicalV7Readiness($canonicalSource))->assess([
            'company_id'=>$company,'branch_id'=>$branch,'actor_id'=>$actor->userId,
            'channel'=>$channel,'employee_id'=>$employee,'business_at'=>$businessAt,
            'payment_mode'=>$mode,'paid_amount'=>Paise::format($invoice),'lines'=>$requestLines,
        ]);
        if(($assessment['posting_allowed']??null)!==false
            ||($assessment['total_paise']??null)!==$invoice
            ||count($assessment['lines']??[])!==count($lines))
            throw new RetailerSaleError('Fresh canonical V7 pricing and stock mismatch.');
        foreach($lines as $i=>$stored) {
            $fresh=$assessment['lines'][$i];
            foreach(['product_id'=>'product_id','batch_id'=>'batch_id',
                'quantity_pcs'=>'qty_pcs','commercial_revision_id'=>'commercial_revision_id',
                'unit_price_paise'=>'unit_price_paise','line_total_paise'=>'line_total_paise'] as $key=>$live) {
                if(($fresh[$live]??null)!==$stored[$key])
                    throw new RetailerSaleError('Fresh V7 product, batch or price revision differs from immutable quote.');
            }
        }
        // The caller never sets this flag. This *internal* callback runs only
        // inside a guarded v8_test writer transaction with all source rows locked.
        $assessment['posting_allowed']=true;
        return ['assessment'=>$assessment,
            'quote'=>['sale_intent_id'=>$id,'company_id'=>$company,'branch_id'=>$branch,
                'retailer_id'=>(int)$sale['retailer_id'],'canonical_party_id'=>(int)$sale['canonical_party_id'],'payment_intent_id'=>$payId,
                'invoice_total_paise'=>$invoice,'quote_digest'=>$digest,'currency'=>'INR',
                'pricing_locked'=>true,'status'=>'awaiting_payment','payment_mode'=>$mode,
                'channel'=>$channel,'employee_id'=>$employee,'saved_business_at'=>$businessAt,
                'saved_lines'=>$lines],
            'tender'=>['id'=>(int)$canonical['id'],'uat_tender_id'=>$tenderId,'company_id'=>$company,'branch_id'=>$branch,
                'sale_intent_id'=>$id,'quote_digest'=>$digest,'verified_source'=>$proofSource,
                'payment_mode'=>$mode,'amount_paise'=>$invoice,'currency'=>'INR',
                'status'=>'confirmed','consumed_sale_id'=>null],
        ];
    }
    private function prefix(object $db):string
    { $p=$db->prefix??null;if(!is_string($p)||!preg_match('/^[A-Za-z0-9_]{1,60}$/D',$p))throw new RetailerSaleError('Unsafe database prefix.');return $p; }
    private function row(object $db,string $query,array $args):?array
    { $sql=$db->prepare($query,...$args);if(!is_string($sql))throw new RetailerSaleError('UAT row lock preparation failed.');$r=$db->get_row($sql,defined('ARRAY_A')?ARRAY_A:'ARRAY_A');if(($db->last_error??'')!==''||($r!==null&&!is_array($r)))throw new RetailerSaleError('UAT locked row query failed.');return $r; }
    private function rows(object $db,string $query,array $args):array
    { $sql=$db->prepare($query,...$args);if(!is_string($sql))throw new RetailerSaleError('UAT row lock preparation failed.');$r=$db->get_results($sql,defined('ARRAY_A')?ARRAY_A:'ARRAY_A');if(($db->last_error??'')!==''||!is_array($r))throw new RetailerSaleError('UAT locked line query failed.');return $r; }
    private function eq(array $row,string $key,int $value):bool
    { return isset($row[$key])&&ctype_digit((string)$row[$key])&&(int)$row[$key]===$value; }
    private function positiveInt(mixed $raw,bool $zero=false):int
    { if((!is_string($raw)&&!is_int($raw))||!ctype_digit((string)$raw)||strlen((string)$raw)>18||($v=(int)$raw)<($zero?0:1))throw new RetailerSaleError('Invalid locked DB integer.');return $v; }
    private function nullableId(mixed $raw):?int {return $raw===null?null:$this->positiveInt($raw);}
}

/** Canonical WPDB reader with transaction-held row locks, never a preview cache. */
final class V7UatRowLockReader implements V7CanonicalReader
{
    private string $prefix;
    public function __construct(private object $db,private Actor $actor,private int $targetBranch)
    { $p=$db->prefix??null;if(!is_string($p)||!preg_match('/^[A-Za-z0-9_]{1,60}$/D',$p))throw new RetailerSaleError('Unsafe WordPress prefix.');$this->prefix=$p.'eh7_'; }
    public function canInspect(int $actorId,int $companyId,int $branchId,string $channel,?int $employeeId):bool
    { if($this->actor->userId!==$actorId||$this->actor->companyId!==$companyId||!$this->actor->hasBranch($branchId)||!$this->actor->can(Capabilities::SALES_CREATE))return false;
      if($channel==='field')return $employeeId!==null && $this->actor->employeeId===$employeeId && $this->actor->assignedBranchId===$branchId;
      return $channel==='counter'&&$employeeId===null; }
    private function read(string $table,string $where,array $args,string $order=''):?array
    { $sql='SELECT * FROM '.$this->prefix.$table.' WHERE '.$where.($order!==''?' ORDER BY '.$order:'').' LIMIT 1 FOR UPDATE';
      $statement=$this->db->prepare($sql,...$args);if(!is_string($statement))throw new RetailerSaleError('V7 row lock preparation failed.');
      $row=$this->db->get_row($statement,defined('ARRAY_A')?ARRAY_A:'ARRAY_A');if(($this->db->last_error??'')!==''||($row!==null&&!is_array($row)))throw new RetailerSaleError('V7 canonical row lock failed.');return $row; }
    public function branch(int $c,int $b):?array {return $this->read('branches','company_id=%d AND id=%d',[$c,$b]);}
    public function employee(int $c,int $id):?array { $r=$this->read('employees','company_id=%d AND id=%d AND assigned_branch_id=%d',[$c,$id,$this->targetBranch]);return $r!==null&&(int)($r['assigned_branch_id']??0)===$this->targetBranch?$r:null; }
    public function closedAccountingPeriod(int $c,string $day):bool {return $this->read('accounting_periods',"company_id=%d AND status='closed' AND %s BETWEEN period_start AND period_end",[$c,$day])!==null;}
    public function closedBranchDay(int $c,int $b,string $day):bool {return $this->read('branch_closings',"company_id=%d AND branch_id=%d AND business_date=%s AND status='closed'",[$c,$b,$day])!==null;}
    public function product(int $c,int $id):?array {return $this->read('products','company_id=%d AND id=%d',[$c,$id]);}
    public function commercial(int $c,int $id,string $at):?array {return $this->read('product_commercial_revisions',"company_id=%d AND product_id=%d AND status='active' AND effective_from<=%s",[$c,$id,$at],'effective_from DESC,id DESC');}
    public function batch(int $c,int $p,int $id):?array {return $this->read('batches','company_id=%d AND product_id=%d AND id=%d',[$c,$p,$id]);}
    public function stockBucket(int $c,int $b,int $p,int $batch,int $custodian):?array {return $this->read('stock_balances','company_id=%d AND branch_id=%d AND product_id=%d AND batch_key=%d AND custodian_key=%d',[$c,$b,$p,$batch,$custodian]);}
    public function accountByCode(int $c,string $code):?array {return $this->read('accounts','company_id=%d AND code=%s',[$c,$code]);}
}
