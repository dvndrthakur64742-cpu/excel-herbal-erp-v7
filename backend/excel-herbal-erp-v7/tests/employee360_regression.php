<?php
declare(strict_types=1);

namespace ExcelHerbal\ERP7\Domain {
    class DomainException extends \RuntimeException {
        public function __construct(string $message,public string $codeKey='error',public int $httpStatus=422){parent::__construct($message);}
    }
}
namespace ExcelHerbal\ERP7\Security {
    final class Capabilities {const EMP_VIEW='employee.view'; const ACCOUNTING_VIEW='finance.accounting.view';}
    final class Actor {
        public function __construct(public int $userId,public int $employeeId,public int $companyId,public int $assignedBranchId,public array $branchIds,public array $capabilities,public string $designationCode){}
        public function can(string $cap):bool{return in_array($cap,$this->capabilities,true);}
        public function hasBranch(int $id):bool{return in_array($id,$this->branchIds,true);}
    }
    final class HierarchyScope {
        public static bool $allow=true;
        public static function assertCanViewEmployee(Actor $a,int $employeeId):void {if(!self::$allow)throw new \ExcelHerbal\ERP7\Domain\DomainException('Hierarchy denied','employee_scope_forbidden',403);}
    }
}
namespace ExcelHerbal\ERP7\Database {
    final class Db {
        public static object $wpdb;
        public static function wpdb():object{return self::$wpdb;}
        public static function table(string $name):string{return 'wp_eh7_'.$name;}
    }
}
namespace {
    require_once __DIR__.'/../src/Organization/Employee360Service.php';
    use ExcelHerbal\ERP7\Organization\{Employee360Service,Employee360Reader,Employee360WpReader};
    use ExcelHerbal\ERP7\Security\{Actor,Capabilities,HierarchyScope};
    use ExcelHerbal\ERP7\Domain\DomainException;
    use ExcelHerbal\ERP7\Database\Db;
    final class Memory360 implements Employee360Reader {
        public ?array $person=['id'=>10,'company_id'=>1,'employee_code'=>'EMP10','full_name'=>'Example','designation_code'=>'FSE','assigned_branch_id'=>2,'status'=>'active'];
        public array $calls=[];
        public function employee(int $company,int $id):?array {$this->calls[]=['employee',$company,$id];return $this->person;}
        public function sales(int $c,int $e,string $f,string $t,array $b):array {$this->calls[]=['sales',$b];return [['month'=>'2026-10','sale_amount'=>'500.00'],['month'=>'2026-09','sale_amount'=>'300.00']];}
        public function performance(int $c,int $e,string $f,string $t,array $b):array {$this->calls[]=['performance',$b];return [['month'=>'2026-10','points'=>'12.00'],['month'=>'2026-08','points'=>'4.00']];}
        public function attendance(int $c,int $e,string $f,string $t,array $b):array {$this->calls[]=['attendance',$b];return [['business_date'=>'2026-10-18','status'=>'present'],['business_date'=>'2026-10-17','status'=>'absent'],['business_date'=>'2026-09-15','status'=>'late']];}
        public function stock(int $c,int $e,array $b):array {$this->calls[]=['stock',$b];return [['branch_id'=>2,'product_id'=>7,'quantity'=>'3.000']];}
        public function ledger(int $c,int $e,string $f,string $t,array $b):array {$this->calls[]=['ledger',$b];return [['entry_no'=>'JE-42','debit'=>'100.00','credit'=>'0.00']];}
    }
    function assertion(bool $ok,string $case):void {if(!$ok)throw new \RuntimeException('FAIL '.$case);$GLOBALS['passed']++;}
    function denies(callable $fn,string $expected):void {try{$fn();throw new \RuntimeException('Expected denied '.$expected);}catch(DomainException $e){assertion($e->codeKey===$expected,'denies '.$expected);}}
    $GLOBALS['passed']=0;
    $self=new Actor(20,10,1,2,[2],[],'FSE');
    $source=new Memory360();
    $res=Employee360Service::view($self,10,'2026-08-01','2026-10-19',$source);
    assertion($res['read_only']===true,'read only');
    assertion($res['dashboard_unchanged']===true,'dashboard remains protected');
    assertion($res['employee']['id']===10,'employee projection');
    assertion($res['monthly_summary'][0]['month']==='2026-10','months descending');
    assertion($res['monthly_summary'][0]['sales_amount']==='500.00','sales not added to points');
    assertion($res['monthly_summary'][0]['points']==='12.00','points separate');
    assertion($res['monthly_summary'][0]['days_present']===1,'attendance present counted');
    assertion($res['monthly_summary'][1]['month']==='2026-09','second month');
    assertion($res['monthly_summary'][1]['days_present']===1,'late counted');
    assertion($res['monthly_summary'][2]['points']==='4.00','points only month retained');
    assertion($res['person_ledger']['visible']===false,'account journal confidential');
    assertion($res['person_ledger']['entries']===[],'no GL for employee');
    assertion(!in_array('ledger',array_column($source->calls,0),true),'no ledger query without authority');
    assertion($res['cash_reconciliation']!=='settled','no phantom employee cash settlement');
    assertion($res['gps_route']==='use_existing_authorized_workforce_gps_route_endpoint','reuse GPS API');
    assertion($source->calls[1][1]===[],'own branch transfer history unrestricted');
    $manager=new Actor(30,19,1,2,[2],[Capabilities::EMP_VIEW,Capabilities::ACCOUNTING_VIEW],'BM');
    $s2=new Memory360();
    $r2=Employee360Service::view($manager,10,'2026-09-01','2026-10-19',$s2);
    assertion($r2['person_ledger']['visible']===true,'accounting manager ledger');
    assertion(count($r2['person_ledger']['entries'])===1,'manager tagged journal');
    assertion($s2->calls[1][1]===[2],'manager branch scope propagated');
    $other=new Actor(31,18,1,2,[2],[],'FSE');
    denies(fn()=>Employee360Service::view($other,10,'2026-10-01','2026-10-19',new Memory360()),'permission_denied');
    $wrongBranch=new Actor(31,18,1,3,[3],[Capabilities::EMP_VIEW],'BM');
    denies(fn()=>Employee360Service::view($wrongBranch,10,'2026-10-01','2026-10-19',new Memory360()),'branch_forbidden');
    HierarchyScope::$allow=false;
    denies(fn()=>Employee360Service::view($manager,10,'2026-10-01','2026-10-19',new Memory360()),'employee_scope_forbidden');
    HierarchyScope::$allow=true;
    $cross=new Memory360();$cross->person['company_id']=77;
    denies(fn()=>Employee360Service::view($self,10,'2026-10-01','2026-10-19',$cross),'employee_not_found');
    $unknown=new Memory360();$unknown->person=null;
    denies(fn()=>Employee360Service::view($self,10,'2026-10-01','2026-10-19',$unknown),'employee_not_found');
    denies(fn()=>Employee360Service::view($self,0,'2026-10-01','2026-10-19',new Memory360()),'employee_id_invalid');
    denies(fn()=>Employee360Service::view($self,10,'2026-02-30','2026-10-19',new Memory360()),'date_invalid');
    denies(fn()=>Employee360Service::view($self,10,'2026-11-01','2026-10-19',new Memory360()),'period_invalid');
    denies(fn()=>Employee360Service::view($self,10,'2024-01-01','2026-10-19',new Memory360()),'period_invalid');
    // The repository SQL must preserve company, employee, branch and posted filters.
    $stub=new class {
        public array $queries=[];
        public function prepare($query,...$args):string {
            $this->queries[]=[$query,$args];
            $i=0;return preg_replace_callback('/%[dsf]/',function($m) use (&$i,$args){$v=$args[$i++]??null;return $m[0]==='%d'?(string)(int)$v:"'".str_replace("'","''",(string)$v)."'";},$query);
        }
        public function get_results($q,$mode):array{return [];}
    };
    Db::$wpdb=$stub;
    if(!defined('ARRAY_A'))define('ARRAY_A','ARRAY_A');
    $dbReader=new Employee360WpReader();
    $dbReader->sales(1,10,'2026-10-01','2026-10-19',[2,3]);
    $dbReader->performance(1,10,'2026-10-01','2026-10-19',[2]);
    $dbReader->attendance(1,10,'2026-10-01','2026-10-19',[2]);
    $dbReader->stock(1,10,[2]);
    $dbReader->ledger(1,10,'2026-10-01','2026-10-19',[2]);
    assertion(count($stub->queries)===5,'five register reads');
    assertion(str_contains($stub->queries[0][0],"es.status='posted'")&&str_contains($stub->queries[0][0],"c.status='completed'"),'only posted completed sales');
    assertion(str_contains($stub->queries[0][0],'c.branch_id IN (%d,%d)'),'sales manager branch guard');
    assertion($stub->queries[0][1]===[1,10,'2026-10-01','2026-10-19',2,3],'bound SQL parameters');
    assertion(str_contains($stub->queries[1][0],'wp_eh7_performance_entries'),'performance ledger source');
    assertion(str_contains($stub->queries[2][0],'wp_eh7_attendance'),'attendance source');
    assertion(str_contains($stub->queries[3][0],'s.custodian_key=%d'),'employee custody scoped');
    assertion(str_contains($stub->queries[4][0],"l.party_type='employee'") && str_contains($stub->queries[4][0],"j.status='posted'"),'tagged posted ledger only');
    assertion(str_contains($stub->queries[4][0],'j.branch_id IN (%d)'),'GL branch guard');

