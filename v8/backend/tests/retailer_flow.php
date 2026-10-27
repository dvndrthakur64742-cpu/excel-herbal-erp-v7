<?php
declare(strict_types=1);
require dirname(__DIR__) . '/src/B2B/RetailerCashSale.php';
require dirname(__DIR__) . '/src/B2B/RetailerMaster.php';
require dirname(__DIR__) . '/src/B2B/RetailerApi.php';
use ExcelHerbal\ERP8\B2B\{RetailerSaleError,RetailerMaster,RetailerMasterGateway,RetailerApi,RetailerCashSale,RetailerSaleGateway};

final class MemoryRetailerStore implements RetailerMasterGateway, RetailerSaleGateway {
    public array $rows = [];
    public array $sales = [];
    public array $stock = [0=>7, 6=>3];
    public bool $authorized = true;
    public bool $tenderVerified = true;
    public function atomic(callable $fn): array { $backup=[$this->rows,$this->sales,$this->stock];try{return $fn();}catch(Throwable $e){[$this->rows,$this->sales,$this->stock]=$backup;throw $e;} }
    public function canManage(int $actorId,int $companyId,int $branchId):bool {return $this->authorized && $companyId===1 && $branchId===1 && $actorId===2;}
    public function canSell(int $actorId,int $companyId,int $branchId,string $channel,?int $employeeId):bool {return $this->canManage($actorId,$companyId,$branchId);}
    public function findByKey(int $companyId,int $branchId,string $key):?array {return $this->rows[$companyId.':'.$branchId.':'.$key]??null;}
    public function create(array $record):array { $record['id']=count($this->rows)+1;$this->rows[$record['company_id'].':'.$record['branch_id'].':'.$record['idempotency_key']]=$record;return $record; }
    public function get(int $companyId,int $branchId,int $retailerId):?array {foreach($this->rows as $r)if($r['id']===$retailerId && $r['company_id']===$companyId && $r['branch_id']===$branchId)return $r;return null;}
    public function list(int $companyId,int $branchId,int $limit=100):array {return array_values(array_filter($this->rows,fn($r)=>$r['company_id']===$companyId&&$r['branch_id']===$branchId));}
    public function retailer(int $companyId,int $branchId,int $retailerId):?array{return $this->get($companyId,$branchId,$retailerId);}
    public function lockIdempotency(int $companyId,string $key):void {}
    public function findByIdempotency(int $companyId,string $key):?array{return $this->sales[$companyId.':'.$key]??null;}
    public function product(int $companyId,int $branchId,int $productId):?array{return ['status'=>'active','mrp'=>'110.00','sale_price'=>'100.00','ho_amount'=>'50.00','bm_profit'=>'20.00','salary_fund'=>'20.00','office_expense'=>'10.00','purchase_cost'=>'40.0000','points'=>'4','batch_required'=>false];}
    public function availablePcs(int $companyId,int $branchId,int $productId,int $batchId,?int $custodianId):int{return $this->stock[$custodianId??0]??0;}
    public function confirmedTender(int $companyId,int $branchId,string $mode,string $reference,int $amountPaise):bool{return $this->tenderVerified;}
    public function record(array $sale,array $stockMoves,array $journalLines):array {foreach($stockMoves as $m){$key=$m['custodian_id']??0;$this->stock[$key]+=$m['quantity_delta'];}$sale['id']=count($this->sales)+1;$this->sales[$sale['company_id'].':'.$sale['idempotency_key']]=$sale;return $sale;}
}
function assertFailure(string $part,callable $fn):void {try{$fn();}catch(RetailerSaleError $e){if(stripos($e->getMessage(),$part)===false)throw $e;return;}throw new RuntimeException('Expected rejection: '.$part);}
$tests=[];
$base=['idempotency_key'=>'retailer-reg-001','shop_name'=>'  Himalayan Herbal Store  ','contact_name'=>'Owner','mobile'=>'9876543210','address'=>'Main market'];
$tests['register retailer, normalized shop'] = function () use($base) {$g=new MemoryRetailerStore;$r=(new RetailerMaster($g))->register($base+['company_id'=>1,'branch_id'=>1,'actor_id'=>2]);assert($r['type']==='retailer'&&$r['shop_name']==='Himalayan Herbal Store'&&$r['status']==='active');};
$tests['retry registration is idempotent'] = function ()use($base){$g=new MemoryRetailerStore;$m=new RetailerMaster($g);$a=$m->register($base+['company_id'=>1,'branch_id'=>1,'actor_id'=>2]);$b=$m->register($base+['company_id'=>1,'branch_id'=>1,'actor_id'=>2]);assert($a['id']===$b['id']&&count($g->rows)===1);};
$tests['registration key conflict rejected'] = function()use($base){$g=new MemoryRetailerStore;$m=new RetailerMaster($g);$m->register($base+['company_id'=>1,'branch_id'=>1,'actor_id'=>2]);assertFailure('different shop',fn()=>$m->register(array_replace($base,['shop_name'=>'Elsewhere'])+['company_id'=>1,'branch_id'=>1,'actor_id'=>2]));};
$tests['unauthorized retailer creation blocked'] = function()use($base){$g=new MemoryRetailerStore;$g->authorized=false;assertFailure('access denied',fn()=>(new RetailerMaster($g))->register($base+['company_id'=>1,'branch_id'=>1,'actor_id'=>2]));assert(!$g->rows);};
$tests['blank shop rejected'] = function()use($base){$g=new MemoryRetailerStore;assertFailure('required',fn()=>(new RetailerMaster($g))->register(array_replace($base,['shop_name'=>'  '])+['company_id'=>1,'branch_id'=>1,'actor_id'=>2]));};
$tests['invalid mobile rejected'] = function()use($base){$g=new MemoryRetailerStore;assertFailure('mobile',fn()=>(new RetailerMaster($g))->register(array_replace($base,['mobile'=>'abc123'])+['company_id'=>1,'branch_id'=>1,'actor_id'=>2]));};
$tests['optional GSTIN format checked'] = function()use($base){$g=new MemoryRetailerStore;assertFailure('GSTIN',fn()=>(new RetailerMaster($g))->register(array_replace($base,['gstin'=>'INVALID'])+['company_id'=>1,'branch_id'=>1,'actor_id'=>2]));};
$tests['branch access enforced for detail'] = function()use($base){$g=new MemoryRetailerStore;$m=new RetailerMaster($g);$m->register($base+['company_id'=>1,'branch_id'=>1,'actor_id'=>2]);assertFailure('access denied',fn()=>$m->detail(1,2,2,1));};
$tests['separate retailer party and sales channel'] = function()use($base){$g=new MemoryRetailerStore;$api=new RetailerApi(new RetailerMaster($g),new RetailerCashSale($g));$r=$api->create(1,1,2,$base+['company_id'=>999,'actor_id'=>999,'branch_id'=>999]);assert($r['company_id']===1 && !isset($r['created_by']) && !isset($r['request_fingerprint']));$sale=$api->postPaidSale(1,1,2,['company_id'=>999,'actor_id'=>999,'branch_id'=>999,'retailer_id'=>$r['id'],'channel'=>'field','employee_id'=>6,'idempotency_key'=>'retailer-sale-001','payment_mode'=>'cash','payment_reference'=>'CASH-ACT-01','paid_amount'=>'200.00','lines'=>[['product_id'=>1,'batch_id'=>0,'qty'=>2]]]);assert($sale['actor_id']===2 && $sale['company_id']===1 && $sale['retailer_outstanding_paise']===0 && $sale['employee_cash_remittance_paise']===20000);};
$tests['UPI unverified blocked'] = function()use($base){$g=new MemoryRetailerStore;$api=new RetailerApi(new RetailerMaster($g),new RetailerCashSale($g));$r=$api->create(1,1,2,$base);$g->tenderVerified=false;assertFailure('not confirmed',fn()=>$api->postPaidSale(1,1,2,['retailer_id'=>$r['id'],'channel'=>'counter','employee_id'=>null,'idempotency_key'=>'retailer-sale-002','payment_mode'=>'upi','payment_reference'=>'UPI-UNKNOWN','paid_amount'=>'100.00','lines'=>[['product_id'=>1,'batch_id'=>0,'qty'=>1]]]));assert($g->stock[0]===7);};
$tests['partial retailer payment blocked'] = function()use($base){$g=new MemoryRetailerStore;$api=new RetailerApi(new RetailerMaster($g),new RetailerCashSale($g));$r=$api->create(1,1,2,$base);assertFailure('Full verified payment',fn()=>$api->postPaidSale(1,1,2,['retailer_id'=>$r['id'],'channel'=>'counter','idempotency_key'=>'retailer-sale-003','payment_mode'=>'cash','payment_reference'=>'CASH-PARTIAL','paid_amount'=>'99.00','lines'=>[['product_id'=>1,'batch_id'=>0,'qty'=>1]]]));};
$i=0;foreach($tests as $name=>$test){try{$test();echo "PASS {$name}\n";$i++;}catch(Throwable $e){fwrite(STDERR,"FAIL {$name}: {$e->getMessage()}\n");exit(1);}}echo "PASS {$i}/".count($tests)." retailer flow tests\n";