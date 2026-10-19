<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP7\Domain {
    final class DomainException extends \RuntimeException {
        public function __construct(string $message,public string $codeKey='error',public int $httpStatus=422){parent::__construct($message);}
    }
}
namespace ExcelHerbal\ERP7\Security {
    final class Capabilities {const EMP_VIEW='organization.employee.view'; const ACCOUNTING_VIEW='finance.accounting.view';}
    final class Actor {
        public function __construct(public int $userId,public int $employeeId,public int $companyId,public int $assignedBranchId,public array $branchIds,public array $capabilities,public string $designationCode){}
        public function can(string $c):bool{return in_array($c,$this->capabilities,true);}
        public function hasBranch(int $b):bool{return in_array($b,$this->branchIds,true);}
    }
    final class HierarchyScope {
        public static bool $allow=true;
        public static function assertCanViewEmployee(Actor $a,int $target):void {if(!self::$allow)throw new \ExcelHerbal\ERP7\Domain\DomainException('Hierarchy denied','employee_scope_forbidden',403);}
    }
}
namespace ExcelHerbal\ERP7\Core {
    final class Input {
        public static function utcBoundsForBusinessRange(string $from,string $to,string $name):array {
            return [$from.' 00:00:00',(new \DateTimeImmutable($to))->modify('+1 day')->format('Y-m-d').' 00:00:00'];
        }
    }
}
namespace ExcelHerbal\ERP7\Database {
    final class Db {
        public static object $stub;
        public static function wpdb():object{return self::$stub;}
        public static function table(string $name):string{return 'wp_eh7_'.$name;}
    }
}
namespace {
    require_once __DIR__.'/../src/Organization/Employee360Service.php';
    require_once __DIR__.'/../src/Organization/Employee360Registers.php';
    use ExcelHerbal\ERP7\Organization\{Employee360Reader,Employee360Registers,Employee360RegisterReader,Employee360WpRegisterReader};
    use ExcelHerbal\ERP7\Security\{Actor,Capabilities,HierarchyScope};
    use ExcelHerbal\ERP7\Domain\DomainException;
    use ExcelHerbal\ERP7\Database\Db;

    $GLOBALS['pass']=0;
    function okay(bool $yes,string $message):void {if(!$yes)throw new \RuntimeException('FAIL: '.$message);$GLOBALS['pass']++;}
    function denied(callable $fn,string $code):void {try{$fn();throw new \RuntimeException('Expected denial '.$code);}catch(DomainException $e){okay($e->codeKey===$code,'denied '.$code);}}
    class ProfileReaderFake implements Employee360Reader {
        public ?array $profile=['id'=>7,'company_id'=>1,'employee_code'=>'F7','full_name'=>'Person','designation_code'=>'FSE','assigned_branch_id'=>2,'status'=>'active'];
        public function employee(int $c,int $id):?array{return $this->profile;}
        public function sales(int $c,int $id,string $f,string $t,array $b):array{return [];}
        public function performance(int $c,int $id,string $f,string $t,array $b):array{return [];}
        public function attendance(int $c,int $id,string $f,string $t,array $b):array{return [];}
        public function stock(int $c,int $id,array $b):array{return [];}
        public function ledger(int $c,int $id,string $f,string $t,array $b):array{return [];}
    }
    class RegisterFake implements Employee360RegisterReader {
        public array $calls=[], $fakeRows=[];
        public function sales(int $c,int $e,string $f,string $t,array $branches,int $limit,int $offset):array {
            $this->calls[]=['sales',$c,$e,$f,$t,$branches,$limit,$offset];return $this->fakeRows;
        }
        public function stock(int $c,int $e,string $f,string $t,array $branches,int $limit,int $offset):array {
            $this->calls[]=['stock',$c,$e,$f,$t,$branches,$limit,$offset];return $this->fakeRows;
        }
    }
    $self=new Actor(17,7,1,2,[2],[],'FSE');
    $profile=new ProfileReaderFake();$reg=new RegisterFake();
    $reg->fakeRows=[['daily_cycle_id'=>3],['daily_cycle_id'=>2],['daily_cycle_id'=>1]];
    $a=Employee360Registers::view($self,7,'sales','2026-10-01','2026-10-19',1,2,$reg,$profile);
    okay($a['read_only']===true,'read-only sales');
    okay($a['register']==='sales','sales type');
    okay($a['has_more']===true&&count($a['rows'])===2,'sentinel pagination');
    okay($reg->calls[0][0]==='sales','sales reader called');
    okay($reg->calls[0][5]===[],'self can see own transferred-branch history');
    okay($reg->calls[0][6]===3&&$reg->calls[0][7]===0,'limit+1 and offset');
    okay($a['financial_custody_reconciliation']!=='settled','no invented cash remittance');
    $next=Employee360Registers::view($self,7,'stock','2026-10-01','2026-10-19',2,2,$reg,$profile);
    okay($next['register']==='stock'&&$reg->calls[1][0]==='stock','stock only custodian movement');
    okay($reg->calls[1][7]===2,'page 2 offset');
    $manager=new Actor(50,22,1,2,[2,4],[Capabilities::EMP_VIEW],'BM');
    Employee360Registers::view($manager,7,'stock','2026-10-01','2026-10-19',1,50,$reg,$profile);
    okay($reg->calls[2][5]===[2,4],'manager limited to authorized branches');
    denied(fn()=>Employee360Registers::view(new Actor(50,22,1,2,[2],[],'FSE'),7,'sales','2026-10-01','2026-10-19',1,50,$reg,$profile),'permission_denied');
    denied(fn()=>Employee360Registers::view(new Actor(50,22,1,4,[4],[Capabilities::EMP_VIEW],'BM'),7,'sales','2026-10-01','2026-10-19',1,50,$reg,$profile),'branch_forbidden');
    HierarchyScope::$allow=false;
    denied(fn()=>Employee360Registers::view($manager,7,'sales','2026-10-01','2026-10-19',1,50,$reg,$profile),'employee_scope_forbidden');
    HierarchyScope::$allow=true;
    $foreign=new ProfileReaderFake();$foreign->profile['company_id']=2;
    denied(fn()=>Employee360Registers::view($self,7,'stock','2026-10-01','2026-10-19',1,50,$reg,$foreign),'employee_not_found');
    $wrong=new ProfileReaderFake();$wrong->profile['id']=8;
    denied(fn()=>Employee360Registers::view($self,7,'stock','2026-10-01','2026-10-19',1,50,$reg,$wrong),'employee_not_found');
    denied(fn()=>Employee360Registers::view($self,7,'unknown','2026-10-01','2026-10-19',1,50,$reg,$profile),'register_type_invalid');
    denied(fn()=>Employee360Registers::view($self,7,'sales','2026-13-01','2026-10-19',1,50,$reg,$profile),'date_invalid');
    denied(fn()=>Employee360Registers::view($self,7,'sales','2026-10-19','2026-10-01',1,50,$reg,$profile),'period_invalid');
    denied(fn()=>Employee360Registers::view($self,7,'sales','2026-10-01','2026-10-19',0,50,$reg,$profile),'register_pagination_invalid');
    denied(fn()=>Employee360Registers::view($self,7,'sales','2026-10-01','2026-10-19',1,101,$reg,$profile),'register_pagination_invalid');

