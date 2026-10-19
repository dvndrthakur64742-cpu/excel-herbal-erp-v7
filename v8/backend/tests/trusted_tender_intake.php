<?php
declare(strict_types=1);
require_once __DIR__.'/../src/B2B/RetailerCashSale.php';
require_once __DIR__.'/../src/B2B/TrustedTenderIntake.php';

use ExcelHerbal\ERP8\B2B\RetailerSaleError;
use ExcelHerbal\ERP8\B2B\TrustedTenderIntake;
use ExcelHerbal\ERP8\B2B\TrustedTenderIntakeGateway;

final class TenderIntakeFake implements TrustedTenderIntakeGateway {
    public array $intents=[];public array $evidence=[];public array $bank=[];
    public bool $failWrite=false;public bool $allowCash=true;public bool $allowUpi=true;
    public int $cashAuthCalls=0;public int $bankQueries=0;
    public function __construct(){
        $this->intents=[
          1=>['id'=>1,'company_id'=>1,'branch_id'=>3,'channel'=>'field','employee_id'=>42,'payment_mode'=>'cash','amount_paise'=>500000,'currency'=>'INR','status'=>'awaiting_payment','merchant_order_id'=>null],
          2=>['id'=>2,'company_id'=>1,'branch_id'=>3,'channel'=>'counter','employee_id'=>null,'payment_mode'=>'cash','amount_paise'=>500000,'currency'=>'INR','status'=>'awaiting_payment','merchant_order_id'=>null],
          3=>['id'=>3,'company_id'=>1,'branch_id'=>3,'channel'=>'field','employee_id'=>42,'payment_mode'=>'upi','amount_paise'=>500000,'currency'=>'INR','status'=>'awaiting_payment','merchant_order_id'=>'order-103'],
          4=>['id'=>4,'company_id'=>1,'branch_id'=>5,'channel'=>'counter','employee_id'=>null,'payment_mode'=>'upi','amount_paise'=>500000,'currency'=>'INR','status'=>'awaiting_payment','merchant_order_id'=>'order-104'],
        ];
        $this->bank['lookup-001']=['status'=>'settled','currency'=>'INR','amount_paise'=>500000,'merchant_account'=>'excel-upi-1','merchant_order_id'=>'order-103','transaction_id'=>'BANK-UTR-001'];
    }
    public function atomic(callable $operation):array{
        $snapshot=serialize([$this->evidence]);
        try{return $operation();}catch(Throwable $e){[$this->evidence]=unserialize($snapshot);throw $e;}
    }
    public function lockedIntent(int $companyId,int $branchId,int $intentId):?array{
        $x=$this->intents[$intentId]??null;
        return $x&&$x['company_id']===$companyId&&$x['branch_id']===$branchId?$x:null;
    }
    public function canCollectCash(int $companyId,int $branchId,int $actorId,string $channel,?int $employeeId):bool{
        $this->cashAuthCalls++;
        return $this->allowCash&&$companyId===1&&$branchId===3&&(
          ($channel==='field'&&$employeeId===42&&$actorId===501)
          ||($channel==='counter'&&$employeeId===null&&$actorId===777));
    }
    public function canVerifyUpi(int $companyId,int $branchId,int $actorId):bool{
        return $this->allowUpi&&$companyId===1&&$branchId===3&&$actorId===999;
    }
    public function verifiedBankPayment(string $key):?array{$this->bankQueries++;return $this->bank[$key]??null;}
    public function merchantAccount(int $companyId,int $branchId):string{return $companyId===1&&$branchId===3?'excel-upi-1':'';}
    public function recordConfirmed(array $data):array{
        if($this->failWrite)throw new RetailerSaleError('Trusted evidence persistence failed.');
        $id=$data['intent_id'];
        if(isset($this->evidence[$id])){
            foreach($data as $k=>$v)if(($this->evidence[$id][$k]??null)!==$v)throw new RetailerSaleError('Payment intent already has different confirmed evidence.');
            return $this->evidence[$id]+['status'=>'confirmed'];
        }
        foreach($this->evidence as $existing)if($existing['company_id']===$data['company_id']
            &&$existing['payment_mode']===$data['payment_mode']
            &&$existing['payment_reference']===$data['payment_reference']){
            throw new RetailerSaleError('Payment reference already allocated to another intent.');
        }
        $this->evidence[$id]=$data;return $data+['status'=>'confirmed'];
    }
}
function rejectTender(string $text,callable $callback):void{
  try {$callback();}catch(RetailerSaleError $e){
    if(!str_contains($e->getMessage(),$text))throw new RuntimeException('Wrong rejection: '.$e->getMessage());return;
  }throw new RuntimeException('Should reject: '.$text);
}
$tests=[];
$tests['field cash records employee custody not branch cashier']=function(){
  $g=new TenderIntakeFake;$r=(new TrustedTenderIntake($g))->cashCollected(1,3,501,1);
  assert($r['amount_paise']===500000 && $r['verified_source']==='employee_cash_custody');
  assert($r['payment_reference']==='CASH-INT-1-3-1');
};
$tests['actor user ID may differ from employee ID']=function(){
  $g=new TenderIntakeFake;
  $r=(new TrustedTenderIntake($g))->cashCollected(1,3,501,1);
  assert($g->evidence[1]['employee_id']===42&&$g->evidence[1]['verified_by']===501);
};
$tests['counter cash requires authorized cashier']=function(){
  $g=new TenderIntakeFake;$r=(new TrustedTenderIntake($g))->cashCollected(1,3,777,2);
  assert($r['verified_source']==='branch_cashier_cash'&&$g->evidence[2]['employee_id']===null);
};
$tests['field cash cannot be verified by another employee']=function(){
  $g=new TenderIntakeFake;rejectTender('authority denied',fn()=>(new TrustedTenderIntake($g))->cashCollected(1,3,502,1));
  assert($g->evidence===[]);
};
$tests['cash cannot be attested by retailer or HTTP role claim']=function(){
  $g=new TenderIntakeFake;rejectTender('authority denied',fn()=>(new TrustedTenderIntake($g))->cashCollected(1,3,1,1));
};
$tests['counter cash cannot be verified by regular employee']=function(){
  $g=new TenderIntakeFake;rejectTender('authority denied',fn()=>(new TrustedTenderIntake($g))->cashCollected(1,3,501,2));
};
$tests['UPI settled proof uses only bank source and matching intent order']=function(){
  $g=new TenderIntakeFake;$r=(new TrustedTenderIntake($g))->upiSettled(1,3,999,3,'lookup-001');
  assert($r['verified_source']==='bank_settlement'&&$r['payment_reference']==='BANK-UTR-001');
};
$tests['untrusted staff cannot verify UPI']=function(){
  $g=new TenderIntakeFake;rejectTender('UPI verification authority',fn()=>(new TrustedTenderIntake($g))->upiSettled(1,3,501,3,'lookup-001'));
  assert($g->bankQueries===0);
};
$tests['UPI request lookup reference is not itself proof']=function(){
  $g=new TenderIntakeFake;rejectTender('settled INR',fn()=>(new TrustedTenderIntake($g))->upiSettled(1,3,999,3,'screen-ref-unknown'));
};
$tests['UPI pending or success-only not settled is rejected']=function(){
  foreach(['pending','success','failed'] as $status){$g=new TenderIntakeFake;$g->bank['lookup-001']['status']=$status;
  rejectTender('settled INR',fn()=>(new TrustedTenderIntake($g))->upiSettled(1,3,999,3,'lookup-001'));}
};
$tests['UPI paid less or more than invoice rejected']=function(){
  foreach([499999,500001] as $amount){$g=new TenderIntakeFake;$g->bank['lookup-001']['amount_paise']=$amount;
  rejectTender('exact invoice',fn()=>(new TrustedTenderIntake($g))->upiSettled(1,3,999,3,'lookup-001'));}
};
$tests['UPI string amount rejected, not coerced']=function(){
  $g=new TenderIntakeFake;$g->bank['lookup-001']['amount_paise']='500000';
  rejectTender('settled INR',fn()=>(new TrustedTenderIntake($g))->upiSettled(1,3,999,3,'lookup-001'));
};
$tests['non-INR UPI settlement rejected']=function(){
  $g=new TenderIntakeFake;$g->bank['lookup-001']['currency']='USD';
  rejectTender('settled INR',fn()=>(new TrustedTenderIntake($g))->upiSettled(1,3,999,3,'lookup-001'));
};
$tests['UPI wrong merchant bank account rejected']=function(){
  $g=new TenderIntakeFake;$g->bank['lookup-001']['merchant_account']='not-excel';
  rejectTender('merchant account',fn()=>(new TrustedTenderIntake($g))->upiSettled(1,3,999,3,'lookup-001'));
};
$tests['UPI unlinked merchant order rejected even if paid']=function(){
  $g=new TenderIntakeFake;$g->bank['lookup-001']['merchant_order_id']='other-order';
  rejectTender('merchant order',fn()=>(new TrustedTenderIntake($g))->upiSettled(1,3,999,3,'lookup-001'));
};
$tests['UPI without bank transaction id rejected']=function(){
  $g=new TenderIntakeFake;$g->bank['lookup-001']['transaction_id']='';
  rejectTender('provider transaction identifier',fn()=>(new TrustedTenderIntake($g))->upiSettled(1,3,999,3,'lookup-001'));
};
$tests['wrong branch or company cannot use intent']=function(){
  $g=new TenderIntakeFake;$s=new TrustedTenderIntake($g);
  rejectTender('open company/branch',fn()=>$s->cashCollected(2,3,501,1));
  rejectTender('open company/branch',fn()=>$s->cashCollected(1,5,501,1));
};
$tests['closed intent rejects cash even when actor authorized']=function(){
  $g=new TenderIntakeFake;$g->intents[1]['status']='cancelled';
  rejectTender('open company/branch',fn()=>(new TrustedTenderIntake($g))->cashCollected(1,3,501,1));
};
$tests['cannot cross cash and UPI intent modes']=function(){
  $g=new TenderIntakeFake;$s=new TrustedTenderIntake($g);
  rejectTender('open company/branch',fn()=>$s->cashCollected(1,3,501,3));
  rejectTender('open company/branch',fn()=>$s->upiSettled(1,3,999,1,'lookup-001'));
};
$tests['invalid zero and negative identity cannot reach DB']=function(){
  $g=new TenderIntakeFake;$s=new TrustedTenderIntake($g);
  rejectTender('positive identifiers',fn()=>$s->cashCollected(1,3,501,0));
  rejectTender('positive identifiers',fn()=>$s->upiSettled(0,3,999,3,'lookup-001'));
};
$tests['cash retries return stable evidence not a second tender']=function(){
  $g=new TenderIntakeFake;$s=new TrustedTenderIntake($g);
  $a=$s->cashCollected(1,3,501,1);$b=$s->cashCollected(1,3,501,1);
  assert($a['payment_reference']===$b['payment_reference']&&count($g->evidence)===1);
};
$tests['UPI retries return stable proof only after bank reconfirmation']=function(){
  $g=new TenderIntakeFake;$s=new TrustedTenderIntake($g);
  $a=$s->upiSettled(1,3,999,3,'lookup-001');$b=$s->upiSettled(1,3,999,3,'lookup-001');
  assert($a===$b&&count($g->evidence)===1);
};
$tests['same UPI reference cannot pay two sale intents']=function(){
  $g=new TenderIntakeFake;$g->intents[5]=$g->intents[3];$g->intents[5]['id']=5;
  $s=new TrustedTenderIntake($g);$s->upiSettled(1,3,999,3,'lookup-001');
  rejectTender('already allocated',fn()=>$s->upiSettled(1,3,999,5,'lookup-001'));
  assert(count($g->evidence)===1);
};
$tests['same intent cannot switch bank transaction proof']=function(){
  $g=new TenderIntakeFake;$s=new TrustedTenderIntake($g);
  $s->upiSettled(1,3,999,3,'lookup-001');
  $g->bank['lookup-002']=$g->bank['lookup-001'];$g->bank['lookup-002']['transaction_id']='BANK-UTR-002';
  rejectTender('different confirmed evidence',fn()=>$s->upiSettled(1,3,999,3,'lookup-002'));
};
$tests['write error leaves no confirmed evidence']=function(){
  $g=new TenderIntakeFake;$g->failWrite=true;
  rejectTender('persistence failed',fn()=>(new TrustedTenderIntake($g))->cashCollected(1,3,501,1));
  assert($g->evidence===[]);
};
$tests['invalid UPI key rejects without querying external bank']=function(){
  $g=new TenderIntakeFake;
  rejectTender('lookup key',fn()=>(new TrustedTenderIntake($g))->upiSettled(1,3,999,3,'?'));
  assert($g->bankQueries===0);
};
$tests['counter payment intent cannot claim employee custody']=function(){
  $g=new TenderIntakeFake;$g->intents[2]['employee_id']=42;
  rejectTender('custody intent',fn()=>(new TrustedTenderIntake($g))->cashCollected(1,3,777,2));
};
$tests['field payment intent requires employee ID']=function(){
  $g=new TenderIntakeFake;$g->intents[1]['employee_id']=null;
  rejectTender('custody intent',fn()=>(new TrustedTenderIntake($g))->cashCollected(1,3,501,1));
};
$tests['disabled cash collector authority rejects all cash']=function(){
  $g=new TenderIntakeFake;$g->allowCash=false;
  rejectTender('authority denied',fn()=>(new TrustedTenderIntake($g))->cashCollected(1,3,501,1));
};
$tests['disabled UPI verification authority rejects all UPI']=function(){
  $g=new TenderIntakeFake;$g->allowUpi=false;
  rejectTender('authority denied',fn()=>(new TrustedTenderIntake($g))->upiSettled(1,3,999,3,'lookup-001'));
};
$count=0;
foreach($tests as $name=>$test){
  try{$test();$count++;echo "PASS: {$name}\n";}catch(Throwable $e){fwrite(STDERR,"FAIL: {$name}: {$e->getMessage()}\n");exit(1);}
}
echo "Trusted tender intake: {$count}/{$count} PASS (FAKE gateway; not MySQL)\n";
