<?php
declare(strict_types=1);

require_once __DIR__.'/../src/B2B/RetailerCashSale.php';
require_once __DIR__.'/../src/B2B/CanonicalRetailerIdentity.php';
require_once __DIR__.'/../src/B2B/CanonicalV7Readiness.php';
require_once __DIR__.'/../src/B2B/CanonicalRetailerCheckoutPreview.php';

use ExcelHerbal\ERP8\B2B\{CanonicalRetailerIdentity,CanonicalRetailerIdentityReader,CanonicalRetailerCheckoutPreview,CanonicalV7Readiness,RetailerSaleError,V7CanonicalReader};

final class CheckoutFixtures implements CanonicalRetailerIdentityReader, V7CanonicalReader
{
    public bool $auth=true, $closed=false;
    public string $receivable='0.00', $stockQty='5.000', $unitPrice='100.00';
    public int $reads=0;
    public array $party=['retailer_id'=>9,'party_id'=>12,'company_id'=>1,'branch_id'=>2,'link_status'=>'active','party_status'=>'active','party_type'=>'customer','shop_name'=>'Sample Retailer'];
    public function canInspectRetailer(int $a,int $c,int $b):bool{return $this->auth && $a===7 && $c===1 && $b===2;}
    public function retailerParty(int $c,int $b,int $id):?array{$this->reads++;return $this->party;}
    public function openCustomerReceivables(int $c,int $b,int $p):string{$this->reads++;return $this->receivable;}
    public function canInspect(int $a,int $c,int $b,string $channel,?int $e):bool{return $this->auth && $a===7 && $c===1 && $b===2;}
    public function branch(int $c,int $b):?array{$this->reads++;return ['status'=>'active'];}
    public function employee(int $c,int $e):?array{$this->reads++;return ['status'=>'active'];}
    public function closedAccountingPeriod(int $c,string $d):bool{$this->reads++;return $this->closed;}
    public function closedBranchDay(int $c,int $b,string $d):bool{$this->reads++;return false;}
    public function product(int $c,int $id):?array{$this->reads++;return ['status'=>'active','uom'=>'PCS','batch_tracking'=>'optional','expiry_tracking'=>0];}
    public function commercial(int $c,int $id,string $at):?array{
        $this->reads++;return ['id'=>88,'status'=>'active','mrp'=>'150.00','sale_price'=>$this->unitPrice,
            'ho_amount'=>'50.00','bm_profit'=>'20.00','salary_fund'=>'20.00','office_expense'=>'10.00','purchase_cost'=>'35.0000'];
    }
    public function batch(int $c,int $pid,int $bid):?array{$this->reads++;return ['status'=>'active','expires_on'=>'2027-01-01'];}
    public function stockBucket(int $c,int $b,int $pid,int $bid,int $custodian):?array{
        $this->reads++;return ['quantity'=>$this->stockQty,'average_unit_cost'=>'42.0000'];
    }
    public function accountByCode(int $c,string $code):?array{
        $this->reads++;$t=['SALES'=>'income','COGS'=>'expense','INVENTORY'=>'asset','BRANCH_CASH'=>'asset',
            'EMPLOYEE_CASH_IN_TRANSIT'=>'asset','UPI_CLEARING'=>'asset'];
        return isset($t[$code])?['id'=>array_search($code,array_keys($t),true)+101,'active'=>1,'type'=>$t[$code]]:null;
    }
}
function previewRequest(array $delta=[]):array{return array_replace([
    'company_id'=>1,'branch_id'=>2,'actor_id'=>7,'retailer_id'=>9,
    'business_at'=>'2026-10-19 11:30:00','channel'=>'counter','employee_id'=>null,
    'payment_mode'=>'cash','paid_amount'=>'200.00',
    'lines'=>[['product_id'=>3,'batch_id'=>0,'qty'=>2]]],$delta);}