    $stub=new class {
        public array $q=[];
        public function prepare($sql,...$args):string{$this->q[]=[$sql,$args];return preg_replace_callback('/%[dsf]/',function($m)use(&$args){$x=array_shift($args);return $m[0]==='%d'?(string)(int)$x:"'".str_replace("'","''",(string)$x)."'";},$sql);}
        public function get_results(string $sql,$kind):array{return [];}
    };
    if(!defined('ARRAY_A'))define('ARRAY_A','ARRAY_A');Db::$stub=$stub;
    $db=new Employee360WpRegisterReader();
    $db->sales(1,7,'2026-10-01','2026-10-19',[2,4],51,100);
    $db->stock(1,7,'2026-10-01','2026-10-19',[2],20,0);
    okay(count($stub->q)===2,'two parameterized source queries');
    $salesSql=$stub->q[0][0];
    okay(str_contains($salesSql,"c.status='completed'")&&str_contains($salesSql,"es.status='posted'"),'only posted daily cycles');
    okay(str_contains($salesSql,'LEFT JOIN wp_eh7_evening_lines'),'cycle level aggregation no duplicated settlement totals');
    okay(str_contains($salesSql,'GROUP BY c.id'),'one summary row per daily cycle');
    okay(str_contains($salesSql,'c.branch_id IN (%d,%d)'),'branch scope in sales SQL');
    okay($stub->q[0][1]===[1,7,'2026-10-01','2026-10-19',2,4,51,100],'sales SQL params bound');
    $stockSql=$stub->q[1][0];
    okay(str_contains($stockSql,'sl.custodian_employee_id=%d'),'stock ledger custodian scoped');
    okay(str_contains($stockSql,"sl.direction IN ('IN','OUT')"),'in and out movement');
    okay(str_contains($stockSql,'sl.occurred_at>=%s AND sl.occurred_at<%s'),'UTC stock time bounds');
    okay(str_contains($stockSql,'sl.branch_id IN (%d)'),'stock manager branch scoped');
    okay(!str_contains($stockSql,'unit_cost')&&!str_contains($stockSql,'average_unit_cost'),'no cost price leak');
    okay($stub->q[1][1]===[1,7,'2026-10-01 00:00:00','2026-10-20 00:00:00',2,20,0],'stock UTC bound args');
    $testText=file_get_contents(__DIR__.'/../src/Organization/Employee360Registers.php');
    okay(str_contains($testText,'financial_custody_reconciliation')&&!str_contains($testText,'cash_remittance_completed'),'no fictitious cash settlement');
    echo 'PASS '.$GLOBALS['pass'].'/'.$GLOBALS['pass']." Employee360 detailed sales and stock registers\n";
}