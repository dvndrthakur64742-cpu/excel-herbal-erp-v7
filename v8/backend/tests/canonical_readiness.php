<?php
declare(strict_types=1);
require dirname(__DIR__) . '/src/B2B/RetailerCashSale.php';
require dirname(__DIR__) . '/src/B2B/CanonicalV7Readiness.php';
require dirname(__DIR__) . '/src/B2B/WpV7CanonicalReader.php';
use ExcelHerbal\ERP8\B2B\{RetailerSaleError,V7CanonicalReader,CanonicalV7Readiness,WpV7CanonicalReader};

class InMemoryV7Reader implements V7CanonicalReader
{
    public bool $authorized=true, $closedPeriod=false, $closedBranch=false;
    public array $branches=[1=>['status'=>'active']];
    public array $employees=[6=>['status'=>'active']];
    public array $products=[1=>['status'=>'active','uom'=>'PCS','batch_tracking'=>'optional','expiry_tracking'=>0]];
    public array $commercials=[1=>['id'=>77,'status'=>'active','mrp'=>'150.00','sale_price'=>'100.00','ho_amount'=>'50.00','bm_profit'=>'20.00','salary_fund'=>'20.00','office_expense'=>'10.00','purchase_cost'=>'40.0000']];
    public array $batches=[7=>['status'=>'active','expires_on'=>'2027-01-01']];
    public array $stock=['1:0:0'=>['quantity'=>'10.000','average_unit_cost'=>'42.1250'],'1:7:0'=>['quantity'=>'8.000','average_unit_cost'=>'50.0000'],'1:0:6'=>['quantity'=>'5.000','average_unit_cost'=>'43.5000']];
    public array $accounts=[
        'SALES'=>['id'=>101,'active'=>1,'type'=>'income'],
        'COGS'=>['id'=>102,'active'=>1,'type'=>'expense'],
        'INVENTORY'=>['id'=>103,'active'=>1,'type'=>'asset'],
        'BRANCH_CASH'=>['id'=>104,'active'=>1,'type'=>'asset'],
        'UPI_CLEARING'=>['id'=>105,'active'=>1,'type'=>'asset'],
        'EMPLOYEE_CASH_IN_TRANSIT'=>['id'=>106,'active'=>1,'type'=>'asset'],
    ];
    public function canInspect(int $actorId,int $companyId,int $branchId,string $channel,?int $employeeId):bool {return $this->authorized && $actorId===2 && $companyId===1 && $branchId===1;}
    public function branch(int $companyId,int $branchId):?array {return $this->branches[$branchId]??null;}
    public function employee(int $companyId,int $employeeId):?array {return $this->employees[$employeeId]??null;}
    public function closedAccountingPeriod(int $companyId,string $businessDate):bool {return $this->closedPeriod;}
    public function closedBranchDay(int $companyId,int $branchId,string $businessDate):bool {return $this->closedBranch;}
    public function product(int $companyId,int $productId):?array {return $this->products[$productId]??null;}
    public function commercial(int $companyId,int $productId,string $businessAt):?array {return $this->commercials[$productId]??null;}
    public function batch(int $companyId,int $productId,int $batchId):?array {return $this->batches[$batchId]??null;}
    public function stockBucket(int $companyId,int $branchId,int $productId,int $batchId,int $custodianKey):?array {return $this->stock[$productId.':'.$batchId.':'.$custodianKey]??null;}
    public function accountByCode(int $companyId,string $code):?array {return $this->accounts[$code]??null;}
}
function preflight(array $patch=[]):array {return array_replace(['company_id'=>1,'branch_id'=>1,'actor_id'=>2,'business_at'=>'2026-10-19 11:00:00','channel'=>'counter','employee_id'=>null,'payment_mode'=>'cash','paid_amount'=>'300.00','lines'=>[['product_id'=>1,'batch_id'=>0,'qty'=>3]]],$patch);}
function rejected(string $message,callable $f):void {try{$f();}catch(RetailerSaleError $e){if(stripos($e->getMessage(),$message)===false)throw $e;return;}throw new \RuntimeException('Expected rejection: '.$message);}
$tests=[];
$tests['canonical counter preview uses V7 moving-average stock cost not purchase cost']=function(){$g=new InMemoryV7Reader;$r=(new CanonicalV7Readiness($g))->assess(preflight());assert($r['total_paise']===30000 && $r['cogs_paise']===12638 && $r['lines'][0]['commercial_revision_id']===77);assert($r['retailer_outstanding_paise']===0 && $r['posting_allowed']===false && count($r['posting_blockers'])>=5);};
$tests['field cash maps stock custody and transit account']=function(){$g=new InMemoryV7Reader;$r=(new CanonicalV7Readiness($g))->assess(preflight(['channel'=>'field','employee_id'=>6,'paid_amount'=>'200.00','lines'=>[['product_id'=>1,'batch_id'=>0,'qty'=>2]]]));assert($r['canonical_account_ids']['EMPLOYEE_CASH_IN_TRANSIT']===106 && $r['cogs_paise']===8700 && $r['lines'][0]['canonical_stock_custodian']===6);};
$tests['UPI maps its own ledger not cash']=function(){$g=new InMemoryV7Reader;$r=(new CanonicalV7Readiness($g))->assess(preflight(['payment_mode'=>'upi']));assert($r['canonical_account_ids']['UPI_CLEARING']===105 && !isset($r['canonical_account_ids']['BRANCH_CASH']));};
$tests['blocks unapproved credit and mixed payment']=function(){rejected('Cash OR UPI',fn()=>(new CanonicalV7Readiness(new InMemoryV7Reader))->assess(preflight(['payment_mode'=>'credit'])));rejected('Cash OR UPI',fn()=>(new CanonicalV7Readiness(new InMemoryV7Reader))->assess(preflight(['payment_mode'=>'cash+upi'])));};
$tests['blocks underpayment and overpayment']=function(){rejected('full Cash/UPI',fn()=>(new CanonicalV7Readiness(new InMemoryV7Reader))->assess(preflight(['paid_amount'=>'299.99'])));rejected('full Cash/UPI',fn()=>(new CanonicalV7Readiness(new InMemoryV7Reader))->assess(preflight(['paid_amount'=>'300.01'])));};
$tests['blocks unauthorized company/branch scope']=function(){$g=new InMemoryV7Reader;$g->authorized=false;rejected('No authorized',fn()=>(new CanonicalV7Readiness($g))->assess(preflight()));};
$tests['blocks closed accounting period']=function(){$g=new InMemoryV7Reader;$g->closedPeriod=true;rejected('period is closed',fn()=>(new CanonicalV7Readiness($g))->assess(preflight()));};
$tests['blocks closed branch day']=function(){$g=new InMemoryV7Reader;$g->closedBranch=true;rejected('business day is closed',fn()=>(new CanonicalV7Readiness($g))->assess(preflight()));};
$tests['blocks wrong company branch and inactive branch']=function(){$g=new InMemoryV7Reader;$g->branches=[];rejected('active branch',fn()=>(new CanonicalV7Readiness($g))->assess(preflight()));};
$tests['blocks inactive employee custodian']=function(){$g=new InMemoryV7Reader;$g->employees[6]['status']='inactive';rejected('Active employee',fn()=>(new CanonicalV7Readiness($g))->assess(preflight(['channel'=>'field','employee_id'=>6])));};
$tests['blocks employee custody mismatch']=function(){$g=new InMemoryV7Reader;$g->stock['1:0:6']['quantity']='1.000';rejected('Insufficient canonical stock',fn()=>(new CanonicalV7Readiness($g))->assess(preflight(['channel'=>'field','employee_id'=>6])));};
$tests['blocks fractional legacy PCS balances']=function(){$g=new InMemoryV7Reader;$g->stock['1:0:0']['quantity']='10.500';rejected('Fractional PCS',fn()=>(new CanonicalV7Readiness($g))->assess(preflight()));};
$tests['blocks missing or misconfigured COGS account']=function(){$g=new InMemoryV7Reader;unset($g->accounts['COGS']);rejected('COGS',fn()=>(new CanonicalV7Readiness($g))->assess(preflight()));};
$tests['blocks wrong account type']=function(){$g=new InMemoryV7Reader;$g->accounts['BRANCH_CASH']['type']='income';rejected('BRANCH_CASH',fn()=>(new CanonicalV7Readiness($g))->assess(preflight()));};
$tests['blocks expired batches']=function(){$g=new InMemoryV7Reader;$g->products[1]['batch_tracking']='required';$g->batches[7]['expires_on']='2026-10-18';rejected('Expired stock',fn()=>(new CanonicalV7Readiness($g))->assess(preflight(['lines'=>[['product_id'=>1,'batch_id'=>7,'qty'=>3]]])));};
$tests['blocks batch required product without batch']=function(){$g=new InMemoryV7Reader;$g->products[1]['batch_tracking']='required';rejected('requires a batch',fn()=>(new CanonicalV7Readiness($g))->assess(preflight()));};
$tests['blocks expiry tracked product with missing expiry']=function(){$g=new InMemoryV7Reader;$g->products[1]['expiry_tracking']=1;$g->batches[7]['expires_on']=null;rejected('expiry date',fn()=>(new CanonicalV7Readiness($g))->assess(preflight(['lines'=>[['product_id'=>1,'batch_id'=>7,'qty'=>3]]])));};
$tests['blocks inconsistent price allocation']=function(){$g=new InMemoryV7Reader;$g->commercials[1]['salary_fund']='10.00';rejected('distribution mismatch',fn()=>(new CanonicalV7Readiness($g))->assess(preflight()));};
$tests['blocks missing current valuation even if purchase cost available']=function(){$g=new InMemoryV7Reader;$g->stock['1:0:0']['average_unit_cost']='0.0000';rejected('average unit cost',fn()=>(new CanonicalV7Readiness($g))->assess(preflight()));};
$tests['blocks unavailable effective commercial']=function(){$g=new InMemoryV7Reader;$g->commercials=[];rejected('commercial revision',fn()=>(new CanonicalV7Readiness($g))->assess(preflight()));};
$tests['blocks duplicate source product/batch']=function(){rejected('Duplicate product',fn()=>(new CanonicalV7Readiness(new InMemoryV7Reader))->assess(preflight(['paid_amount'=>'600.00','lines'=>[['product_id'=>1,'batch_id'=>0,'qty'=>3],['product_id'=>1,'batch_id'=>0,'qty'=>3]]])));};
$tests['validates business datetime independently']=function(){rejected('Invalid business datetime',fn()=>(new CanonicalV7Readiness(new InMemoryV7Reader))->assess(preflight(['business_at'=>'2026-02-30 11:00:00'])));};
$tests['never accepts client-supplied mixed or split tender']=function(){rejected('Cash OR UPI',fn()=>(new CanonicalV7Readiness(new InMemoryV7Reader))->assess(preflight(['payment_mode'=>['cash','upi']])));};
$tests['read-only WordPress adapter requires authorization callback']=function(){rejected('authorization callback',fn()=>new WpV7CanonicalReader((object)['prefix'=>'wp_'],null));};
$tests['read-only WordPress adapter validates safe table prefix']=function(){rejected('Unsafe WordPress',fn()=>new WpV7CanonicalReader((object)['prefix'=>'wp_;DROP'],fn()=>true));};
$tests['read-only WordPress adapter queries canonical V7 tables and effective revision']=function(){
 $wpdb=new class {
     public string $prefix='wp_', $last_error='';
     public array $queries=[];
     public function prepare(string $sql,...$params):string {$this->queries[]=['sql'=>$sql,'params'=>$params];return $sql;}
     public function get_row(string $sql,string $format):?array{return ['id'=>77,'status'=>'active'];}
 };
 $g=new WpV7CanonicalReader($wpdb,fn(int $actor,int $company,int $branch,string $channel,?int $emp)=>$actor===2&&$company===1&&$branch===1);
 assert($g->canInspect(2,1,1,'counter',null)===true && $g->canInspect(2,1,2,'counter',null)===false);
 $g->commercial(1,10,'2026-10-19 10:30:00');$g->stockBucket(1,2,10,7,6);$g->accountByCode(1,'COGS');
 assert(count($wpdb->queries)===3);
 assert(str_contains($wpdb->queries[0]['sql'],'wp_eh7_product_commercial_revisions')&&str_contains($wpdb->queries[0]['sql'],'effective_from<=%s'));
 assert(str_contains($wpdb->queries[1]['sql'],'wp_eh7_stock_balances')&&str_contains($wpdb->queries[1]['sql'],'custodian_key=%d'));
 assert(str_contains($wpdb->queries[2]['sql'],'wp_eh7_accounts'));
};
$tests['read-only WordPress adapter fails closed on DB error']=function(){
 $wpdb=new class {
     public string $prefix='wp_', $last_error='Simulated read failure';
     public function prepare(string $sql,...$params):string {return $sql;}
     public function get_row(string $sql,string $format):?array {return null;}
 };
 $g=new WpV7CanonicalReader($wpdb,fn()=>true);
 rejected('query failed',fn()=>$g->branch(1,1));
};
$tests['read-only WordPress adapter cannot mutate any canonical table']=function(){
 $wpdb=new class {
     public string $prefix='wp_', $last_error='';
     public int $readCount=0;
     public function prepare(string $sql,...$params):string {if (!str_starts_with($sql,'SELECT '))throw new \RuntimeException('Unexpected write');return $sql;}
     public function get_row(string $sql,string $format):?array {$this->readCount++;return null;}
     public function query(string $sql):never {throw new \RuntimeException('Unexpected mutating SQL');}
 };
 $g=new WpV7CanonicalReader($wpdb,fn()=>true);
 $g->branch(1,1);$g->employee(1,6);$g->product(1,2);$g->commercial(1,2,'2026-10-19 11:00:00');
 $g->stockBucket(1,1,2,0,0);$g->batch(1,2,7);$g->accountByCode(1,'SALES');
 $g->closedBranchDay(1,1,'2026-10-19');$g->closedAccountingPeriod(1,'2026-10-19');
 assert($wpdb->readCount===9);
};
$i=0;foreach($tests as $name=>$test){try{$test();echo "PASS {$name}\n";$i++;}catch(Throwable $e){fwrite(STDERR,"FAIL {$name}: {$e->getMessage()}\n");exit(1);}}echo "PASS {$i}/".count($tests)." canonical integration preflight tests\n";
