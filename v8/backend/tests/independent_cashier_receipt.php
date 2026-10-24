<?php
declare(strict_types=1);
require_once __DIR__.'/../src/B2B/RetailerCashSale.php';
require_once __DIR__.'/../src/B2B/IndependentCashierReceipt.php';
use ExcelHerbal\ERP8\B2B\{IndependentCashierReceipt,IndependentCashierReceiptGateway,RetailerSaleError};

final class CashierReceiptFake implements IndependentCashierReceiptGateway
{
    public bool $allow=true,$failWrite=false;
    public int $writes=0;
    public array $receipts=[];
    public array $pending=['channel'=>'field','payment_mode'=>'cash','sale_status'=>'paid_posted',
      'sale_actor_id'=>2,'amount_due_paise'=>20000,'amount_remitted_paise'=>0,'custody_status'=>'pending'];
    public function atomic(callable $work):array
    {
        $before=[$this->receipts,$this->writes,$this->pending];
        try{return $work();}catch(Throwable $e){[$this->receipts,$this->writes,$this->pending]=$before;throw $e;}
    }
    public function canAttest(int $a,int $c,int $b):bool{return $this->allow && $a===3 && $c===1 && $b===1;}
    public function lockedFieldCash(int $c,int $b,int $s,int $e):?array
    {
        return $c===1 && $b===1 && $s===77 && $e===6 ? $this->pending : null;
    }
    public function existingByReference(int $c,int $b,string $r):?array
    {
        foreach($this->receipts as $v)if($v['company_id']===$c&&$v['branch_id']===$b&&$v['cash_receipt_reference']===$r)return$v;
        return null;
    }
    public function existingBySale(int $c,int $s):?array
    {
        return $this->receipts[$c.':'.$s]??null;
    }
    public function storeAttestedReceipt(array $record):array
    {
        if ($this->failWrite)throw new RetailerSaleError('Simulated receipt insert failure');
        $this->writes++;
        $v=$record+['id'=>$this->writes,'consumed_event_id'=>null];
        $this->receipts[$record['company_id'].':'.$record['sale_id']]=$v;
        return $v;
    }
}
function cashContext(array $patch=[]):array
{
    return array_replace(['company_id'=>1,'branch_id'=>1,'actor_id'=>3,'employee_id'=>6,
        'sale_id'=>77,'cash_receipt_reference'=>'CASHIER-REC-0001'],$patch);
}
function rejectCashier(string $word,callable $fn):void
{
    try{$fn();}catch(RetailerSaleError $e){
       if(!str_contains(strtolower($e->getMessage()),strtolower($word)))
          throw new RuntimeException('Wrong error: '.$e->getMessage());
       return;
    }
    throw new RuntimeException('Expected rejection: '.$word);
}
$checks=[];
$checks['cashier independently attests full sale custody'] = function(){
    $g=new CashierReceiptFake;$a=(new IndependentCashierReceipt($g))->attest(cashContext());
    assert($a['id']===1 && $a['amount_paise']===20000 && $a['cashier_actor_id']===3);
    assert($a['verified_source']==='cashier' && $a['status']==='confirmed' && $g->writes===1);
};
$checks['exact receipt replay does not duplicate cash receipt'] = function(){
    $g=new CashierReceiptFake;$s=new IndependentCashierReceipt($g);
    $a=$s->attest(cashContext());$b=$s->attest(cashContext());assert($a===$b && $g->writes===1);
};
$checks['receipt retry after remittance remains idempotent, not new evidence'] = function(){
    $g=new CashierReceiptFake;$s=new IndependentCashierReceipt($g);
    $a=$s->attest(cashContext());$g->pending['amount_remitted_paise']=20000;$g->pending['custody_status']='settled';
    $b=$s->attest(cashContext());assert($a===$b && $g->writes===1);
};
$checks['receipt reference replay for another employee forbidden'] = function(){
    $g=new CashierReceiptFake;$s=new IndependentCashierReceipt($g);$s->attest(cashContext());
    rejectCashier('independent',fn()=>$s->attest(cashContext(['employee_id'=>7])));assert($g->writes===1);
};
$checks['new receipt reference for posted sale rejected'] = function(){
    $g=new CashierReceiptFake;$s=new IndependentCashierReceipt($g);$s->attest(cashContext());
    rejectCashier('already been attested',fn()=>$s->attest(cashContext(['cash_receipt_reference'=>'CASHIER-REC-0002'])));
};
$checks['ordinary sale actor cannot self attest physical cash'] = function(){
    $g=new CashierReceiptFake;$g->pending['sale_actor_id']=3;
    rejectCashier('independent',fn()=>(new IndependentCashierReceipt($g))->attest(cashContext()));
    assert($g->writes===0);
};
$checks['no cashier permission prevents all writes'] = function(){
    $g=new CashierReceiptFake;$g->allow=false;
    rejectCashier('authorization',fn()=>(new IndependentCashierReceipt($g))->attest(cashContext()));assert($g->writes===0);
};
$checks['branch role permission cannot be bypassed'] = function(){
    $g=new CashierReceiptFake;rejectCashier('authorization',fn()=>(new IndependentCashierReceipt($g))->attest(cashContext(['branch_id'=>2])));
};
$checks['no field cash liability cannot attest'] = function(){
    $g=new CashierReceiptFake;rejectCashier('independent',fn()=>(new IndependentCashierReceipt($g))->attest(cashContext(['sale_id'=>99])));
};
$checks['UPI sale cannot produce cash receipt'] = function(){
    $g=new CashierReceiptFake;$g->pending['payment_mode']='upi';
    rejectCashier('field Cash',fn()=>(new IndependentCashierReceipt($g))->attest(cashContext()));
};
$checks['counter sale cannot produce employee cash receipt'] = function(){
    $g=new CashierReceiptFake;$g->pending['channel']='counter';
    rejectCashier('field Cash',fn()=>(new IndependentCashierReceipt($g))->attest(cashContext()));
};
$checks['unposted sale cannot produce receipt'] = function(){
    $g=new CashierReceiptFake;$g->pending['sale_status']='awaiting_payment';
    rejectCashier('field Cash',fn()=>(new IndependentCashierReceipt($g))->attest(cashContext()));
};
$checks['partial cash custody cannot produce receipt'] = function(){
    $g=new CashierReceiptFake;$g->pending['amount_remitted_paise']=1;
    rejectCashier('already remitted',fn()=>(new IndependentCashierReceipt($g))->attest(cashContext()));
};
$checks['settled cash cannot produce new receipt'] = function(){
    $g=new CashierReceiptFake;$g->pending['custody_status']='settled';
    rejectCashier('already remitted',fn()=>(new IndependentCashierReceipt($g))->attest(cashContext()));
};
$checks['zero due cannot produce receipt'] = function(){
    $g=new CashierReceiptFake;$g->pending['amount_due_paise']=0;
    rejectCashier('liability',fn()=>(new IndependentCashierReceipt($g))->attest(cashContext()));
};
$checks['no cashier receipt reference injection'] = function(){
    $g=new CashierReceiptFake;rejectCashier('reference',fn()=>(new IndependentCashierReceipt($g))->attest(cashContext(['cash_receipt_reference'=>'  ref  '])));
};
$checks['negative company IDs are rejected'] = function(){
    $g=new CashierReceiptFake;rejectCashier('positive',fn()=>(new IndependentCashierReceipt($g))->attest(cashContext(['company_id'=>-1])));
};
$checks['independent receipt insertion failure rolls back'] = function(){
    $g=new CashierReceiptFake;$g->failWrite=true;
    rejectCashier('simulated',fn()=>(new IndependentCashierReceipt($g))->attest(cashContext()));
    assert($g->receipts===[] && $g->writes===0);
};
$checks['request fake amount is ignored, locked liability remains authority'] = function(){
    $g=new CashierReceiptFake;$a=(new IndependentCashierReceipt($g))->attest(cashContext(['amount_paise'=>1,'verified_source'=>'browser']));
    assert($a['amount_paise']===20000 && $a['verified_source']==='cashier');
};
$checks['same sale forged cashier actor fails separate RBAC'] = function(){
    $g=new CashierReceiptFake;rejectCashier('authorization',fn()=>(new IndependentCashierReceipt($g))->attest(cashContext(['actor_id'=>999])));
};
$pass=0;foreach($checks as $name=>$cb){try{$cb();++$pass;echo "PASS $name\n";}catch(Throwable $e){fwrite(STDERR,"FAIL $name: {$e->getMessage()}\n");exit(1);}}
echo "PASS $pass/".count($checks)." independent cashier receipt tests\n";
