<?php
declare(strict_types=1);
require_once __DIR__.'/../src/B2B/RetailerCashSale.php';
require_once __DIR__.'/../src/B2B/ImmutableRetailerIntentIssuer.php';
use ExcelHerbal\ERP8\B2B\{ImmutableRetailerIntentIssuer,ImmutableRetailerIntentGateway,RetailerSaleError};

final class ImmutableIssuerFake implements ImmutableRetailerIntentGateway
{
    public array $stored=[];
    public int $creates=0;
    public bool $authorized=true,$failCreate=false,$active=false;
    public function atomic(callable $work):array{
        if($this->active)throw new RuntimeException('unexpected nested transaction');
        $old=$this->stored;$oldCreates=$this->creates;$this->active=true;
        try{$result=$work();return $result;}
        catch(Throwable $e){$this->stored=$old;$this->creates=$oldCreates;throw $e;}
        finally{$this->active=false;}
    }
    public function lockRequest(int $companyId,string $requestKey):void{if(!$this->active)throw new RuntimeException('unlocked fake');}
    public function canIssue(int $companyId,int $branchId,int $actorId,?int $employeeId,string $channel):bool{
        return $this->authorized && $companyId===1 && $branchId===2 && $actorId===7
            && (($channel==='field'&&$employeeId===7)||($channel==='counter'&&$employeeId===null));
    }
    public function existingPair(int $companyId,string $requestKey):?array{return $this->stored[$companyId.':'.$requestKey]??null;}
    public function createPair(array $snapshot,string $requestKey,?string $merchantOrderId):array{
        if($this->failCreate)throw new RuntimeException('simulated atomic DB failure');
        $this->creates++;
        $r=['sale_intent_id'=>101+$this->creates,'payment_intent_id'=>201+$this->creates,
            'invoice_total_paise'=>$snapshot['gross_paise'],'quote_digest'=>hash('sha256',json_encode($snapshot,JSON_THROW_ON_ERROR)),
            'merchant_order_id'=>$merchantOrderId,'status'=>'awaiting_payment','currency'=>'INR','pricing_locked'=>true];
        foreach(['company_id','branch_id','retailer_id','canonical_party_id','channel','employee_id','payment_mode'] as $k)$r[$k]=$snapshot[$k];
        $this->stored[$snapshot['company_id'].':'.$requestKey]=$r;return $r;
    }
}
function serverPreview(array $replace=[]):array{
    $s=['company_id'=>1,'branch_id'=>2,'retailer_id'=>9,'canonical_party_id'=>12,
        'channel'=>'counter','employee_id'=>null,'business_at'=>'2026-10-19 11:35:00',
        'payment_mode'=>'cash','gross_paise'=>20000,
        'lines'=>[['product_id'=>3,'batch_id'=>0,'quantity_pcs'=>2,'commercial_revision_id'=>88,'unit_price_paise'=>10000,'line_total_paise'=>20000]]];
    $s=array_replace($s,$replace);$digest=hash('sha256',json_encode($s,JSON_THROW_ON_ERROR));
    return $s+['shop_name'=>'Example Shop','preview_digest'=>$digest,'posting_allowed'=>false,
        'stock_reserved'=>false,'credit_allowed'=>false,'retailer_outstanding_paise'=>0,
        'release_status'=>'preview_only','requires_locked_revalidation'=>true,
        'tax_invoice_status'=>'policy_not_approved','payment_verification_status'=>'not_verified_by_preview'];
}
function issueRequest(array $delta=[]):array{return array_replace(['company_id'=>1,'branch_id'=>2,'actor_id'=>7,'request_key'=>str_repeat('a',32)],$delta);}
function failIssue(ImmutableIssuerFake $f,array $ctx=[],array $preview=[],string $expected=''):void{
    try{(new ImmutableRetailerIntentIssuer($f))->issue(issueRequest($ctx),serverPreview($preview));}
    catch(RetailerSaleError $e){if($expected!==''&&!str_contains($e->getMessage(),$expected))throw new RuntimeException('Expected '.$expected.' but saw '.$e->getMessage());return;}
    throw new RuntimeException('Unsafe intent issuance was accepted');
}
$cases=[];
$cases['Cash full-pay linked UAT sale/payment intents']=$run=function(){
    $f=new ImmutableIssuerFake;$out=(new ImmutableRetailerIntentIssuer($f))->issue(issueRequest(),serverPreview());
    assert($out['sale_intent_id']===102 && $out['payment_intent_id']===202);
    assert($out['posting_allowed']===false&&$out['stock_reserved']===false&&$out['status']==='awaiting_payment');
    assert($out['merchant_order_id']===null&&$out['payment_verification_status']==='not_verified');
};
$cases['request replay returns same sale and payment without duplicate']=function(){
    $f=new ImmutableIssuerFake;$issuer=new ImmutableRetailerIntentIssuer($f);
    $a=$issuer->issue(issueRequest(),serverPreview());$b=$issuer->issue(issueRequest(),serverPreview());
    assert($a===$b && $f->creates===1);
};
$cases['UPI generates server-side unique merchant order']=function(){
    $f=new ImmutableIssuerFake;$p=serverPreview(['payment_mode'=>'upi']);$svc=new ImmutableRetailerIntentIssuer($f);
    $a=$svc->issue(issueRequest(),$p);$b=$svc->issue(issueRequest(['request_key'=>str_repeat('b',32)]),$p);
    assert(preg_match('/^EH8-UAT-[a-f0-9]{32}$/D',$a['merchant_order_id'])===1);
    assert($a['merchant_order_id']!==$b['merchant_order_id']);
};
$cases['UPI retry preserves original merchant order']=function(){
    $f=new ImmutableIssuerFake;$svc=new ImmutableRetailerIntentIssuer($f);$p=serverPreview(['payment_mode'=>'upi']);
    assert($svc->issue(issueRequest(),$p)===$svc->issue(issueRequest(),$p));
};
$cases['different request keys create separate intents']=function(){
    $f=new ImmutableIssuerFake;$svc=new ImmutableRetailerIntentIssuer($f);
    $a=$svc->issue(issueRequest(),serverPreview());$b=$svc->issue(issueRequest(['request_key'=>str_repeat('c',32)]),serverPreview());
    assert($a['sale_intent_id']!==$b['sale_intent_id']&&$f->creates===2);
};
$cases['reusing key with changed quote fails']=function(){
    $f=new ImmutableIssuerFake;$svc=new ImmutableRetailerIntentIssuer($f);
    $svc->issue(issueRequest(),serverPreview());
    failIssue($f,[],['gross_paise'=>10000,'lines'=>[['product_id'=>3,'batch_id'=>0,'quantity_pcs'=>1,'commercial_revision_id'=>88,'unit_price_paise'=>10000,'line_total_paise'=>10000]]],'canonical quote');
    assert($f->creates===1);
};
$cases['buyer from another branch denied']=fn()=>failIssue(new ImmutableIssuerFake,['branch_id'=>3],[],'differs');
$cases['different company denied']=fn()=>failIssue(new ImmutableIssuerFake,['company_id'=>3],[],'differs');
$cases['malformed idempotency key denied']=fn()=>failIssue(new ImmutableIssuerFake,['request_key'=>'weak'],[],'idempotency');
$cases['browser-changed price without digest denied']=function(){
    $p=serverPreview();$p['gross_paise']=50000;$f=new ImmutableIssuerFake;
    try{(new ImmutableRetailerIntentIssuer($f))->issue(issueRequest(),$p);throw new RuntimeException('Accepted tampering');}
    catch(RetailerSaleError $e){assert(str_contains($e->getMessage(),'digest'));}
};
$cases['partial sale total mismatch denied']=fn()=>failIssue(new ImmutableIssuerFake,[],['gross_paise'=>10000],'do not equal');
$cases['zero value denied']=fn()=>failIssue(new ImmutableIssuerFake,[],['gross_paise'=>0],'full-pay');
$cases['credit / unsupported tender denied']=fn()=>failIssue(new ImmutableIssuerFake,[],['payment_mode'=>'credit'],'full-pay');
$cases['other unapproved tender split denied']=fn()=>failIssue(new ImmutableIssuerFake,[],['payment_mode'=>'cash+upi'],'full-pay');
$cases['duplicate product batch line denied']=function(){
    $line=['product_id'=>3,'batch_id'=>0,'quantity_pcs'=>1,'commercial_revision_id'=>88,'unit_price_paise'=>10000,'line_total_paise'=>10000];
    failIssue(new ImmutableIssuerFake,[],['lines'=>[$line,$line]],'Duplicate');
};
$cases['field sale must have employee custodian']=fn()=>failIssue(new ImmutableIssuerFake,[],['channel'=>'field'],'custodian');
$cases['counter sale cannot take employee custodian']=fn()=>failIssue(new ImmutableIssuerFake,[],['employee_id'=>7],'custodian');
$cases['field sale with authorized custodian accepted']=function(){
    $r=(new ImmutableRetailerIntentIssuer(new ImmutableIssuerFake))->issue(issueRequest(),serverPreview(['channel'=>'field','employee_id'=>7]));
    assert($r['status']==='awaiting_payment'&&$r['posting_allowed']===false);
};
$cases['unauthorized issuer refused']=function(){$f=new ImmutableIssuerFake;$f->authorized=false;failIssue($f,[],[],'permission denied');};
$cases['missing canonical retailer link refused']=function(){
    $p=serverPreview();unset($p['canonical_party_id']);$f=new ImmutableIssuerFake;
    try{(new ImmutableRetailerIntentIssuer($f))->issue(issueRequest(),$p);throw new RuntimeException('Accepted missing link');}
    catch(RetailerSaleError $e){assert(str_contains($e->getMessage(),'identity'));}
};
$cases['preview posting flag rejected']=function(){
    $p=serverPreview();$p['posting_allowed']=true;$f=new ImmutableIssuerFake;
    try{(new ImmutableRetailerIntentIssuer($f))->issue(issueRequest(),$p);throw new RuntimeException('Accepted posting flag');}
    catch(RetailerSaleError $e){assert(str_contains($e->getMessage(),'fail-closed'));}
};
$cases['preview GST policy status must remain blocked']=function(){
    $p=serverPreview();$p['tax_invoice_status']='approved';$f=new ImmutableIssuerFake;
    try{(new ImmutableRetailerIntentIssuer($f))->issue(issueRequest(),$p);throw new RuntimeException('Accepted policy flag');}
    catch(RetailerSaleError $e){assert(str_contains($e->getMessage(),'fail-closed'));}
};
$cases['confirmed payment must not be forged in preview']=function(){
    $p=serverPreview();$p['payment_verification_status']='confirmed';$f=new ImmutableIssuerFake;
    try{(new ImmutableRetailerIntentIssuer($f))->issue(issueRequest(),$p);throw new RuntimeException('Accepted verified flag');}
    catch(RetailerSaleError $e){assert(str_contains($e->getMessage(),'fail-closed'));}
};
$cases['failed DB insert rolls back receipt']=function(){
    $f=new ImmutableIssuerFake;$f->failCreate=true;
    try{(new ImmutableRetailerIntentIssuer($f))->issue(issueRequest(),serverPreview());throw new RuntimeException('Expected DB failure');}
    catch(RuntimeException $e){if($e->getMessage()==='Expected DB failure')throw $e;}
    assert($f->creates===0&&$f->stored===[]);
};
$cases['stale/invalid existing pair rejected']=function(){
    $f=new ImmutableIssuerFake;$svc=new ImmutableRetailerIntentIssuer($f);$svc->issue(issueRequest(),serverPreview());
    $f->stored['1:'.str_repeat('a',32)]['pricing_locked']=false;
    failIssue($f,[],[],'not locked');
};
$cases['overflow money amount denied']=function(){
    $l=['product_id'=>3,'batch_id'=>0,'quantity_pcs'=>PHP_INT_MAX,'commercial_revision_id'=>88,'unit_price_paise'=>10000,'line_total_paise'=>10000];
    failIssue(new ImmutableIssuerFake,[],['lines'=>[$l]],'overflow');
};
$done=0;
foreach($cases as $label=>$test){try{$test();$done++;echo "PASS $label\n";}catch(Throwable $e){fwrite(STDERR,"FAIL $label: ".$e->getMessage()."\n");exit(1);}}
echo "PASS $done/".count($cases)." immutable sale/payment issuance regressions\n";
