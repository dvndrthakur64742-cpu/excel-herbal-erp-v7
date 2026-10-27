<?php
declare(strict_types=1);
require dirname(__DIR__).'/src/B2B/RetailerCashSale.php';
require dirname(__DIR__).'/src/B2B/EmployeeCashRemittance.php';
require dirname(__DIR__).'/src/B2B/EmployeeRemittanceApi.php';
use ExcelHerbal\ERP8\B2B\{EmployeeRemittanceGateway,EmployeeCashRemittance,EmployeeRemittanceApi,RetailerSaleError};

final class RemittanceFake implements EmployeeRemittanceGateway
{
    public bool $allow = true;
    public bool $receiptConfirmed = true;
    public bool $failPosting = false;
    public array $pending = ['amount_due_paise'=>20000,'amount_remitted_paise'=>0,'status'=>'pending'];
    public array $byKey = [];
    public array $journals = [];
    public array $receipts = [];
    public int $eventCount = 0;
    public function atomic(callable $work):array
    {
        $before=[$this->pending,$this->byKey,$this->journals,$this->receipts,$this->eventCount];
        try{return $work();}catch(Throwable $e){[$this->pending,$this->byKey,$this->journals,$this->receipts,$this->eventCount]=$before;throw $e;}
    }
    public function canConfirmRemittance(int $a,int $c,int $b):bool{return $this->allow && $a===2 && $c===1 && $b===1;}
    public function lockRemittanceKey(int $c,string $key):void{}
    public function remittanceByKey(int $c,string $key):?array{return $this->byKey[$c.':'.$key]??null;}
    public function pendingCash(int $c,int $b,int $s,int $e):?array{return ($c===1 && $b===1 && $s===77 && $e===6)?$this->pending:null;}
    public function confirmedBranchReceipt(int $c,int $b,int $s,int $e,string $ref,int $amount):bool
    {
        return $this->receiptConfirmed && $c===1 && $b===1 && $s===77 && $e===6 && $amount===20000 && $ref==='BRANCH-CASH-001' && !isset($this->receipts[$ref]);
    }
    public function recordCashRemittance(array $record,array $journal):array
    {
        if($this->failPosting)throw new RetailerSaleError('Simulated transaction failure');
        if($this->pending['status']!=='pending' || $this->eventCount!==0 || $journal[0]['debit_paise']!==$journal[1]['credit_paise'])throw new RetailerSaleError('Invalid posting');
        $this->eventCount++;
        $this->pending=['amount_due_paise'=>20000,'amount_remitted_paise'=>20000,'status'=>'settled'];
        $this->receipts[$record['cash_receipt_reference']]=true;
        $this->journals[]=$journal;
        $record['id']=1;
        $this->byKey[$record['company_id'].':'.$record['idempotency_key']]=$record;
        return $record;
    }
}
function remitRequest(array $data=[]):array
{
    return array_replace(['company_id'=>1,'branch_id'=>1,'actor_id'=>2,'employee_id'=>6,'sale_id'=>77,
      'cash_receipt_reference'=>'BRANCH-CASH-001','amount'=>'200.00','idempotency_key'=>'cash-remittance-001'],$data);
}
function remitFailure(string $fragment,callable $fn):void
{
    try{$fn();}catch(RetailerSaleError $e){if(stripos($e->getMessage(),$fragment)===false)throw new RuntimeException("Expected '{$fragment}', got '{$e->getMessage()}'");return;}
    throw new RuntimeException('Expected rejection: '.$fragment);
}
$tests=[];
$tests['full cashier verified field cash posts balanced reclassification'] = function(){
    $g=new RemittanceFake;$r=(new EmployeeCashRemittance($g))->confirm(remitRequest());
    assert($r['status']==='posted' && $r['amount_paise']===20000 && $g->pending['status']==='settled');
    assert($g->journals[0][0]['account']==='BRANCH_CASH' && $g->journals[0][1]['account']==='EMPLOYEE_CASH_IN_TRANSIT');
    assert($g->journals[0][0]['debit_paise']===$g->journals[0][1]['credit_paise'] && $g->eventCount===1);
};
$tests['idempotent exact retry does not post twice'] = function(){
    $g=new RemittanceFake;$s=new EmployeeCashRemittance($g);$a=$s->confirm(remitRequest());$b=$s->confirm(remitRequest());
    assert($a['id']===$b['id'] && $g->eventCount===1 && count($g->journals)===1);
};
$tests['different request under same key denied'] = function(){
    $g=new RemittanceFake;$s=new EmployeeCashRemittance($g);$s->confirm(remitRequest());
    remitFailure('reused',fn()=>$s->confirm(remitRequest(['cash_receipt_reference'=>'BRANCH-CASH-002'])));
};
$tests['actor authorization verified on retry too'] = function(){
    $g=new RemittanceFake;$s=new EmployeeCashRemittance($g);$s->confirm(remitRequest());$g->allow=false;
    remitFailure('authority denied',fn()=>$s->confirm(remitRequest()));
};
$tests['cashier-only authority denied before any write'] = function(){
    $g=new RemittanceFake;$g->allow=false;remitFailure('authority denied',fn()=>(new EmployeeCashRemittance($g))->confirm(remitRequest()));assert($g->eventCount===0);
};
$tests['underpayment cannot finalize employee cash'] = function(){
    $g=new RemittanceFake;remitFailure('Full employee cash',fn()=>(new EmployeeCashRemittance($g))->confirm(remitRequest(['amount'=>'199.99'])));assert($g->eventCount===0);
};
$tests['overpayment cannot finalize employee cash'] = function(){
    $g=new RemittanceFake;remitFailure('Full employee cash',fn()=>(new EmployeeCashRemittance($g))->confirm(remitRequest(['amount'=>'200.01'])));assert($g->eventCount===0);
};
$tests['unverified receipt rejected'] = function(){
    $g=new RemittanceFake;$g->receiptConfirmed=false;remitFailure('not independently confirmed',fn()=>(new EmployeeCashRemittance($g))->confirm(remitRequest()));assert($g->pending['status']==='pending');
};
$tests['no cross branch access'] = function(){
    $g=new RemittanceFake;remitFailure('authority denied',fn()=>(new EmployeeCashRemittance($g))->confirm(remitRequest(['branch_id'=>2])));
};
$tests['employee cannot substitute another pending sale'] = function(){
    $g=new RemittanceFake;remitFailure('No pending field cash',fn()=>(new EmployeeCashRemittance($g))->confirm(remitRequest(['employee_id'=>7])));
};
$tests['counter/upi without remittance cannot be settled'] = function(){
    $g=new RemittanceFake;remitFailure('No pending field cash',fn()=>(new EmployeeCashRemittance($g))->confirm(remitRequest(['sale_id'=>12])));
};
$tests['zero amount denied'] = function(){
    $g=new RemittanceFake;remitFailure('exceed zero',fn()=>(new EmployeeCashRemittance($g))->confirm(remitRequest(['amount'=>'0'])));
};
$tests['unknown textual money denied'] = function(){
    $g=new RemittanceFake;remitFailure('Invalid money',fn()=>(new EmployeeCashRemittance($g))->confirm(remitRequest(['amount'=>'20.001'])));
};
$tests['simulated posting failure rolls back receipt and cash'] = function(){
    $g=new RemittanceFake;$g->failPosting=true;remitFailure('Simulated transaction failure',fn()=>(new EmployeeCashRemittance($g))->confirm(remitRequest()));
    assert($g->eventCount===0 && $g->pending['status']==='pending' && !$g->receipts && !$g->byKey);
};
$tests['duplicate remittance under new key cannot re-post'] = function(){
    $g=new RemittanceFake;$s=new EmployeeCashRemittance($g);$s->confirm(remitRequest());
    remitFailure('No pending field cash',fn()=>$s->confirm(remitRequest(['idempotency_key'=>'cash-remittance-002'])));
    assert($g->eventCount===1);
};
$tests['cannot settle stale partial state without approved policy'] = function(){
    $g=new RemittanceFake;$g->pending['amount_remitted_paise']=10000;
    remitFailure('partially posted',fn()=>(new EmployeeCashRemittance($g))->confirm(remitRequest()));
};
$tests['cashier API strips spoofed actor branch and fingerprint'] = function(){
    $g=new RemittanceFake;$api=new EmployeeRemittanceApi(new EmployeeCashRemittance($g));
    $response=$api->confirmBranchCash(1,1,2,remitRequest(['company_id'=>5,'branch_id'=>4,'actor_id'=>1000,'request_fingerprint'=>'forged']));
    assert($response['company_id']===1 && $response['branch_id']===1 && !isset($response['actor_id']) && !isset($response['request_fingerprint']));
    assert($g->pending['status']==='settled');
};
$tests['cashier API caller branch cannot be bypassed'] = function(){
    $g=new RemittanceFake;$api=new EmployeeRemittanceApi(new EmployeeCashRemittance($g));
    remitFailure('authority denied',fn()=>$api->confirmBranchCash(1,2,2,remitRequest(['branch_id'=>1])));
    assert($g->eventCount===0);
};
$i=0;foreach($tests as $name=>$fn){try{$fn();echo "PASS {$name}\n";$i++;}catch(Throwable $e){fwrite(STDERR,"FAIL {$name}: {$e->getMessage()}\n");exit(1);}}
echo "PASS {$i}/".count($tests)." remittance tests\n";
