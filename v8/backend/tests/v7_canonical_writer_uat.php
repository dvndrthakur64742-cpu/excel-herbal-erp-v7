<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP7\Security {
    final class Actor {
        public function __construct(public int $userId=8,public int $employeeId=9,public int $companyId=1,public int $assignedBranchId=4,public array $branchIds=[4],public array $capabilities=['sales.create'],public string $designationCode='BM') {}
        public function can(string $cap):bool{return in_array($cap,$this->capabilities,true);}
        public function hasBranch(int $id):bool{return in_array($id,$this->branchIds,true);}
    }
    final class Capabilities {public const SALES_CREATE='sales.create';}
    final class Guard {public static function branch(Actor $a,int $b,string $cap):void{if(!$a->hasBranch($b)||!$a->can($cap))throw new \ExcelHerbal\ERP8\B2B\RetailerSaleError('Branch or sale permission denied.');}}
}
namespace ExcelHerbal\ERP7\Database {
    final class Db {
        public static $db;
        public static function wpdb():object{return self::$db;}
        public static function table(string $name):string{return self::$db->prefix.'eh7_'.$name;}
        public static function now():string{return '2026-10-19 10:00:00';}
        public static function mustQuery(object $d,string $q):int{$v=$d->query($q);if($v===false)throw new \RuntimeException('Query failed');return (int)$v;}
        public static function mustInsert(object $d,string $t,array $row):int{$n=$d->insert($t,$row);if($n===false)throw new \RuntimeException('Insert failed');return (int)$n;}
        public static function mustUpdate(object $d,string $t,array $row,array $where):int{$n=$d->update($t,$row,$where);if($n===false)throw new \RuntimeException('Update failed');return (int)$n;}
    }
    final class Transaction {
        public static function run(callable $fn):mixed{
            $d=Db::wpdb();$snapshot=[$d->rows,$d->insert_id,$d->counts,$d->stock,$d->journals,$d->stock_moves];
            try{return $fn();}catch(\Throwable $e){[$d->rows,$d->insert_id,$d->counts,$d->stock,$d->journals,$d->stock_moves]=$snapshot;throw $e;}
        }
    }
}
namespace ExcelHerbal\ERP7\Inventory {
    final class StockService {
        public static bool $fail=false;public static bool $costDrift=false;
        public static function move($a,int $branch,int $product,?int $batch,?int $employee,string $dir,float $qty,float $cost,string $source,int $id):float{
            if(self::$fail)throw new \ExcelHerbal\ERP8\B2B\RetailerSaleError('Simulated V7 stock failure');
            $d=\ExcelHerbal\ERP7\Database\Db::wpdb();$key=$branch.'-'.$product.'-'.($employee??0);
            if(($d->stock[$key]??0)<$qty)throw new \ExcelHerbal\ERP8\B2B\RetailerSaleError('Insufficient stock');
            $d->stock[$key]-=$qty;$d->stock_moves[]=['employee'=>$employee,'source'=>$source,'qty'=>$qty,'batch'=>$batch];
            return self::$costDrift?$cost+1:$cost;
        }
    }
}
namespace ExcelHerbal\ERP7\Finance {
    final class AccountingService {
        public static bool $fail=false;public static bool $closed=false;
        public static function lockCompanyForPeriod($a):void{}
        public static function assertPeriodOpen($a,string $date):void{if(self::$closed)throw new \ExcelHerbal\ERP8\B2B\RetailerSaleError('Period closed');}
        public static function post($a,int $branch,string $source,int $saleId,string $date,array $lines,string $memo):int{
            if(self::$fail)throw new \ExcelHerbal\ERP8\B2B\RetailerSaleError('Simulated V7 journal failure');
            $d=\ExcelHerbal\ERP7\Database\Db::wpdb();$d->journals[900]=['source'=>$source,'sale'=>$saleId,'lines'=>$lines,'date'=>$date];return 900;
        }
    }
}
namespace { function wp_get_environment_type():string{return $GLOBALS['environment']??'development';} }
namespace ExcelHerbal\ERP8\B2B {
    require_once __DIR__.'/../src/B2B/RetailerCashSale.php';
    require_once __DIR__.'/../src/B2B/CanonicalPostingContract.php';
    require_once __DIR__.'/../src/B2B/V7CanonicalPostingSinkUat.php';
    use ExcelHerbal\ERP7\Security\Actor;
    use ExcelHerbal\ERP7\Database\Db;
    use ExcelHerbal\ERP7\Inventory\StockService;
    use ExcelHerbal\ERP7\Finance\AccountingService;
    final class FakeWpdb {
        public string $prefix='wp_',$database='v8_test';public int $insert_id=0;
        public array $rows=[],$counts=[],$stock=['4-11-0'=>10,'4-11-42'=>10],$journals=[],$stock_moves=[];
        public bool $closedDay=false,$openCredit=false,$badParty=false,$failFinalize=false;
        public function prepare(string $query,...$args):string{foreach($args as $a){$pos=strpos($query,'%');if($pos===false)break;$q=$query[$pos+1];$formatted=$q==='d'?(string)(int)$a:"'".str_replace("'","''",(string)$a)."'";$query=substr_replace($query,$formatted,$pos,2);}return $query;}
        public function get_var(string $sql):mixed{
            if(str_contains($sql,'DATABASE()'))return $this->database;
            if(str_contains($sql,'branch_closings'))return $this->closedDay?7:null;
            return null;
        }
        public function query(string $sql):int|false{
            if(str_contains($sql,'INSERT INTO')&&str_contains($sql,'b2b_checkout_keys')){
                $matches=[];preg_match('/VALUES\((\d+),\'([^\']+)\'\)/',$sql,$matches);
                if(!isset($matches[1]))throw new \RuntimeException('Bad key insert SQL');
                $key=$matches[1].':'.$matches[2];$this->rows['keys'][$key]??=['company_id'=>(int)$matches[1],'request_key'=>$matches[2],'sale_id'=>null,'sale_intent_id'=>null,'request_fingerprint'=>null];return 1;
            }
            if(str_contains($sql,'UPDATE')&&str_contains($sql,'b2b_verified_tenders')){
                if(($this->rows['proof_consumed']??false)===true)return 0;
                $this->rows['proof_consumed']=true;return 1;
            }
            return 1;
        }
        public function get_results(string $sql,$mode):array{return $this->openCredit?[['id'=>7,'outstanding_amount'=>'100.00']]:[];}
        public function get_row(string $sql,$mode):?array{
            if(str_contains($sql,'b2b_checkout_keys')){
                preg_match('/request_key=\'([^\']+)\'/',$sql,$m);
                return $this->rows['keys']['1:'.($m[1]??'')]??null;
            }
            if(str_contains($sql,'b2b_retailer_sales')){
                $sale=$this->rows['sales'][0]??null;return $sale===null?null:['id'=>$sale['id'],'journal_entry_id'=>$sale['journal_entry_id'],'invoice_total_paise'=>$sale['invoice_total_paise'],'quote_digest'=>$sale['quote_digest']];
            }
            if(str_contains($sql,'eh8_retailer_party_links'))return $this->badParty?null:['id'=>55];
            return null;
        }
        public function insert(string $table,array $data):int{
            $this->insert_id=73;
            if(str_contains($table,'b2b_retailer_sales')){
                $this->rows['sales'][]=$data+['id'=>73,'journal_entry_id'=>null];
                $this->counts['sales']=($this->counts['sales']??0)+1;
            }
            if(str_contains($table,'b2b_retailer_sale_lines'))$this->counts['lines']=($this->counts['lines']??0)+1;
            return 1;
        }
        public function update(string $table,array $data,array $where):int{
            if(str_contains($table,'b2b_retailer_sales')){
                if($this->failFinalize)return 0;
                $this->rows['sales'][0]=array_merge($this->rows['sales'][0],$data);return 1;
            }
            if(str_contains($table,'b2b_checkout_keys')){
                $key=$where['company_id'].':'.$where['request_key'];$this->rows['keys'][$key]=array_merge($this->rows['keys'][$key],$data);return 1;
            }
            return 0;
        }
    }
    if(!defined('ARRAY_A'))define('ARRAY_A','ARRAY_A');
    if(!defined('EH8_ALLOW_V7_B2B_UAT_POSTING'))define('EH8_ALLOW_V7_B2B_UAT_POSTING',true);
    if(!defined('EH8_B2B_TAX_POLICY_APPROVED'))define('EH8_B2B_TAX_POLICY_APPROVED',true);
    if(!defined('EH8_B2B_REVERSAL_POLICY_APPROVED'))define('EH8_B2B_REVERSAL_POLICY_APPROVED',true);
    if(!defined('EH8_B2B_TRUSTED_TENDER_APPROVED'))define('EH8_B2B_TRUSTED_TENDER_APPROVED',true);
    function context(array $changes=[]):array{return array_replace(['company_id'=>1,'branch_id'=>4,'actor_id'=>8,'retailer_id'=>12,'sale_intent_id'=>333,'idempotency_key'=>'safe-sale-key-123'],$changes);}
    function assessment(array $changes=[]):array{return array_replace([
        'assessment'=>'canonical_read_model_validated','posting_allowed'=>true,
        'company_id'=>1,'branch_id'=>4,'business_date'=>'2026-10-19',
        'channel'=>'counter','employee_id'=>null,'payment_mode'=>'cash','total_paise'=>30000,
        'paid_paise'=>30000,'retailer_outstanding_paise'=>0,'cogs_paise'=>12000,
        'canonical_account_ids'=>['BRANCH_CASH'=>25,'UPI_CLEARING'=>30,'EMPLOYEE_CASH_IN_TRANSIT'=>35,'SALES'=>40,'COGS'=>50,'INVENTORY'=>60],
        'lines'=>[['product_id'=>11,'batch_id'=>0,'qty_pcs'=>3,'canonical_stock_custodian'=>0,'commercial_revision_id'=>21,'unit_price_paise'=>10000,'line_total_paise'=>30000,'cogs_paise'=>12000]]],$changes);}
    function fixtures(array $changeA=[],array $changeQ=[],array $changeProof=[]):callable{
        return static function($a,$ctx,$db)use($changeA,$changeQ,$changeProof){
            $assessment=assessment($changeA);
            $saved=array_map(static fn(array $l):array=>['product_id'=>$l['product_id'],'batch_id'=>$l['batch_id'],
                'quantity_pcs'=>$l['qty_pcs'],'commercial_revision_id'=>$l['commercial_revision_id'],
                'unit_price_paise'=>$l['unit_price_paise'],'line_total_paise'=>$l['line_total_paise']],$assessment['lines']);
            $quote=array_replace(['sale_intent_id'=>333,'company_id'=>1,'branch_id'=>4,'retailer_id'=>12,
                'canonical_party_id'=>55,'invoice_total_paise'=>30000,'channel'=>$assessment['channel'],
                'employee_id'=>$assessment['employee_id'],'payment_mode'=>$assessment['payment_mode'],
                'saved_business_at'=>'2026-10-19 10:30:00','saved_lines'=>$saved,
                'currency'=>'INR','pricing_locked'=>true,'status'=>'awaiting_payment'],$changeQ);
            $quote['quote_digest']??=hash('sha256',json_encode(['company_id'=>$quote['company_id'],
                'branch_id'=>$quote['branch_id'],'retailer_id'=>$quote['retailer_id'],
                'canonical_party_id'=>$quote['canonical_party_id'],'channel'=>$quote['channel'],
                'employee_id'=>$quote['employee_id'],'business_at'=>$quote['saved_business_at'],
                'payment_mode'=>$quote['payment_mode'],'gross_paise'=>$quote['invoice_total_paise'],
                'lines'=>$quote['saved_lines']],JSON_THROW_ON_ERROR));
            $proof=array_replace(['id'=>77,'company_id'=>1,'branch_id'=>4,'sale_intent_id'=>333,
                'quote_digest'=>$quote['quote_digest'],'payment_mode'=>$assessment['payment_mode'],
                'verified_source'=>$assessment['payment_mode']==='upi'?'bank_settlement':($assessment['channel']==='field'?'employee_cash_custody':'branch_cashier_cash'),
                'amount_paise'=>30000,'consumed_sale_id'=>null,'currency'=>'INR','status'=>'confirmed'],$changeProof);
            return ['assessment'=>$assessment,'quote'=>$quote,'tender'=>$proof];
        };
    }
    function fresh(callable $reader=null,Actor $actor=null):array{
        Db::$db=new FakeWpdb();$GLOBALS['environment']='development';StockService::$fail=false;StockService::$costDrift=false;AccountingService::$fail=false;AccountingService::$closed=false;
        return [new V7CanonicalPostingSinkUat($actor??new Actor(),$reader??fixtures()),Db::$db];
    }
    function denied(string $needle,callable $fn):void{try{$fn();}catch(RetailerSaleError $e){if(!str_contains($e->getMessage(),$needle))throw new \RuntimeException('Expected '.$needle.' got '.$e->getMessage());return;}throw new \RuntimeException('Expected rejection '.$needle);}
    $tests=[];
    $tests['atomic success writes one canonical sale V7 stock and GL, one tender']=function(){[$writer,$d]=fresh();$x=$writer->post(context());assert($x['status']==='posted'&&$x['journal_id']===900);assert($d->stock['4-11-0']==7&&($d->rows['proof_consumed']??false)===true);assert(count($d->journals)===1&&$d->journals[900]['source']==='b2b_retailer_sale'&&$d->counts['sales']===1);};
    $tests['exact retry returns single receipt and does not move stock again']=function(){[$writer,$d]=fresh();$writer->post(context());$r=$writer->post(context());assert($r['replayed']===true&&$d->stock['4-11-0']==7&&$d->counts['sales']===1);};
    $tests['reuse key with different sale intent fails']=function(){[$writer,$d]=fresh();$writer->post(context());denied('reused',fn()=>$writer->post(context(['sale_intent_id'=>334])));assert($d->counts['sales']===1);};
    $tests['wrong actor replay cannot read paid receipt']=function(){[$writer,$d]=fresh();$writer->post(context());$other=new V7CanonicalPostingSinkUat(new Actor(10),fixtures());denied('reused',fn()=>$other->post(context(['actor_id'=>10])));};
    $tests['cannot use production WordPress even with all test flags']=function(){[$writer,$d]=fresh();$d->database='wordpress_live';denied('except v8_test',fn()=>$writer->post(context()));assert(!$d->rows);};
    $tests['only WordPress development environment is allowed']=function(){[$writer,$d]=fresh();$GLOBALS['environment']='production';denied('release gates',fn()=>$writer->post(context()));assert(!$d->rows);};
    $tests['malicious table prefix is blocked']=function(){[$writer,$d]=fresh();$d->prefix='wp_;DROP TABLE';denied('prefix',fn()=>$writer->post(context()));};
    $tests['wrong WordPress actor denied']=function(){[$writer,$d]=fresh();denied('actor mismatch',fn()=>$writer->post(context(['actor_id'=>99])));};
    $tests['branch scope denied']=function(){[$writer,$d]=fresh();denied('permission denied',fn()=>$writer->post(context(['branch_id'=>5])));};
    $tests['forged client quote amount cannot settle']=function(){[$writer,$d]=fresh(fixtures([],['invoice_total_paise'=>25000]));denied('differ',fn()=>$writer->post(context()));assert(!isset($d->rows['sales']));};
    $tests['wrong tender amount rolls back']=function(){[$writer,$d]=fresh(fixtures([],[],['amount_paise'=>20000]));denied('unconsumed',fn()=>$writer->post(context()));assert(!isset($d->rows['sales']));};
    $tests['UPI cannot use employee cash proof']=function(){[$writer,$d]=fresh(fixtures(['payment_mode'=>'upi'],[],['verified_source'=>'employee_cash_custody']));denied('unconsumed',fn()=>$writer->post(context()));};
    $tests['already consumed proof fails']=function(){[$writer,$d]=fresh(fixtures([],[],['consumed_sale_id'=>44]));denied('unconsumed',fn()=>$writer->post(context()));};
    $tests['closed accounting period denies']=function(){[$writer,$d]=fresh();AccountingService::$closed=true;denied('Period closed',fn()=>$writer->post(context()));assert(!isset($d->rows['sales']));};
    $tests['closed branch day denies']=function(){[$writer,$d]=fresh();$d->closedDay=true;denied('closed branch day',fn()=>$writer->post(context()));};
    $tests['old customer outstanding credit denies']=function(){[$writer,$d]=fresh();$d->openCredit=true;denied('legacy credit',fn()=>$writer->post(context()));};
    $tests['unlinked or inactive canonical customer denies']=function(){[$writer,$d]=fresh();$d->badParty=true;denied('active canonical V7 customer',fn()=>$writer->post(context()));};
    $tests['stock failure rolls back source and proof']=function(){[$writer,$d]=fresh();StockService::$fail=true;denied('stock failure',fn()=>$writer->post(context()));assert(($d->stock['4-11-0']??0)===10&&!isset($d->rows['sales'])&&!isset($d->rows['proof_consumed']));};
    $tests['journal failure rolls back entire sale stock and proof']=function(){[$writer,$d]=fresh();AccountingService::$fail=true;denied('journal failure',fn()=>$writer->post(context()));assert($d->stock['4-11-0']==10&&!isset($d->rows['sales'])&&!isset($d->rows['proof_consumed']));};
    $tests['moving average COGS mismatch rolls back']=function(){[$writer,$d]=fresh();StockService::$costDrift=true;denied('cost changed',fn()=>$writer->post(context()));assert($d->stock['4-11-0']==10&&!isset($d->rows['sales']));};
    $tests['source finalization failure rolls back']=function(){[$writer,$d]=fresh();$d->failFinalize=true;denied('finalization failed',fn()=>$writer->post(context()));assert($d->stock['4-11-0']==10&&!isset($d->rows['proof_consumed']));};
    $tests['field Cash moves employee stock and journal tags employee transit']=function(){[$writer,$d]=fresh(fixtures(['channel'=>'field','employee_id'=>42,'canonical_account_ids'=>assessment()['canonical_account_ids'],'lines'=>[['product_id'=>11,'batch_id'=>0,'qty_pcs'=>3,'canonical_stock_custodian'=>42,'commercial_revision_id'=>21,'unit_price_paise'=>10000,'line_total_paise'=>30000,'cogs_paise'=>12000]]]));$r=$writer->post(context());assert($r['employee_cash_to_remit_paise']===30000&&$d->stock['4-11-42']==7&&$d->stock['4-11-0']==10);$j=$d->journals[900]['lines'][0];assert($j['party_type']==='employee'&&$j['party_id']===42&&$j['account_id']===35);};
    $tests['UPI uses clearing account, never employee cash ledger']=function(){[$writer,$d]=fresh(fixtures(['payment_mode'=>'upi']));$writer->post(context());$line=$d->journals[900]['lines'][0];assert($line['account_id']===30&&!isset($line['party_type']));};
    $tests['fresh locked assessment with posting denied stops writes']=function(){[$writer,$d]=fresh(fixtures(['posting_allowed'=>false]));denied('differ',fn()=>$writer->post(context()));assert(!isset($d->rows['sales']));};
    $tests['no authenticated lockedReader callback denied']=function(){try{new V7CanonicalPostingSinkUat(new Actor(),'not-a-callable');}catch(RetailerSaleError){return;}throw new \RuntimeException('Callable guard not enforced');};
    $tests['changed stock item rejected even if total same']=function(){[$writer,$d]=fresh(fixtures([],['saved_lines'=>[['product_id'=>99,'batch_id'=>0,'quantity_pcs'=>3,'commercial_revision_id'=>21,'unit_price_paise'=>10000,'line_total_paise'=>30000]]]));denied('Persisted product',fn()=>$writer->post(context()));assert(!isset($d->rows['sales']));};
    $tests['changed commercial revision rejected']=function(){[$writer,$d]=fresh(fixtures([],['saved_lines'=>[['product_id'=>11,'batch_id'=>0,'quantity_pcs'=>3,'commercial_revision_id'=>22,'unit_price_paise'=>10000,'line_total_paise'=>30000]]]));denied('commercial price revision',fn()=>$writer->post(context()));};
    $tests['modified quote digest rejected']=function(){[$writer,$d]=fresh(fixtures([],['quote_digest'=>str_repeat('b',64)]));denied('digest',fn()=>$writer->post(context()));};
    $tests['missing immutable product lines rejected']=function(){[$writer,$d]=fresh(fixtures([],['saved_lines'=>[]]));denied('saved business time',fn()=>$writer->post(context()));};
    $tests['changed saved business date rejected']=function(){[$writer,$d]=fresh(fixtures([],['saved_business_at'=>'2026-10-18 10:30:00']));denied('saved business time',fn()=>$writer->post(context()));};
    $tests['unpriced quote state cannot post']=function(){[$writer,$d]=fresh(fixtures([],['pricing_locked'=>false]));denied('Immutable quote',fn()=>$writer->post(context()));};
    $tests['unsigned tender staging state cannot post']=function(){[$writer,$d]=fresh(fixtures([],[],['status'=>'awaiting_payment']));denied('unconsumed',fn()=>$writer->post(context()));};
    $tests['non-INR tender cannot post']=function(){[$writer,$d]=fresh(fixtures([],[],['currency'=>'USD']));denied('unconsumed',fn()=>$writer->post(context()));};
    $tests['money uses canonical V7 Cash Sales COGS Inventory double entry']=function(){[$writer,$d]=fresh();$writer->post(context());$j=$d->journals[900]['lines'];assert(count($j)===4&&array_sum(array_column($j,'debit'))===array_sum(array_column($j,'credit')));assert($j[0]['debit']===300&&$j[1]['credit']===300&&$j[2]['debit']===120);};
    $passed=0;foreach($tests as $name=>$fn){try{$fn();$passed++;}catch(\Throwable $e){fwrite(STDERR,"FAIL: $name: ".$e->getMessage()."\n");exit(1);}}echo "PASS {$passed}/".count($tests)." V7 canonical UAT writer isolated regression tests\n";
}
