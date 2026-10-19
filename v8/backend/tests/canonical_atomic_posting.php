<?php
declare(strict_types=1);

require dirname(__DIR__).'/src/B2B/RetailerCashSale.php';
require dirname(__DIR__).'/src/B2B/CanonicalPostingContract.php';

use ExcelHerbal\ERP8\B2B\{CanonicalPostingGateway,CanonicalPostingPlan,CanonicalRetailerAtomicPosting,RetailerSaleError};

function lockedAssessment(array $patch=[]): array
{
    return array_replace([
        'assessment'=>'canonical_read_model_validated','posting_allowed'=>true,
        'company_id'=>1,'branch_id'=>4,'channel'=>'field','employee_id'=>6,
        'business_date'=>'2026-10-19','payment_mode'=>'cash',
        'total_paise'=>30000,'paid_paise'=>30000,'cogs_paise'=>12038,
        'retailer_outstanding_paise'=>0,
        'canonical_account_ids'=>[
            'EMPLOYEE_CASH_IN_TRANSIT'=>25,'BRANCH_CASH'=>29,'UPI_CLEARING'=>33,
            'SALES'=>40,'COGS'=>50,'INVENTORY'=>60,
        ],
        'lines'=>[['product_id'=>11,'batch_id'=>7,'qty_pcs'=>3,
            'commercial_revision_id'=>99,'canonical_stock_custodian'=>6,
            'unit_price_paise'=>10000,'line_total_paise'=>30000,'cogs_paise'=>12038]],
    ],$patch);
}
function trustedRequest(array $patch=[]): array
{
    return array_replace(['company_id'=>1,'branch_id'=>4,'actor_id'=>8,'retailer_id'=>12,
        'channel'=>'field','employee_id'=>6,'business_at'=>'2026-10-19 10:30:00',
        'payment_mode'=>'cash','payment_reference'=>'CASH-TRUSTED-001',
        'paid_amount'=>'300.00','idempotency_key'=>'retailer-canonical-sale-001',
        'lines'=>[['product_id'=>11,'batch_id'=>7,'qty'=>3]]],$patch);
}
final class TransactionalCanonicalFake implements CanonicalPostingGateway
{
    public bool $release = true;
    public bool $allow = true;
    public int $partyId = 55;
    public bool $verified = true;
    public bool $failJournal = false;
    public bool $failFinalization = false;
    public bool $failStock = false;
    public bool $tamperReceipt = false;
    public array $locked;
    public array $events=[];
    public array $receipts=[];
    public array $source=[];
    public array $stock=[11=>10];
    public array $tenders=['CASH-TRUSTED-001'=>true,'UPI-TRUSTED-001'=>true];
    public array $journals=[];
    public function __construct(){$this->locked=lockedAssessment();}
    public function atomic(callable $work):array
    {
        $snapshot=[$this->events,$this->receipts,$this->source,$this->stock,$this->tenders,$this->journals];
        try {return $work();}
        catch(Throwable $e){[$this->events,$this->receipts,$this->source,$this->stock,$this->tenders,$this->journals]=$snapshot;throw $e;}
    }
    public function lockIdempotency(int $c,string $key):void{$this->events[]='lock-key';}
    public function findPostedByKey(int $c,string $key):?array{$this->events[]='find-key';return $this->receipts[$c.':'.$key]??null;}
    public function assertReleaseGates(int $c,int $b):void{
        $this->events[]='release';
        if(!$this->release)throw new RetailerSaleError('Production release gates remain disabled.');
    }
    public function assertAuthorizedRetailer(int $c,int $b,int $r,int $a):int{
        $this->events[]='retailer';
        if(!$this->allow || $c!==1 || $b!==4 || $r!==12 || $a!==8)throw new RetailerSaleError('Retailer scope denied.');
        return $this->partyId;
    }
    public function lockedAssessment(array $trustedRequest):array{$this->events[]='assess-under-lock';return $this->locked;}
    public function consumeVerifiedTender(int $c,int $b,string $mode,string $ref,int $amount):void{
        $this->events[]='consume-tender';
        if(!$this->verified || !isset($this->tenders[$ref]) || !$this->tenders[$ref] || $amount!==30000)
            throw new RetailerSaleError('Verified tender is unavailable or already consumed.');
        $this->tenders[$ref]=false;
    }
    public function createCanonicalSource(array $header,array $lines):int{
        $this->events[]='create-canonical-sale';$this->source[73]=['header'=>$header,'lines'=>$lines];return 73;
    }
    public function moveCanonicalStock(int $sourceId,array $line):void{
        $this->events[]='canonical-stock';
        if($this->failStock)throw new RetailerSaleError('Stock write failed.');
        $id=$line['product_id'];$qty=$line['qty_pcs'];if(($this->stock[$id]??0)<$qty)throw new RetailerSaleError('Not enough locked stock.');
        $this->stock[$id]-=$qty;
    }
    public function postCanonicalJournal(int $sourceId,array $journalLines,string $date):int{
        $this->events[]='canonical-journal';
        if($this->failJournal)throw new RetailerSaleError('Journal write failed.');
        $debits=array_sum(array_column($journalLines,'debit_paise'));
        $credits=array_sum(array_column($journalLines,'credit_paise'));
        if($debits!==$credits)throw new RetailerSaleError('Unbalanced canonical journal.');
        $this->journals[901]=$journalLines;return 901;
    }
    public function finalizeCanonicalSource(int $sourceId,int $journalId,array $record):array{
        $this->events[]='finalize';
        if($this->failFinalization)throw new RetailerSaleError('Finalize failed.');
        if($this->tamperReceipt)$record['journal_id']=0;
        $this->receipts[$record['company_id'].':'.$record['idempotency_key']]=$record;
        return $record;
    }
}
function fails(string $message,callable $fn):void{
    try {$fn();}catch(RetailerSaleError $e){
        if(stripos($e->getMessage(),$message)===false)throw new RuntimeException('Expected '.$message.' got '.$e->getMessage());
        return;
    }
    throw new RuntimeException('Expected rejection: '.$message);
}
$tests=[];
$tests['canonical plan maps V7 account IDs, not placeholder strings']=function(){
    $p=CanonicalPostingPlan::fromLockedAssessment(lockedAssessment());
    assert($p['journal_lines'][0]['account_id']===25);
    assert($p['journal_lines'][1]['account_id']===40);
    assert($p['journal_lines'][2]['account_id']===50);
    assert($p['journal_lines'][3]['account_id']===60);
    assert(array_sum(array_column($p['journal_lines'],'debit_paise'))===42038);
    assert($p['employee_cash_to_remit_paise']===30000 && $p['retailer_outstanding_paise']===0);
};
$tests['field UPI does not assign employee cash deposit']=function(){
    $p=CanonicalPostingPlan::fromLockedAssessment(lockedAssessment(['payment_mode'=>'upi']));
    assert($p['employee_cash_to_remit_paise']===0 && $p['journal_lines'][0]['account_id']===33);
};
$tests['counter cash uses branch cash with no employee custody']=function(){
    $a=lockedAssessment(['channel'=>'counter','employee_id'=>null]);
    $a['lines'][0]['canonical_stock_custodian']=0;
    $p=CanonicalPostingPlan::fromLockedAssessment($a);
    assert($p['journal_lines'][0]['account_id']===29 && $p['stock_movements'][0]['custodian_employee_id']===null);
};
$tests['must reject V7 read-only assessment as write permission']=function(){
    fails('remains disabled',fn()=>CanonicalPostingPlan::fromLockedAssessment(lockedAssessment(['posting_allowed'=>false])));
};
$tests['strictly reject forged posting status']=function(){
    fails('remains disabled',fn()=>CanonicalPostingPlan::fromLockedAssessment(lockedAssessment(['posting_allowed'=>'true'])));
};
$tests['reject payment smaller than invoice']=function(){
    fails('incomplete payment',fn()=>CanonicalPostingPlan::fromLockedAssessment(lockedAssessment(['paid_paise'=>29000])));
};
$tests['reject any retailer outstanding']=function(){
    fails('incomplete payment',fn()=>CanonicalPostingPlan::fromLockedAssessment(lockedAssessment(['retailer_outstanding_paise'=>1])));
};
$tests['reject wrong canonical custody']=function(){
    $a=lockedAssessment();$a['lines'][0]['canonical_stock_custodian']=0;
    fails('stock custody',fn()=>CanonicalPostingPlan::fromLockedAssessment($a));
};
$tests['reject duplicate canonical stock lines']=function(){
    $a=lockedAssessment();$a['lines'][]=$a['lines'][0];
    fails('Duplicate canonical',fn()=>CanonicalPostingPlan::fromLockedAssessment($a));
};
$tests['reject unit price and line multiplication mismatch']=function(){
    $a=lockedAssessment();$a['lines'][0]['line_total_paise']=29000;
    fails('amount mismatch',fn()=>CanonicalPostingPlan::fromLockedAssessment($a));
};
$tests['reject line cost and header cost mismatch']=function(){
    $a=lockedAssessment(['cogs_paise'=>12037]);
    fails('line sums differ',fn()=>CanonicalPostingPlan::fromLockedAssessment($a));
};
$tests['reject accounts with shared debit and credit id']=function(){
    $a=lockedAssessment();$a['canonical_account_ids']['COGS']=40;
    fails('distinct',fn()=>CanonicalPostingPlan::fromLockedAssessment($a));
};
$tests['zero cost creates balanced two-line financial posting']=function(){
    $a=lockedAssessment(['cogs_paise'=>0]);$a['lines'][0]['cogs_paise']=0;
    $p=CanonicalPostingPlan::fromLockedAssessment($a);
    assert(count($p['journal_lines'])===2);
};
$tests['reject unsupported credit and split tender']=function(){
    fails('Cash/UPI',fn()=>CanonicalPostingPlan::fromLockedAssessment(lockedAssessment(['payment_mode'=>'credit'])));
    fails('Cash/UPI',fn()=>CanonicalPostingPlan::fromLockedAssessment(lockedAssessment(['payment_mode'=>'cash+upi'])));
};
$tests['reject invalid stock unit or commercial revision']=function(){
    $a=lockedAssessment();$a['lines'][0]['qty_pcs']=0;
    fails('Invalid canonical product',fn()=>CanonicalPostingPlan::fromLockedAssessment($a));
    $a=lockedAssessment();$a['lines'][0]['commercial_revision_id']=0;
    fails('Invalid canonical product',fn()=>CanonicalPostingPlan::fromLockedAssessment($a));
};
$tests['atomic posting commits source, stock, tender and GL once']=function(){
    $g=new TransactionalCanonicalFake;$r=(new CanonicalRetailerAtomicPosting($g))->post(trustedRequest());
    assert($r['status']==='posted' && $r['sale_id']===73 && $r['journal_id']===901);
    assert($g->stock[11]===7 && $g->tenders['CASH-TRUSTED-001']===false);
    assert($g->events===['lock-key','find-key','release','retailer','assess-under-lock','consume-tender','create-canonical-sale','canonical-stock','canonical-journal','finalize']);
};
$tests['sale source binds to canonical V7 customer party, never a shadow customer']=function(){
    $g=new TransactionalCanonicalFake;
    (new CanonicalRetailerAtomicPosting($g))->post(trustedRequest());
    assert($g->source[73]['header']['canonical_party_id']===55);
    assert($g->source[73]['header']['retailer_id']===12);
    assert($g->source[73]['header']['outstanding_paise']===0);
    assert(!in_array('AR',array_column($g->journals[901],'account_id'),true));
};
$tests['retailer link without canonical customer party blocks posting']=function(){
    $g=new TransactionalCanonicalFake;$g->partyId=0;
    fails('valid customer party',fn()=>(new CanonicalRetailerAtomicPosting($g))->post(trustedRequest()));
    assert($g->stock[11]===10 && $g->tenders['CASH-TRUSTED-001']===true && !$g->source);
};
$tests['idempotency returns exact receipt with no second deduction']=function(){
    $g=new TransactionalCanonicalFake;$s=new CanonicalRetailerAtomicPosting($g);
    $a=$s->post(trustedRequest());$b=$s->post(trustedRequest());
    assert($a===$b && $g->stock[11]===7 && count($g->journals)===1 && count($g->source)===1);
};
$tests['idempotency rejects different reference with same key']=function(){
    $g=new TransactionalCanonicalFake;$s=new CanonicalRetailerAtomicPosting($g);$s->post(trustedRequest());
    fails('reused',fn()=>$s->post(trustedRequest(['payment_reference'=>'CASH-NEW-002'])));
    assert($g->stock[11]===7 && count($g->journals)===1);
};
$tests['blocked release gate cannot consume tender or stock']=function(){
    $g=new TransactionalCanonicalFake;$g->release=false;
    fails('release gates',fn()=>(new CanonicalRetailerAtomicPosting($g))->post(trustedRequest()));
    assert($g->stock[11]===10 && $g->tenders['CASH-TRUSTED-001']===true && !$g->source);
};
$tests['denied retailer/actor branch cannot post']=function(){
    $g=new TransactionalCanonicalFake;$g->allow=false;
    fails('scope denied',fn()=>(new CanonicalRetailerAtomicPosting($g))->post(trustedRequest()));
    assert($g->stock[11]===10 && !$g->journals);
};
$tests['read-only preflight cannot be turned into production writer']=function(){
    $g=new TransactionalCanonicalFake;$g->locked['posting_allowed']=false;
    fails('remains disabled',fn()=>(new CanonicalRetailerAtomicPosting($g))->post(trustedRequest()));
    assert($g->tenders['CASH-TRUSTED-001']===true);
};
$tests['full amount mismatch at trusted edge denies transaction']=function(){
    $g=new TransactionalCanonicalFake;
    fails('differs from trusted',fn()=>(new CanonicalRetailerAtomicPosting($g))->post(trustedRequest(['paid_amount'=>'100.00'])));
    assert($g->stock[11]===10);
};
$tests['unverified tender blocks all writes']=function(){
    $g=new TransactionalCanonicalFake;$g->verified=false;
    fails('Verified tender',fn()=>(new CanonicalRetailerAtomicPosting($g))->post(trustedRequest()));
    assert($g->stock[11]===10 && !$g->source && !$g->journals);
};
$tests['reused tender under different sale key is denied']=function(){
    $g=new TransactionalCanonicalFake;$s=new CanonicalRetailerAtomicPosting($g);$s->post(trustedRequest());
    fails('already consumed',fn()=>$s->post(trustedRequest(['idempotency_key'=>'retailer-canonical-sale-002'])));
    assert($g->stock[11]===7 && count($g->source)===1);
};
$tests['stock posting failure rolls back tender and source']=function(){
    $g=new TransactionalCanonicalFake;$g->failStock=true;
    fails('Stock write failed',fn()=>(new CanonicalRetailerAtomicPosting($g))->post(trustedRequest()));
    assert($g->stock[11]===10 && $g->tenders['CASH-TRUSTED-001']===true && !$g->source);
};
$tests['journal failure rolls back tender, stock and sale']=function(){
    $g=new TransactionalCanonicalFake;$g->failJournal=true;
    fails('Journal write failed',fn()=>(new CanonicalRetailerAtomicPosting($g))->post(trustedRequest()));
    assert($g->stock[11]===10 && $g->tenders['CASH-TRUSTED-001']===true && !$g->source && !$g->journals);
};
$tests['finalization failure rolls back tender, stock and journal']=function(){
    $g=new TransactionalCanonicalFake;$g->failFinalization=true;
    fails('Finalize failed',fn()=>(new CanonicalRetailerAtomicPosting($g))->post(trustedRequest()));
    assert($g->stock[11]===10 && $g->tenders['CASH-TRUSTED-001']===true && !$g->source && !$g->journals);
};
$tests['tampered receipt rolls back entire posting']=function(){
    $g=new TransactionalCanonicalFake;$g->tamperReceipt=true;
    fails('receipt integrity',fn()=>(new CanonicalRetailerAtomicPosting($g))->post(trustedRequest()));
    assert($g->stock[11]===10 && $g->tenders['CASH-TRUSTED-001']===true && !$g->receipts);
};
$tests['untrusted session identifiers are rejected']=function(){
    $g=new TransactionalCanonicalFake;
    fails('Trusted posting',fn()=>(new CanonicalRetailerAtomicPosting($g))->post(trustedRequest(['actor_id'=>'8'])));
    fails('Trusted posting',fn()=>(new CanonicalRetailerAtomicPosting($g))->post(trustedRequest(['company_id'=>-1])));
};
$tests['client tender confirmed flag alone never unlocks payment']=function(){
    $g=new TransactionalCanonicalFake;$g->verified=false;
    fails('Verified tender',fn()=>(new CanonicalRetailerAtomicPosting($g))->post(trustedRequest(['payment_confirmed'=>true])));
    assert($g->stock[11]===10);
};
$tests['wrong channel or employee from locked plan denies posting']=function(){
    $g=new TransactionalCanonicalFake;
    fails('differs from trusted',fn()=>(new CanonicalRetailerAtomicPosting($g))->post(trustedRequest(['channel'=>'counter','employee_id'=>null])));
};
$tests['counter UPI uses correct ledger and no employee responsibility']=function(){
    $g=new TransactionalCanonicalFake;$a=lockedAssessment(['channel'=>'counter','employee_id'=>null,'payment_mode'=>'upi']);
    $a['lines'][0]['canonical_stock_custodian']=0;$g->locked=$a;
    $s=(new CanonicalRetailerAtomicPosting($g))->post(trustedRequest(['channel'=>'counter','employee_id'=>null,
        'payment_mode'=>'upi','payment_reference'=>'UPI-TRUSTED-001']));
    assert($s['employee_cash_to_remit_paise']===0 && $g->journals[901][0]['account_id']===33);
};
$ok=0;foreach($tests as $name=>$fn){
    try{$fn();$ok++;echo "PASS {$name}\n";}
    catch(Throwable $e){fwrite(STDERR,"FAIL {$name}: {$e->getMessage()}\n");exit(1);}
}
echo "PASS {$ok}/".count($tests)." canonical atomic posting contract tests\n";
