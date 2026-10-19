<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP7\Security {
 final class Actor { public function __construct(public int $userId=8,public int $employeeId=42,public int $companyId=1,public int $assignedBranchId=4,public array $branchIds=[4],public array $capabilities=['sales.create']) {} public function can(string $cap):bool{return in_array($cap,$this->capabilities,true);}public function hasBranch(int $id):bool{return in_array($id,$this->branchIds,true);} }
 final class Capabilities {const SALES_CREATE='sales.create';}
 final class Guard {public static function branch(Actor $a,int $branch,string $cap):void{if(!$a->can($cap)||!$a->hasBranch($branch))throw new \ExcelHerbal\ERP8\B2B\RetailerSaleError('Branch permission denied');}}
}
namespace ExcelHerbal\ERP8\B2B {
 require_once __DIR__.'/../src/B2B/RetailerCashSale.php';
 require_once __DIR__.'/../src/B2B/CanonicalV7Readiness.php';
 // Source dependency can be safely mocked for isolated reader checks; real posting
 // writer has its own 34-case separate suite and uses this callback signature.
 final class V7CanonicalPostingSinkUat { public static function assertNonProductionEnvironment(object $db):void {if($db->database!=='v8_test'||$db->prefix!=='wp_')throw new RetailerSaleError('UAT environment blocked');}}
 require_once __DIR__.'/../src/B2B/V7UatLockedCheckoutReader.php';
 use ExcelHerbal\ERP7\Security\Actor;
 final class FakeWpdbV8 {
    public string $prefix='wp_';public string $database='v8_test';public string $last_error='';
    public array $rows=[];public array $lockSql=[];public array $lastArgs=[];
    public function __construct(){
        $lines=[['product_id'=>'11','batch_id'=>'0','quantity_pcs'=>'2','commercial_revision_id'=>'21','unit_price_paise'=>'10000','line_total_paise'=>'20000','line_no'=>'1']];
        $quote=['company_id'=>1,'branch_id'=>4,'retailer_id'=>13,'canonical_party_id'=>17,
            'channel'=>'field','employee_id'=>42,'business_at'=>'2026-10-19 11:50:00',
            'payment_mode'=>'cash','gross_paise'=>20000,'lines'=>array_map(static fn($x)=>array_intersect_key(array_map('intval',$x),array_flip(['product_id','batch_id','quantity_pcs','commercial_revision_id','unit_price_paise','line_total_paise'])),$lines)];
        $digest=hash('sha256',json_encode($quote,JSON_THROW_ON_ERROR));
        $this->rows=[
            'v8_b2b_sale_intents_uat'=>['id'=>333,'company_id'=>1,'branch_id'=>4,'retailer_id'=>13,'canonical_party_id'=>17,'channel'=>'field','employee_id'=>'42','payment_mode'=>'cash','merchant_order_id'=>null,'currency'=>'INR','invoice_total_paise'=>'20000','quote_digest'=>$digest,'pricing_locked'=>'1','status'=>'awaiting_payment'],
            'v8_b2b_issued_sale_context_uat'=>['sale_intent_id'=>333,'company_id'=>1,'branch_id'=>4,'business_at'=>'2026-10-19 11:50:00','quote_digest'=>$digest],
            'v8_b2b_sale_intent_lines_uat'=>$lines,
            'v8_b2b_sale_tender_reservations_uat'=>['id'=>88,'company_id'=>1,'branch_id'=>4,'sale_intent_id'=>333,'payment_intent_id'=>55,'tender_id'=>77,'retailer_id'=>13,'canonical_party_id'=>17,'channel'=>'field','employee_id'=>'42','payment_mode'=>'cash','payment_reference'=>'CASH-INT-1-4-55','verified_source'=>'employee_cash_custody','amount_paise'=>'20000','quote_digest'=>$digest,'status'=>'reserved'],
            'v8_b2b_payment_intent_to_sale_uat'=>['company_id'=>1,'branch_id'=>4,'payment_intent_id'=>55,'sale_intent_id'=>'333','quote_digest'=>$digest],
            'v8_b2b_payment_intents_uat'=>['id'=>55,'company_id'=>1,'branch_id'=>4,'channel'=>'field','employee_id'=>'42','payment_mode'=>'cash','amount_paise'=>'20000','merchant_order_id'=>null,'currency'=>'INR','status'=>'awaiting_payment'],
            'v8_b2b_tender_intake_evidence_uat'=>['intent_id'=>55,'company_id'=>1,'branch_id'=>4,'confirmed_tender_id'=>'77','amount_paise'=>'20000','payment_mode'=>'cash','verified_source'=>'employee_cash_custody','verified_by'=>'8','payment_reference'=>'CASH-INT-1-4-55','channel'=>'field','employee_id'=>'42'],
            'v8_b2b_verified_tenders'=>['id'=>77,'company_id'=>1,'branch_id'=>4,'amount_paise'=>'20000','payment_mode'=>'cash','verified_source'=>'employee_cash_custody','payment_reference'=>'CASH-INT-1-4-55','status'=>'confirmed','consumed_sale_id'=>null],
            'wp_eh7_b2b_verified_tenders'=>['id'=>'99','company_id'=>1,'branch_id'=>4,'sale_intent_id'=>333,'payment_intent_id'=>55,'tender_id'=>77,'quote_digest'=>$digest,'channel'=>'field','employee_id'=>'42','payment_mode'=>'cash','currency'=>'INR','status'=>'confirmed','verified_by'=>'8','verified_source'=>'employee_cash_custody','amount_paise'=>'20000','provider_transaction_id'=>'CASH-INT-1-4-55','consumed_sale_id'=>null],
            'wp_eh7_branches'=>['id'=>4,'status'=>'active','company_id'=>1],
            'wp_eh7_employees'=>['id'=>42,'status'=>'active','assigned_branch_id'=>4,'company_id'=>1],
            'wp_eh7_accounting_periods'=>null,
            'wp_eh7_branch_closings'=>null,
            'wp_eh7_products'=>['id'=>11,'status'=>'active','uom'=>'PCS','batch_tracking'=>'off','expiry_tracking'=>'0'],
            'wp_eh7_product_commercial_revisions'=>['id'=>'21','status'=>'active','sale_price'=>'100.00','mrp'=>'120.00','ho_amount'=>'60.00','bm_profit'=>'10.00','salary_fund'=>'10.00','office_expense'=>'20.00','purchase_cost'=>'40.00'],
            'wp_eh7_batches'=>null,
            'wp_eh7_stock_balances'=>['quantity'=>'10.000','average_unit_cost'=>'40.0000'],
            'wp_eh7_accounts'=>['SALES'=>['id'=>'10','active'=>'1','type'=>'income'],'COGS'=>['id'=>'11','active'=>'1','type'=>'expense'],'INVENTORY'=>['id'=>'12','active'=>'1','type'=>'asset'],'EMPLOYEE_CASH_IN_TRANSIT'=>['id'=>'13','active'=>'1','type'=>'asset']],
        ];
    }
    public function prepare(string $sql,...$args):string {
        if(!str_contains($sql,'FOR UPDATE'))throw new RetailerSaleError('Missing row lock');
        $this->lastArgs=$args;$this->lockSql[]=$sql;
        return $sql;
    }
    private function selected(string $sql):mixed {
        foreach($this->rows as $table=>$data){
          if(str_contains($sql,'FROM '.$table.' ') || str_contains($sql,'FROM '.$table."\n")){
            if($table==='wp_eh7_accounts') { $key=$this->lastArgs[1]??'';return $data[$key]??null; }
            return $data;
          }
        }
        throw new RetailerSaleError('Unexpected unlocked table: '.$sql);
    }
    public function get_row(string $sql,$format=null):?array {
        $x=$this->selected($sql);return is_array($x)?$x:null;
    }
    public function get_results(string $sql,$format=null):array {
        $x=$this->selected($sql);return is_array($x)?$x:[];
    }
 }
 function quoteDigest(FakeWpdbV8 $d):void {
     $s=&$d->rows['v8_b2b_sale_intents_uat'];
     $snap=['company_id'=>1,'branch_id'=>4,'retailer_id'=>13,'canonical_party_id'=>17,
         'channel'=>$s['channel'],'employee_id'=>$s['employee_id']===null?null:(int)$s['employee_id'],
         'business_at'=>'2026-10-19 11:50:00','payment_mode'=>$s['payment_mode'],'gross_paise'=>20000,
         'lines'=>[['product_id'=>11,'batch_id'=>0,'quantity_pcs'=>2,'commercial_revision_id'=>21,'unit_price_paise'=>10000,'line_total_paise'=>20000]]];
     $hash=hash('sha256',json_encode($snap,JSON_THROW_ON_ERROR));
     $s['quote_digest']=$hash;
     foreach(['v8_b2b_issued_sale_context_uat','v8_b2b_sale_tender_reservations_uat','v8_b2b_payment_intent_to_sale_uat','wp_eh7_b2b_verified_tenders'] as $k)$d->rows[$k]['quote_digest']=$hash;
 }
 function ctx():array{return ['company_id'=>1,'branch_id'=>4,'retailer_id'=>13,'sale_intent_id'=>333,'actor_id'=>8];}
 function caseRun(?callable $modify=null):array{
     $db=new FakeWpdbV8();$actor=new Actor();$context=ctx();
     if($modify)$modify($db,$actor,$context);
     return [(new V7UatLockedCheckoutReader())($actor,$context,$db),$db];
 }
 function deny(callable $modify,string $contains=''):void{
     try{caseRun($modify);}catch(RetailerSaleError $e){if($contains!==''&&!str_contains(strtolower($e->getMessage()),strtolower($contains)))throw new \RuntimeException('Wrong rejection: '.$e->getMessage());return;}
     throw new \RuntimeException('Expected rejection, got acceptance');
 }
 $tests=[];
 $tests['valid field cash binds all staged rows and canonical V7 locked assessment']=static function(){[$out,$db]=caseRun();assert($out['assessment']['posting_allowed']===true&&$out['tender']['id']===99&&$out['quote']['saved_lines'][0]['product_id']===11);assert($out['assessment']['total_paise']===20000&&$out['assessment']['cogs_paise']===8000&&count($db->lockSql)>=14);};
 $tests['reader is pure read-only without DB mutation']=static function(){[$r,$db]=caseRun();foreach($db->lockSql as $sql)assert(str_starts_with($sql,'SELECT ')&&str_contains($sql,'FOR UPDATE'));};
 $tests['UPI bank settlement matches exact merchant order and no employee Cash-in-Transit']=static function(){
    [$out,$db]=caseRun(static function($d){
        $order='EH8-UAT-'.str_repeat('a',32);
        $d->rows['v8_b2b_sale_intents_uat']['payment_mode']='upi';
        $d->rows['v8_b2b_sale_intents_uat']['merchant_order_id']=$order;
        $d->rows['v8_b2b_payment_intents_uat']['payment_mode']='upi';
        $d->rows['v8_b2b_payment_intents_uat']['merchant_order_id']=$order;
        $d->rows['v8_b2b_sale_tender_reservations_uat']['payment_mode']='upi';
        $d->rows['v8_b2b_tender_intake_evidence_uat']['payment_mode']='upi';
        $d->rows['v8_b2b_verified_tenders']['payment_mode']='upi';
        $d->rows['wp_eh7_b2b_verified_tenders']['payment_mode']='upi';
        foreach(['v8_b2b_sale_tender_reservations_uat','v8_b2b_tender_intake_evidence_uat','v8_b2b_verified_tenders','wp_eh7_b2b_verified_tenders'] as $k)$d->rows[$k]['verified_source']='bank_settlement';
        $d->rows['wp_eh7_accounts']['UPI_CLEARING']=['id'=>'14','active'=>'1','type'=>'asset'];
        quoteDigest($d);
    });
    assert($out['assessment']['payment_mode']==='upi'&&isset($out['assessment']['canonical_account_ids']['UPI_CLEARING']));
 };
 $tests['counter Cash uses branch custody without employee assignment']=static function(){
    [$out,$db]=caseRun(static function($d){
        $d->rows['v8_b2b_sale_intents_uat']['channel']='counter';
        $d->rows['v8_b2b_payment_intents_uat']['channel']='counter';
        $d->rows['v8_b2b_sale_tender_reservations_uat']['channel']='counter';
        $d->rows['v8_b2b_tender_intake_evidence_uat']['channel']='counter';
        foreach(['v8_b2b_sale_intents_uat','v8_b2b_payment_intents_uat','v8_b2b_sale_tender_reservations_uat','v8_b2b_tender_intake_evidence_uat','wp_eh7_b2b_verified_tenders'] as $k)$d->rows[$k]['employee_id']=null;
        $d->rows['wp_eh7_b2b_verified_tenders']['channel']='counter';
        foreach(['v8_b2b_sale_tender_reservations_uat','v8_b2b_tender_intake_evidence_uat','v8_b2b_verified_tenders','wp_eh7_b2b_verified_tenders'] as $k)$d->rows[$k]['verified_source']='branch_cashier_cash';
        $d->rows['wp_eh7_accounts']['BRANCH_CASH']=['id'=>'14','active'=>'1','type'=>'asset'];
        quoteDigest($d);
    });
    assert($out['assessment']['employee_id']===null&&isset($out['assessment']['canonical_account_ids']['BRANCH_CASH']));
 };
 $tests['draft schema contains all independent canonical proof fields']=static function(){
    $schema=file_get_contents(__DIR__.'/../schema/009_v7_canonical_retailer_posting_DRAFT.sql');
    assert(is_string($schema));
    foreach(['payment_intent_id','tender_id','verified_by','currency','status','channel','employee_id','consumed_sale_id','provider_transaction_id'] as $field)assert(str_contains($schema,$field));
 };
 $mutations=[
 'different actor ID'=>[static fn($d,$a,&$c)=>$c['actor_id']=99,'actor'],
 'different company'=>[static fn($d,$a,&$c)=>$c['company_id']=2,'actor'],
 'different branch'=>[static fn($d,$a,&$c)=>$c['branch_id']=5,'branch'],
 'production database blocked'=>[static fn($d)=>$d->database='production','environment'],
 'malicious prefix blocked'=>[static fn($d)=>$d->prefix='wp_;drop','environment'],
 'missing intent'=>[static fn($d)=>$d->rows['v8_b2b_sale_intents_uat']=null,'quote'],
 'retailer mismatch'=>[static fn($d)=>$d->rows['v8_b2b_sale_intents_uat']['retailer_id']=99,'quote'],
 'credit payment rejected'=>[static fn($d)=>$d->rows['v8_b2b_sale_intents_uat']['payment_mode']='credit','quote'],
 'currency wrong'=>[static fn($d)=>$d->rows['v8_b2b_sale_intents_uat']['currency']='USD','quote'],
 'sale not awaiting payment'=>[static fn($d)=>$d->rows['v8_b2b_sale_intents_uat']['status']='posted','quote'],
 'pricing not locked'=>[static fn($d)=>$d->rows['v8_b2b_sale_intents_uat']['pricing_locked']=0,'quote'],
 'invalid employee custody'=>[static fn($d)=>$d->rows['v8_b2b_sale_intents_uat']['employee_id']=null,'custody'],
 'missing business timestamp'=>[static fn($d)=>$d->rows['v8_b2b_issued_sale_context_uat']=null,'business time'],
 'changed issued business timestamp'=>[static fn($d)=>$d->rows['v8_b2b_issued_sale_context_uat']['business_at']='2026-10-18 11:50:00','digest'],
 'missing line'=>[static fn($d)=>$d->rows['v8_b2b_sale_intent_lines_uat']=[],'lines'],
 'duplicate line number'=>[static function($d){$d->rows['v8_b2b_sale_intent_lines_uat'][]=$d->rows['v8_b2b_sale_intent_lines_uat'][0];},'line'],
 'changed stored quantity'=>[static fn($d)=>$d->rows['v8_b2b_sale_intent_lines_uat'][0]['quantity_pcs']='3','arithmetic'],
 'reduced stored total'=>[static fn($d)=>$d->rows['v8_b2b_sale_intent_lines_uat'][0]['line_total_paise']='19999','arithmetic'],
 'tampered line price same total'=>[static fn($d)=>$d->rows['v8_b2b_sale_intent_lines_uat'][0]['unit_price_paise']='9999','arithmetic'],
 'missing reservation'=>[static fn($d)=>$d->rows['v8_b2b_sale_tender_reservations_uat']=null,'reservation'],
 'wrong reservation canonical party'=>[static fn($d)=>$d->rows['v8_b2b_sale_tender_reservations_uat']['canonical_party_id']=555,'reservation'],
 'reservation amount mismatch'=>[static fn($d)=>$d->rows['v8_b2b_sale_tender_reservations_uat']['amount_paise']='19999','reservation'],
 'wrong payment linked sale'=>[static fn($d)=>$d->rows['v8_b2b_payment_intent_to_sale_uat']['sale_intent_id']='123','payment intent'],
 'payment intent different amount'=>[static fn($d)=>$d->rows['v8_b2b_payment_intents_uat']['amount_paise']='19999','payment intent'],
 'missing cash attestation'=>[static fn($d)=>$d->rows['v8_b2b_tender_intake_evidence_uat']=null,'evidence'],
 'different tender proof ID'=>[static fn($d)=>$d->rows['v8_b2b_tender_intake_evidence_uat']['confirmed_tender_id']='199','evidence'],
 'wrong tender reference'=>[static fn($d)=>$d->rows['v8_b2b_verified_tenders']['payment_reference']='fake','evidence'],
 'tender already consumed'=>[static fn($d)=>$d->rows['v8_b2b_verified_tenders']['consumed_sale_id']=991,'evidence'],
 'canonical receipt missing'=>[static fn($d)=>$d->rows['wp_eh7_b2b_verified_tenders']=null,'canonical'],
 'canonical receipt currency mismatch'=>[static fn($d)=>$d->rows['wp_eh7_b2b_verified_tenders']['currency']='USD','canonical'],
 'canonical receipt forged verified by'=>[static fn($d)=>$d->rows['wp_eh7_b2b_verified_tenders']['verified_by']='9','canonical'],
 'canonical receipt already consumed'=>[static fn($d)=>$d->rows['wp_eh7_b2b_verified_tenders']['consumed_sale_id']=24,'canonical'],
 'revised V7 rate'=>[static fn($d)=>$d->rows['wp_eh7_product_commercial_revisions']['sale_price']='99.00','commercial'],
 'changed V7 price revision'=>[static fn($d)=>$d->rows['wp_eh7_product_commercial_revisions']['id']='22',''],
 'insufficient V7 stock'=>[static fn($d)=>$d->rows['wp_eh7_stock_balances']['quantity']='1.000','stock'],
 'missing V7 sales account'=>[static fn($d)=>$d->rows['wp_eh7_accounts']['SALES']=null,'Chart'],
 'closed V7 accounting period'=>[static fn($d)=>$d->rows['wp_eh7_accounting_periods']=['id'=>22],'period'],
 'closed V7 branch day'=>[static fn($d)=>$d->rows['wp_eh7_branch_closings']=['id'=>22],'day'],
 'employee assigned another branch'=>[static fn($d)=>$d->rows['wp_eh7_employees']['assigned_branch_id']=9,'employee'],
 'wrong V7 employee assignment'=>[static fn($d)=>$d->rows['wp_eh7_employees']=null,'employee'],
 'forged V7 product status'=>[static fn($d)=>$d->rows['wp_eh7_products']['status']='inactive','product'],
 ];
 foreach($mutations as $name=>[$mutator,$needle])$tests[$name]=static fn()=>deny($mutator,$needle);
 $passed=0;foreach($tests as $name=>$fn){try{$fn();$passed++;}catch(\Throwable $e){fwrite(STDERR,'FAIL '.$name.': '.$e->getMessage()."\n");exit(1);}}
 echo "PASS {$passed}/".count($tests)." V7 same-DB locked immutable evidence and fresh stock reader regression cases\n";
}
