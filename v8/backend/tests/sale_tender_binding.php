<?php
declare(strict_types=1);
require_once __DIR__.'/../src/B2B/RetailerCashSale.php';
require_once __DIR__.'/../src/B2B/SaleIntentTenderBinding.php';
use ExcelHerbal\ERP8\B2B\RetailerSaleError;
use ExcelHerbal\ERP8\B2B\SaleIntentTenderBinding;
use ExcelHerbal\ERP8\B2B\SaleIntentTenderBindingGateway;

final class SaleBindingFake implements SaleIntentTenderBindingGateway
{
    public array $sales=[],$payment=[],$proof=[],$bindings=[];
    public bool $allowed=true,$writeFailure=false;
    public int $nextId=1,$writes=0,$assessments=0;
    public function __construct()
    {
        $digest=str_repeat('a',64);
        $this->sales=[1=>['id'=>1,'company_id'=>8,'branch_id'=>3,'retailer_id'=>55,'canonical_party_id'=>901,
            'status'=>'awaiting_payment','currency'=>'INR','pricing_locked'=>true,'invoice_total_paise'=>500000,
            'quote_digest'=>$digest,'channel'=>'field','employee_id'=>42,'payment_mode'=>'cash','merchant_order_id'=>null]];
        $this->payment=[9=>['id'=>9,'company_id'=>8,'branch_id'=>3,'sale_intent_id'=>1,'linked_quote_digest'=>$digest,
            'status'=>'awaiting_payment','currency'=>'INR','amount_paise'=>500000,'channel'=>'field','employee_id'=>42,
            'payment_mode'=>'cash','merchant_order_id'=>null]];
        $this->proof=[9=>['intent_id'=>9,'confirmed_tender_id'=>100,'company_id'=>8,'branch_id'=>3,
            'amount_paise'=>500000,'payment_mode'=>'cash','channel'=>'field','employee_id'=>42,
            'status'=>'confirmed','tender_status'=>'confirmed','consumed_sale_id'=>null,
            'verified_by'=>777,'payment_reference'=>'CASH-INT-8-3-9','verified_source'=>'employee_cash_custody']];
    }
    public function atomic(callable $work):array
    {
        $backup=[$this->bindings,$this->nextId,$this->writes];
        try{return $work();}catch(Throwable $e){[$this->bindings,$this->nextId,$this->writes]=$backup;throw $e;}
    }
    public function lockedSaleIntent(int $c,int $b,int $id):?array
    { $r=$this->sales[$id]??null;return $r&&$r['company_id']===$c&&$r['branch_id']===$b?$r:null; }
    public function canBind(int $c,int $b,int $actor,array $sale):bool
    { $this->assessments++;return $this->allowed&&$c===8&&$b===3&&$actor===777; }
    public function lockedPaymentIntent(int $c,int $b,int $id):?array
    { $r=$this->payment[$id]??null;return $r&&$r['company_id']===$c&&$r['branch_id']===$b?$r:null; }
    public function lockedConfirmedEvidence(int $c,int $b,int $id):?array
    { $r=$this->proof[$id]??null;return $r&&$r['company_id']===$c&&$r['branch_id']===$b?$r:null; }
    public function existingForSale(int $c,int $id):?array
    {foreach($this->bindings as $r)if($r['company_id']===$c&&$r['sale_intent_id']===$id)return $r;return null;}
    public function existingForTender(int $c,int $id):?array
    {foreach($this->bindings as $r)if($r['company_id']===$c&&$r['tender_id']===$id)return $r;return null;}
    public function saveReservedBinding(array $r):array
    {if($this->writeFailure)throw new RetailerSaleError('Simulated binding persistence failure.');
        $this->writes++;$r['id']=$this->nextId++;$this->bindings[$r['id']]=$r;return $r;}
}
function ctx(array $override=[]):array{return array_replace(['company_id'=>8,'branch_id'=>3,'actor_id'=>777,'sale_intent_id'=>1,'payment_intent_id'=>9],$override);}
function denyBinding(string $needle, callable $operation):void
{try{$operation();}catch(RetailerSaleError $e){if(!str_contains($e->getMessage(),$needle))throw new RuntimeException('Wrong denial: '.$e->getMessage());return;}throw new RuntimeException('Expected denial: '.$needle);}
$tests=[];
$tests['confirmed field cash binds to canonical customer without posting']=function(){
    $g=new SaleBindingFake;$r=(new SaleIntentTenderBinding($g))->reserve(ctx());
    assert($r['binding_id']===1&&$r['canonical_party_id']===901&&$r['amount_paise']===500000&&$r['posting_allowed']===false);
    assert($r['status']==='reserved'&&$g->writes===1);
};
$tests['safe repeat preserves same reservation']=function(){
    $g=new SaleBindingFake;$s=new SaleIntentTenderBinding($g);$a=$s->reserve(ctx());$b=$s->reserve(ctx());
    assert($a===$b&&$g->writes===1&&count($g->bindings)===1);
};
$tests['unauthorized actor cannot bind']=function(){
    $g=new SaleBindingFake;denyBinding('binder required',fn()=>(new SaleIntentTenderBinding($g))->reserve(ctx(['actor_id'=>12])));
    assert($g->bindings===[]);
};
$tests['authority failure cannot be overridden by request claims']=function(){
    $g=new SaleBindingFake;$g->allowed=false;denyBinding('binder required',fn()=>(new SaleIntentTenderBinding($g))->reserve(ctx()+['authorized'=>true]));
};
$tests['negative, string and zero identity inputs denied']=function(){
    foreach([0,-1,'8',null] as $x){$g=new SaleBindingFake;denyBinding('positive ID',fn()=>(new SaleIntentTenderBinding($g))->reserve(ctx(['company_id'=>$x])));}
};
$tests['other branch cannot access original sale']=function(){
    $g=new SaleBindingFake;denyBinding('locked INR',fn()=>(new SaleIntentTenderBinding($g))->reserve(ctx(['branch_id'=>4])));
};
$tests['other company cannot access original sale']=function(){
    $g=new SaleBindingFake;denyBinding('locked INR',fn()=>(new SaleIntentTenderBinding($g))->reserve(ctx(['company_id'=>9])));
};
$tests['closed, posted or cancelled sale denied']=function(){
    foreach(['posted','cancelled','payment_verified'] as $state){$g=new SaleBindingFake;$g->sales[1]['status']=$state;
        denyBinding('locked INR',fn()=>(new SaleIntentTenderBinding($g))->reserve(ctx()));}
};
$tests['unpriced or unlocked quote cannot bind']=function(){
    foreach([false,0,null] as $x){$g=new SaleBindingFake;$g->sales[1]['pricing_locked']=$x;
        denyBinding('locked INR',fn()=>(new SaleIntentTenderBinding($g))->reserve(ctx()));}
};
$tests['zero or altered invoice total is denied']=function(){
    foreach([0,-1] as $x){$g=new SaleBindingFake;$g->sales[1]['invoice_total_paise']=$x;
        denyBinding('locked INR',fn()=>(new SaleIntentTenderBinding($g))->reserve(ctx()));}
    $g=new SaleBindingFake;$g->sales[1]['invoice_total_paise']=500001;
    denyBinding('exact priced sale',fn()=>(new SaleIntentTenderBinding($g))->reserve(ctx()));
};
$tests['non INR and missing canonical party denied']=function(){
    $g=new SaleBindingFake;$g->sales[1]['currency']='USD';denyBinding('locked INR',fn()=>(new SaleIntentTenderBinding($g))->reserve(ctx()));
    $g=new SaleBindingFake;$g->sales[1]['canonical_party_id']=0;denyBinding('Canonical retailer identity',fn()=>(new SaleIntentTenderBinding($g))->reserve(ctx()));
};
$tests['invalid quote digest denied']=function(){
    $g=new SaleBindingFake;$g->sales[1]['quote_digest']='bad';denyBinding('quote digest',fn()=>(new SaleIntentTenderBinding($g))->reserve(ctx()));
};
$tests['different checkout quote fingerprint denied']=function(){
    $g=new SaleBindingFake;$g->payment[9]['linked_quote_digest']=str_repeat('b',64);
    denyBinding('exact priced sale',fn()=>(new SaleIntentTenderBinding($g))->reserve(ctx()));
};
$tests['payment belonging to another sale denied']=function(){
    $g=new SaleBindingFake;$g->payment[9]['sale_intent_id']=2;
    denyBinding('exact priced sale',fn()=>(new SaleIntentTenderBinding($g))->reserve(ctx()));
};
$tests['payment cannot switch cash to UPI']=function(){
    $g=new SaleBindingFake;$g->payment[9]['payment_mode']='upi';
    denyBinding('exact priced sale',fn()=>(new SaleIntentTenderBinding($g))->reserve(ctx()));
};
$tests['employee stock custody mismatch denied']=function(){
    $g=new SaleBindingFake;$g->payment[9]['employee_id']=100;
    denyBinding('exact priced sale',fn()=>(new SaleIntentTenderBinding($g))->reserve(ctx()));
};
$tests['cash order cannot smuggle merchant order']=function(){
    $g=new SaleBindingFake;$g->payment[9]['merchant_order_id']='UPI-ABC';
    denyBinding('Cash sale',fn()=>(new SaleIntentTenderBinding($g))->reserve(ctx()));
};
$tests['UPI binding requires independently matched sale order and bank settlement']=function(){
    $g=new SaleBindingFake;$g->sales[1]['payment_mode']='upi';$g->payment[9]['payment_mode']='upi';
    $g->sales[1]['merchant_order_id']='ORDER-1';$g->payment[9]['merchant_order_id']='ORDER-1';
    $g->proof[9]['payment_mode']='upi';$g->proof[9]['verified_source']='bank_settlement';
    $g->proof[9]['payment_reference']='BANK-UTR-00099';
    $r=(new SaleIntentTenderBinding($g))->reserve(ctx());assert($r['posting_allowed']===false);
    $g=new SaleBindingFake;$g->sales[1]['payment_mode']='upi';$g->payment[9]['payment_mode']='upi';
    $g->sales[1]['merchant_order_id']='ORDER-1';$g->payment[9]['merchant_order_id']='ORDER-2';
    denyBinding('merchant order',fn()=>(new SaleIntentTenderBinding($g))->reserve(ctx()));
};
$tests['pending or absent verified evidence denied']=function(){
    $g=new SaleBindingFake;unset($g->proof[9]);denyBinding('Confirmed, unconsumed',fn()=>(new SaleIntentTenderBinding($g))->reserve(ctx()));
    $g=new SaleBindingFake;$g->proof[9]['tender_status']='pending';
    denyBinding('Confirmed, unconsumed',fn()=>(new SaleIntentTenderBinding($g))->reserve(ctx()));
};
$tests['already consumed tender denied']=function(){
    $g=new SaleBindingFake;$g->proof[9]['consumed_sale_id']=567;
    denyBinding('Confirmed, unconsumed',fn()=>(new SaleIntentTenderBinding($g))->reserve(ctx()));
};
$tests['wrong proof branch or amount denied']=function(){
    $g=new SaleBindingFake;$g->proof[9]['branch_id']=4;
    denyBinding('Confirmed, unconsumed',fn()=>(new SaleIntentTenderBinding($g))->reserve(ctx()));
    $g=new SaleBindingFake;$g->proof[9]['amount_paise']=499999;
    denyBinding('Confirmed, unconsumed',fn()=>(new SaleIntentTenderBinding($g))->reserve(ctx()));
};
$tests['staff screenshot/claimed bank source cannot masquerade as settled payment']=function(){
    $g=new SaleBindingFake;$g->proof[9]['verified_source']='bank_settlement';
    denyBinding('custody and verification',fn()=>(new SaleIntentTenderBinding($g))->reserve(ctx()));
};
$tests['malformed proof reference denied']=function(){
    $g=new SaleBindingFake;$g->proof[9]['payment_reference']='X';
    denyBinding('reference required',fn()=>(new SaleIntentTenderBinding($g))->reserve(ctx()));
};
$tests['same confirmed tender cannot fund another sale intent']=function(){
    $g=new SaleBindingFake;$s=new SaleIntentTenderBinding($g);$s->reserve(ctx());
    $g->sales[2]=$g->sales[1];$g->sales[2]['id']=2;
    $g->payment[10]=$g->payment[9];$g->payment[10]['id']=10;$g->payment[10]['sale_intent_id']=2;
    $g->proof[10]=$g->proof[9];$g->proof[10]['intent_id']=10;
    denyBinding('different sale',fn()=>$s->reserve(ctx(['sale_intent_id'=>2,'payment_intent_id'=>10])));
    assert(count($g->bindings)===1);
};
$tests['same sale cannot switch evidence after reservation']=function(){
    $g=new SaleBindingFake;$s=new SaleIntentTenderBinding($g);$s->reserve(ctx());
    $g->proof[9]['confirmed_tender_id']=101;
    denyBinding('different sale',fn()=>$s->reserve(ctx()));
};
$tests['quote modification after binding invalidates replay']=function(){
    $g=new SaleBindingFake;$s=new SaleIntentTenderBinding($g);$s->reserve(ctx());
    $g->sales[1]['quote_digest']=str_repeat('b',64);
    $g->payment[9]['linked_quote_digest']=str_repeat('b',64);
    denyBinding('different sale',fn()=>$s->reserve(ctx()));
};
$tests['failed insert fully rolls back reservation']=function(){
    $g=new SaleBindingFake;$g->writeFailure=true;
    denyBinding('persistence failure',fn()=>(new SaleIntentTenderBinding($g))->reserve(ctx()));
    assert($g->bindings===[]&&$g->writes===0);
};
$tests['corrupted prior reservation forbidden']=function(){
    $g=new SaleBindingFake;$s=new SaleIntentTenderBinding($g);$s->reserve(ctx());
    $g->bindings[1]['status']='posted';
    denyBinding('cannot be reused',fn()=>$s->reserve(ctx()));
};
$tests['counter cash is branch custody, not employee custody']=function(){
    $g=new SaleBindingFake;$g->sales[1]['channel']='counter';$g->sales[1]['employee_id']=null;
    $g->payment[9]['channel']='counter';$g->payment[9]['employee_id']=null;
    $g->proof[9]['channel']='counter';$g->proof[9]['employee_id']=null;
    $g->proof[9]['verified_source']='branch_cashier_cash';
    assert((new SaleIntentTenderBinding($g))->reserve(ctx())['posting_allowed']===false);
};
$count=0;foreach($tests as $name=>$test){try{$test();$count++;echo "PASS: $name\n";}catch(Throwable $e){fwrite(STDERR,"FAIL: $name: {$e->getMessage()}\n");exit(1);}}
echo "Sale intent tender binding: $count/$count PASS (FAKE gateway; no live ERP writes)\n";
