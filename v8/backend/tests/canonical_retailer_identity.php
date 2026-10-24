<?php
declare(strict_types=1);

use ExcelHerbal\ERP8\B2B\{RetailerSaleError,CanonicalRetailerIdentity,CanonicalRetailerIdentityReader,WpV7RetailerIdentityReader};
require_once __DIR__.'/../src/B2B/RetailerCashSale.php';
require_once __DIR__.'/../src/B2B/CanonicalRetailerIdentity.php';
require_once __DIR__.'/../src/B2B/WpV7RetailerIdentityReader.php';

final class FakeCanonicalRetailerIdentityReader implements CanonicalRetailerIdentityReader
{
    public bool $authorized = true;
    public ?array $row = [
        'retailer_id'=>91,'company_id'=>1,'branch_id'=>4,'party_id'=>55,
        'link_status'=>'active','party_status'=>'active','party_type'=>'customer',
        'shop_name'=>'Herbal Retail Shop',
    ];
    public string $outstanding = '0.00';
    public int $lookups=0;
    public int $receivableReads=0;
    public function canInspectRetailer(int $actorId,int $companyId,int $branchId):bool
    {return $this->authorized&&$actorId===20&&$companyId===1&&$branchId===4;}
    public function retailerParty(int $companyId,int $branchId,int $retailerId):?array
    {$this->lookups++;return $this->row;}
    public function openCustomerReceivables(int $companyId,int $branchId,int $partyId):string
    {$this->receivableReads++;return $this->outstanding;}
}
function idRequest(array $changes=[]):array{return array_replace(['actor_id'=>20,'company_id'=>1,'branch_id'=>4,'retailer_id'=>91],$changes);}
function idRejected(string $fragment,callable $cb):void
{
    try{$cb();}catch(RetailerSaleError $e){if(!str_contains($e->getMessage(),$fragment))throw new RuntimeException($e->getMessage());return;}
    throw new RuntimeException('Expected rejection: '.$fragment);
}
$tests=[];
$tests['active canonical retailer maps to customer party without enabling posting']=static function():void {
    $result=(new CanonicalRetailerIdentity(new FakeCanonicalRetailerIdentityReader()))->resolve(idRequest());
    assert($result['canonical_party_id']===55 && $result['retailer_id']===91);
    assert($result['credit_allowed']===false && $result['outstanding_paise']===0 && $result['posting_allowed']===false);
};
$tests['shopper identity cannot be read without actor branch authority']=static function():void {
    $g=new FakeCanonicalRetailerIdentityReader();$g->authorized=false;
    idRejected('access denied',static fn()=>(new CanonicalRetailerIdentity($g))->resolve(idRequest()));
    assert($g->lookups===0 && $g->receivableReads===0);
};
$tests['malformed trusted company or user context rejected']=static function():void {
    foreach(['actor_id'=>0,'company_id'=>'1','branch_id'=>null,'retailer_id'=>-1] as $k=>$value){
        idRejected('requires valid',static fn()=>(new CanonicalRetailerIdentity(new FakeCanonicalRetailerIdentityReader()))->resolve(idRequest([$k=>$value])));
    }
};
$tests['unknown retailer link cannot impersonate V7 customer']=static function():void {
    $g=new FakeCanonicalRetailerIdentityReader();$g->row=null;
    idRejected('not linked',static fn()=>(new CanonicalRetailerIdentity($g))->resolve(idRequest()));
};
$tests['link cannot cross company branch or ID boundary']=static function():void {
    foreach(['company_id'=>2,'branch_id'=>5,'retailer_id'=>92] as $k=>$wrong){
        $g=new FakeCanonicalRetailerIdentityReader();$g->row[$k]=$wrong;
        idRejected('crosses company',static fn()=>(new CanonicalRetailerIdentity($g))->resolve(idRequest()));
    }
};
$tests['linked customer must be active and type customer']=static function():void {
    foreach([['link_status','inactive'],['party_status','inactive'],['party_type','supplier']] as [$key,$value]){
        $g=new FakeCanonicalRetailerIdentityReader();$g->row[$key]=$value;
        idRejected('both be active',static fn()=>(new CanonicalRetailerIdentity($g))->resolve(idRequest()));
    }
};
$tests['canonical party ID must be positive integer-like DB id']=static function():void {
    foreach(['0','1 OR 1=1',''] as $bad){
        $g=new FakeCanonicalRetailerIdentityReader();$g->row['party_id']=$bad;
        idRejected('invalid canonical identifier',static fn()=>(new CanonicalRetailerIdentity($g))->resolve(idRequest()));
    }
};
$tests['shop name cannot be empty']=static function():void {
    $g=new FakeCanonicalRetailerIdentityReader();$g->row['shop_name']='   ';
    idRejected('shop name',static fn()=>(new CanonicalRetailerIdentity($g))->resolve(idRequest()));
};
$tests['positive existing customer AR blocks Cash-only retailer classification']=static function():void {
    $g=new FakeCanonicalRetailerIdentityReader();$g->outstanding='0.01';
    idRejected('Existing customer credit',static fn()=>(new CanonicalRetailerIdentity($g))->resolve(idRequest()));
};
$tests['unparseable outstanding balance fails closed']=static function():void {
    $g=new FakeCanonicalRetailerIdentityReader();$g->outstanding='UNAVAILABLE';
    idRejected('Invalid money',static fn()=>(new CanonicalRetailerIdentity($g))->resolve(idRequest()));
};
$tests['identity reader requires mandatory V7 access authorization callback']=static function():void {
    idRejected('authorization callback',static fn()=>new WpV7RetailerIdentityReader((object)['prefix'=>'wp_'],null));
};
$tests['identity reader rejects unsafe interpolated WP table prefixes']=static function():void {
    idRejected('Unsafe WordPress prefix',static fn()=>new WpV7RetailerIdentityReader((object)['prefix'=>'wp_;DROP'],static fn()=>true));
};
$tests['WP adapter joins V8 classification to V7 parties with strict scopes']=static function():void {
    $db=new class{
        public string $prefix='wp_', $last_error='';
        public array $queries=[];
        public function prepare(string $sql,...$params):string {$this->queries[]=['sql'=>$sql,'args'=>$params];return $sql;}
        public function get_row(string $sql,string $type):array{return ['retailer_id'=>'91','party_id'=>'55','company_id'=>'1','branch_id'=>'4','link_status'=>'active','party_type'=>'customer','party_status'=>'active','shop_name'=>'Retail Shop'];}
        public function get_var(string $sql):string{return '0.00';}
    };
    $reader=new WpV7RetailerIdentityReader($db,static fn(int $actor,int $co,int $br)=>$actor===20 && $co===1 && $br===4);
    $r=(new CanonicalRetailerIdentity($reader))->resolve(idRequest());
    assert($r['canonical_party_id']===55&&$r['posting_allowed']===false);
    assert(count($db->queries)===2);
    assert(str_contains($db->queries[0]['sql'],'wp_eh8_retailer_party_links'));
    assert(str_contains($db->queries[0]['sql'],'wp_eh7_parties'));
    assert(str_contains($db->queries[0]['sql'],'p.company_id=l.company_id'));
    assert(str_contains($db->queries[0]['sql'],'p.branch_id=l.branch_id'));
    assert($db->queries[0]['args']===[1,4,91]);
    assert(str_contains($db->queries[1]['sql'],'wp_eh7_counter_sales'));
    assert(str_contains($db->queries[1]['sql'],"status='posted'"));
    assert($db->queries[1]['args']===[1,4,55]);
};
$tests['WP adapter denies wrong branch without database query']=static function():void {
    $db=new class{public string $prefix='wp_', $last_error='';public int $calls=0;public function prepare(string $s,...$a):string{$this->calls++;return $s;}};
    $reader=new WpV7RetailerIdentityReader($db,static fn($a,$c,$b)=>false);
    idRejected('access denied',static fn()=>(new CanonicalRetailerIdentity($reader))->resolve(idRequest()));
    assert($db->calls===0);
};
$tests['missing retailer mapping table or failing database read denies identity']=static function():void {
    $db=new class{
        public string $prefix='wp_', $last_error='';
        public function prepare(string $s,...$a):string{return $s;}
        public function get_row(string $s,string $f):null{$this->last_error='Table does not exist';return null;}
    };
    $reader=new WpV7RetailerIdentityReader($db,static fn()=>true);
    idRejected('data unavailable',static fn()=>(new CanonicalRetailerIdentity($reader))->resolve(idRequest()));
};
$tests['failure to read receivable balance must deny retailer eligibility']=static function():void {
    $db=new class{
        public string $prefix='wp_', $last_error='';
        public function prepare(string $s,...$a):string{return $s;}
        public function get_row(string $s,string $f):array{return ['retailer_id'=>'91','party_id'=>'55','company_id'=>'1','branch_id'=>'4','link_status'=>'active','party_type'=>'customer','party_status'=>'active','shop_name'=>'Retail Shop'];}
        public function get_var(string $s):null{return null;}
    };
    $reader=new WpV7RetailerIdentityReader($db,static fn()=>true);
    idRejected('balance could not be validated',static fn()=>(new CanonicalRetailerIdentity($reader))->resolve(idRequest()));
};
$tests['reader has no SQL mutation operation']=static function():void {
    $db=new class{
        public string $prefix='wp_', $last_error='';
        public array $reads=[];
        public function prepare(string $s,...$a):string{assert(str_starts_with($s,'SELECT '));$this->reads[]=$s;return $s;}
        public function get_row(string $s,string $f):null{return null;}
        public function query(string $s):never{throw new RuntimeException('Write forbidden');}
    };
    $reader=new WpV7RetailerIdentityReader($db,static fn()=>true);
    $reader->retailerParty(1,4,91);
    assert(count($db->reads)===1);
};
$passed=0;
foreach($tests as $name=>$test){
    try{$test();echo "PASS {$name}\n";$passed++;}
    catch(Throwable $e){fwrite(STDERR,"FAIL {$name}: {$e->getMessage()}\n");exit(1);}
}
echo "PASS {$passed}/".count($tests)." canonical retailer identity tests\n";