function checkout(CheckoutFixtures $f,array $request=[]):array{
    return (new CanonicalRetailerCheckoutPreview(new CanonicalRetailerIdentity($f),new CanonicalV7Readiness($f)))
        ->compose(previewRequest($request));
}
function failPreview(CheckoutFixtures $f,array $request=[],string $msg=''):void{
    try{checkout($f,$request);}catch(RetailerSaleError $e){if($msg!==''&&!str_contains($e->getMessage(),$msg))throw $e;return;}
    throw new RuntimeException('Expected preview rejection: '.$msg);
}
$tests=[];
$tests['retailer party and canonical stock form one nonposting checkout']=static function():void{
    $r=checkout(new CheckoutFixtures);
    assert($r['canonical_party_id']===12 && $r['retailer_id']===9 && $r['gross_paise']===20000);
    assert($r['credit_allowed']===false&&$r['posting_allowed']===false&&$r['stock_reserved']===false);
    assert($r['tax_invoice_status']==='policy_not_approved' && $r['payment_verification_status']==='not_verified_by_preview');
};
$tests['valid snapshot is deterministic']=static function():void{
    $a=checkout(new CheckoutFixtures);$b=checkout(new CheckoutFixtures);
    assert($a['preview_digest']===$b['preview_digest']&&preg_match('/^[0-9a-f]{64}$/',$a['preview_digest']));
};
$tests['changed purchased quantity changes digest']=static function():void{
    $a=checkout(new CheckoutFixtures);$b=checkout(new CheckoutFixtures,['paid_amount'=>'100.00','lines'=>[['product_id'=>3,'batch_id'=>0,'qty'=>1]]]);
    assert($a['preview_digest']!==$b['preview_digest']);
};
$tests['changed business datetime changes digest']=static function():void{
    $a=checkout(new CheckoutFixtures);$b=checkout(new CheckoutFixtures,['business_at'=>'2026-10-19 11:35:00']);
    assert($a['preview_digest']!==$b['preview_digest']);
};
$tests['different trusted channel and custodian changes digest']=static function():void{
    $a=checkout(new CheckoutFixtures);
    $b=checkout(new CheckoutFixtures,['channel'=>'field','employee_id'=>7]);
    assert($a['preview_digest']!==$b['preview_digest']);
};
$tests['unauthorized actor cannot read identity or stock']=static function():void{$f=new CheckoutFixtures;$f->auth=false;failPreview($f,[],'access denied');assert($f->reads===0);};
$tests['wrong branch cannot reuse another retailer identity']=static function():void{failPreview(new CheckoutFixtures,['branch_id'=>3],'access denied');};
$tests['unlinked customer cannot quote']=static function():void{$f=new CheckoutFixtures;$f->party['link_status']='inactive';failPreview($f,[],'both be active');};
$tests['existing customer receivable blocks new Cash-only sale']=static function():void{$f=new CheckoutFixtures;$f->receivable='0.01';failPreview($f,[],'Existing customer credit');};
$tests['closed accounting period blocks checkout']=static function():void{$f=new CheckoutFixtures;$f->closed=true;failPreview($f,[],'period is closed');};
$tests['insufficient canonical stock blocks checkout']=static function():void{$f=new CheckoutFixtures;$f->stockQty='1.000';failPreview($f,[],'Insufficient canonical stock');};
$tests['changed approved price without matching allocation blocks checkout']=static function():void{$f=new CheckoutFixtures;$f->unitPrice='90.00';failPreview($f,[],'commercial distribution');};
$tests['payment total cannot be less than current priced stock']=static function():void{failPreview(new CheckoutFixtures,['paid_amount'=>'199.99'],'full Cash/UPI');};
$tests['partial UPI and Cash mixed in one sale remains unapproved']=static function():void{failPreview(new CheckoutFixtures,['payment_mode'=>'cash+upi'],'Cash OR UPI');};
$tests['field employee custody uses the same canonical read model']=static function():void{
    $r=checkout(new CheckoutFixtures,['channel'=>'field','employee_id'=>7]);
    assert($r['channel']==='field' && $r['employee_id']===7 && $r['posting_allowed']===false);
};
$tests['quote never leaks COGS, GL account ids or salary distribution']=static function():void{
    $r=checkout(new CheckoutFixtures);$json=json_encode($r,JSON_THROW_ON_ERROR);
    assert(!str_contains($json,'cogs_paise')&&!str_contains($json,'canonical_account_ids'));
    assert(!str_contains($json,'salary_fund')&&!str_contains($json,'purchase_cost'));
};
$tests['quote never claims posted journal invoice receipt or stock movement']=static function():void{
    $r=checkout(new CheckoutFixtures);foreach(['invoice_id','journal_id','stock_ledger_id','payment_receipt_id','payment_verified','posted'] as $key)
        assert(!array_key_exists($key,$r));
    assert($r['release_status']==='preview_only'&&$r['requires_locked_revalidation']===true);
};
$i=0;
foreach($tests as $label=>$test){try{$test();echo "PASS $label\n";$i++;}catch(Throwable $e){fwrite(STDERR,"FAIL $label: ".$e->getMessage()."\n");exit(1);}}
echo "PASS $i/".count($tests)." canonical retailer checkout preview tests\n";