    require_once __DIR__.'/../src/Organization/Employee360PersonLedger.php';
    $personSource=new class implements \ExcelHerbal\ERP7\Organization\EmployeePersonLedgerReader {
        public array $calls=[];
        public array $events=[
            ['event_type'=>'gl','event_id'=>8,'branch_id'=>2,'debit'=>'200.00','credit'=>'0.00'],
            ['event_type'=>'stock','event_id'=>7,'branch_id'=>2,'qty_in'=>'5.000','qty_out'=>'0.000'],
            ['event_type'=>'points','event_id'=>6,'branch_id'=>2,'points'=>'7.00'],
        ];
        public array $fin=[
            ['account_id'=>4,'account_code'=>'EMPLOYEE_CASH_IN_TRANSIT',
             'opening_delta'=>'50.00','period_debit'=>'200.00','period_credit'=>'100.00'],
        ];
        public array $stock=[
            ['branch_id'=>2,'product_id'=>11,'batch_key'=>201,
             'opening_quantity'=>'2.000','period_in'=>'5.000','period_out'=>'3.000'],
        ];
        public function events(int $c,int $e,string $f,string $t,array $b,int $limit,int $offset):array {
            $this->calls[]=['events',$c,$e,$f,$t,$b,$limit,$offset];
            return array_slice($this->events,$offset,$limit);
        }
        public function financialBalances(int $c,int $e,string $f,string $t,array $b):array {
            $this->calls[]=['financial',$c,$e,$f,$t,$b];
            return $this->fin;
        }
        public function stockBalances(int $c,int $e,string $f,string $t,array $b):array {
            $this->calls[]=['stock',$c,$e,$f,$t,$b];
            return $this->stock;
        }
    };
    $person=\ExcelHerbal\ERP7\Organization\Employee360PersonLedger::view(
        $manager,10,'2026-10-01','2026-10-19',1,2,$personSource,new Memory360());
    assertion($person['register']==='person_ledger'&&$person['read_only'],'Tally person ledger read only');
    assertion($person['has_more']===true&&count($person['rows'])===2,'unified cross-source pagination');
    assertion($person['financial_accounts'][0]['opening_debit_minus_credit']==='50.00'
        &&$person['financial_accounts'][0]['closing_debit_minus_credit']==='150.00',
        'GL opening + debits - credits yields closing INR per account');
    assertion($person['stock_items'][0]['closing_quantity']==='4.000',
        'PCS opening + IN - OUT yields stock closing per batch');
    assertion($person['employee_cash_handover_verified']===false
        &&$person['upi_bank_settlement_verified']===false
        &&$person['physical_stock_verified']===false,
        'financial and inventory balances never claim physical verification');
    assertion($personSource->calls[0][5]===[2] &&$personSource->calls[0][6]===3
        &&$personSource->calls[0][7]===0,'globally paginated finance manager branch scope');
    $pageTwo=\ExcelHerbal\ERP7\Organization\Employee360PersonLedger::view(
        $manager,10,'2026-10-01','2026-10-19',2,2,$personSource,new Memory360());
    assertion(count($pageTwo['rows'])===1
        &&$pageTwo['financial_accounts'][0]['closing_debit_minus_credit']==='150.00',
        'balances derived from entire authorized history, not visible page');
    denies(fn()=>\ExcelHerbal\ERP7\Organization\Employee360PersonLedger::view(
        $self,10,'2026-10-01','2026-10-19',1,2,$personSource,new Memory360()),'permission_denied');
    denies(fn()=>\ExcelHerbal\ERP7\Organization\Employee360PersonLedger::view(
        $wrongBranch,10,'2026-10-01','2026-10-19',1,2,$personSource,new Memory360()),'branch_forbidden');
    $personSource->events=[['event_type'=>'gl','event_id'=>8,'branch_id'=>99]];
    denies(fn()=>\ExcelHerbal\ERP7\Organization\Employee360PersonLedger::view(
        $manager,10,'2026-10-01','2026-10-19',1,2,$personSource,new Memory360()),'person_ledger_source_invalid');
    $personSource->events=[];
    $personSource->fin[0]['period_debit']='1.234';
    denies(fn()=>\ExcelHerbal\ERP7\Organization\Employee360PersonLedger::view(
        $manager,10,'2026-10-01','2026-10-19',1,2,$personSource,new Memory360()),'person_ledger_source_invalid');
    $personSource->fin[0]['period_debit']='200.00';
    $personSource->stock[0]['opening_quantity']='-2.000';
    $negative=\ExcelHerbal\ERP7\Organization\Employee360PersonLedger::view(
        $manager,10,'2026-10-01','2026-10-19',1,2,$personSource,new Memory360());
    assertion($negative['stock_items'][0]['closing_quantity']==='0.000','signed opening stock balances supported');
    $personSource->stock[0]['opening_quantity']='2.000';
    denies(fn()=>\ExcelHerbal\ERP7\Organization\Employee360PersonLedger::view(
        $manager,10,'2026-10-01','2026-10-19',0,2,$personSource,new Memory360()),'register_pagination_invalid');
    $registerSource=file_get_contents(__DIR__.'/../src/Organization/Employee360Registers.php');
    assertion(str_contains($registerSource,"if(".'$type'."==='person_ledger')") && str_contains($registerSource,"Employee360PersonLedger::view("),
        'existing authorized Employee 360 register route dispatches Tally person ledger');

    echo 'PASS '.$GLOBALS['passed'].'/'. $GLOBALS['passed']." Employee360 role, finance, branch, posted-source and profile regressions\n";
}