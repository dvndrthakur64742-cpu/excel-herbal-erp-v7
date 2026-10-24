<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP7\Domain {
    final class DomainException extends \RuntimeException {
        public function __construct(string $message, public string $codeKey='error', public int $httpStatus=422){parent::__construct($message);}
    }
}
namespace ExcelHerbal\ERP7\Security {
    final class Capabilities {const EMP_VIEW='organization.employee.view';const ACCOUNTING_VIEW='finance.accounting.view';}
    final class Actor {
        public function __construct(public int $userId,public int $employeeId,public int $companyId,public int $assignedBranchId,public array $branchIds,public array $capabilities,public string $designationCode){}
        public function can(string $c):bool{return in_array($c,$this->capabilities,true);}
        public function hasBranch(int $b):bool{return in_array($b,$this->branchIds,true);}
    }
    final class HierarchyScope {
        public static bool $allow=true;
        public static function assertCanViewEmployee(Actor $a,int $target):void{if(!self::$allow)throw new \ExcelHerbal\ERP7\Domain\DomainException('Outside hierarchy','employee_scope_forbidden',403);}
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
    require_once __DIR__.'/../src/Organization/EmployeeCashControl.php';
    use ExcelHerbal\ERP7\Organization\{Employee360Reader,EmployeeCashControl,EmployeeCashControlReader,EmployeeCashControlWpReader};
    use ExcelHerbal\ERP7\Security\{Actor,Capabilities,HierarchyScope};
    use ExcelHerbal\ERP7\Domain\DomainException;
    use ExcelHerbal\ERP7\Database\Db;
    $pass=0;
    function ok(bool $v,string $m):void{global $pass;if(!$v)throw new \RuntimeException('FAIL: '.$m);$pass++;}
    function deny(callable $f,string $code):void{try{$f();throw new \RuntimeException('Expected denial '.$code);}catch(DomainException $e){ok($e->codeKey===$code,'reject '.$code);}}
    class ProfileFake implements Employee360Reader {
        public ?array $value=['id'=>7,'company_id'=>1,'assigned_branch_id'=>2];
        public function employee(int $c,int $id):?array{return $this->value;}
        public function sales(int $c,int $id,string $f,string $t,array $b):array{return [];}
        public function performance(int $c,int $id,string $f,string $t,array $b):array{return [];}
        public function attendance(int $c,int $id,string $f,string $t,array $b):array{return [];}
        public function stock(int $c,int $id,array $b):array{return [];}
        public function ledger(int $c,int $id,string $f,string $t,array $b):array{return [];}
    }
    class CashFake implements EmployeeCashControlReader {
        public array $calls=[], $rows=[];
        public function posted(int $c,int $e,string $f,string $t,array $b,int $limit,int $offset):array{
            $this->calls[]=[$c,$e,$f,$t,$b,$limit,$offset];return $this->rows;
        }
    }
    function row(int $id,int $branch=2,string $cash='120.25',string $upi='20.00',string $total='140.25',string $glCash='120.25',string $glUpi='20.00',int $journals=1,array $override=[]):array{
       $base=['daily_cycle_id'=>$id,'branch_id'=>$branch,'business_date'=>'2026-10-19',
           'cash_amount'=>$cash,'upi_amount'=>$upi,'expected_amount'=>$total,
           'gl_cash_debit'=>$glCash,'gl_upi_debit'=>$glUpi,'gl_cash_credit'=>'0.00',
           'gl_upi_credit'=>'0.00','gl_sales_credit'=>$total,
           'gl_cogs_debit'=>'0.00','gl_inventory_credit'=>'0.00',
           'gl_unexpected_amount'=>'0.00',
           'gl_total_debit'=>number_format((float)$glCash+(float)$glUpi,2,'.',''),
           'gl_total_credit'=>$total,'gl_orphan_account_lines'=>0,'journal_count'=>$journals];
       return array_replace($base,$override);
    }
    $self=new Actor(12,7,1,2,[2],[Capabilities::ACCOUNTING_VIEW],'FSE');
    $m=new Actor(33,2,1,2,[2],[Capabilities::ACCOUNTING_VIEW,Capabilities::EMP_VIEW],'BM');
    $fake=new CashFake();$profile=new ProfileFake();
    $fake->rows=[row(10),row(11,2,'0.00','45.00','45.00','0.00','45.00'),row(12)];
    $out=EmployeeCashControl::view($self,7,'2026-10-01','2026-10-19',1,2,$fake,$profile);
    ok($out['read_only']===true,'read-only cash control');
    ok($out['has_more']&&count($out['rows'])===2,'pagination sentinel');
    ok($fake->calls[0] === [1,7,'2026-10-01','2026-10-19',[],3,0],'self all historical branches');
    ok($out['rows'][0]['journal_check']==='journal_amounts_match','cash, UPI, sales and full GL matched');
    ok($out['rows'][0]['journal_balanced']===true&&$out['rows'][0]['journal_sales_credit_reconcile']===true,
       'GL debit/credit and SALES credit explicitly validated');
    ok($out['rows'][0]['cash_remittance_proof']==='not_evidenced_in_legacy_v7','no invented cash remittance confirmation');
    ok($out['rows'][0]['legacy_direct_branch_cash_posting']===true,'legacy branch journal disclosed');
    ok($out['rows'][1]['cash_remittance_proof']==='not_applicable','no cash custody if cash is zero');
    ok($out['rows'][1]['upi_bank_settlement_proof']==='not_verified_by_this_report','upi not independently settled');
    ok($out['page_totals']['cash_reported_paise']===12025&&$out['page_totals']['upi_reported_paise']===6500,'exact money totals');
    ok($out['page_flags']['cash_remittance_unproven_count']===1,'only positive cash flagged');
    ok($out['page_flags']['journal_mismatch_count']===0,'all journal amounts matched');
    ok($out['page_flags']['upi_bank_unproven_count']===2,
       'only page-visible UPI-positive closings flagged without independent bank proof');
    ok($out['page_evidence_gaps']['cash_without_independent_receipt_paise']===12025
        &&$out['page_evidence_gaps']['upi_without_bank_confirmation_paise']===6500,
       'independent receipt/UPI proof gaps are booked values only, never double-counted GL');
    ok($out['page_evidence_gaps']['interpretation']==='booked_tenders_without_independent_proof_not_outstanding'
       &&$out['page_evidence_gaps']['basis']==='canonical_daily_order_page_only',
       'no debt, employee liability, physical remittance, PSP deposit or cross-source total inferred');
    $fake->rows=[row(14,2,'120.25','0.00','120.25','90.00','0.00')];
    $mismatch=EmployeeCashControl::view($m,7,'2026-10-01','2026-10-19',2,1,$fake,$profile);
    ok($mismatch['rows'][0]['journal_check']==='journal_amount_mismatch','posted journal mismatch surfaced');
    ok($mismatch['page_flags']['journal_mismatch_count']===1,'journal mismatch counted');
    ok($fake->calls[1]===[1,7,'2026-10-01','2026-10-19',[2],2,1],'manager scoped plus pagination');
    $fake->rows=[row(14,2,'120.25','0.00','120.25','0.00','0.00',0)];
    $missing=EmployeeCashControl::view($self,7,'2026-10-01','2026-10-19',1,50,$fake,$profile);
    ok($missing['rows'][0]['journal_check']==='missing_journal','missing journal flagged');
    $fake->rows=[row(14,2,'120.25','0.00','120.25','120.25','0.00',2)];
    $dup=EmployeeCashControl::view($self,7,'2026-10-01','2026-10-19',1,50,$fake,$profile);
    ok($dup['rows'][0]['journal_check']==='duplicate_journal','duplicate journal flagged');
    $fake->rows=[row(15,2,'120.25','20.00','140.25','120.25','20.00',1,
        ['gl_cash_credit'=>'1.00','gl_total_debit'=>'141.25','gl_total_credit'=>'141.25'])];
    $reverse=EmployeeCashControl::view($self,7,'2026-10-01','2026-10-19',1,50,$fake,$profile);
    ok($reverse['rows'][0]['journal_check']==='journal_amount_mismatch'
        &&$reverse['rows'][0]['journal_cash_upi_reconcile']===false
        &&$reverse['rows'][0]['journal_balanced']===true,
        'unexpected Cash credit is rejected even when overall GL remains balanced');
    $fake->rows=[row(16,2,'120.25','20.00','140.25','120.25','20.00',1,
        ['gl_sales_credit'=>'139.25'])];
    $salesShort=EmployeeCashControl::view($self,7,'2026-10-01','2026-10-19',1,50,$fake,$profile);
    ok($salesShort['rows'][0]['journal_check']==='journal_amount_mismatch'
        &&$salesShort['rows'][0]['journal_sales_credit_reconcile']===false,
        'understated SALES credit fails even if Cash/UPI and gross journal totals match');
    $fake->rows=[row(17,2,'120.25','20.00','140.25','120.25','20.00',1,
        ['gl_total_credit'=>'140.24'])];
    $unbalanced=EmployeeCashControl::view($self,7,'2026-10-01','2026-10-19',1,50,$fake,$profile);
    ok($unbalanced['rows'][0]['journal_check']==='journal_amount_mismatch'
        &&$unbalanced['rows'][0]['journal_balanced']===false,
        'one-paisa GL imbalance fails despite matching payment debit accounts');
    $fake->rows=[row(18,2,'120.25','20.00','140.25','120.25','20.00',1,
        ['gl_orphan_account_lines'=>1])];
    $orphan=EmployeeCashControl::view($self,7,'2026-10-01','2026-10-19',1,50,$fake,$profile);
    ok($orphan['rows'][0]['journal_check']==='journal_amount_mismatch'
        &&$orphan['rows'][0]['journal_orphan_account_lines']===1,
        'orphan/foreign-company GL account blocks clean reconciliation');
    // Legitimate posted Daily Order journals contain balanced COGS/inventory
    // legs as well as tender debit and SALES credit.
    $fake->rows=[row(19,2,'120.25','20.00','140.25','120.25','20.00',1,
        ['gl_cogs_debit'=>'75.00','gl_inventory_credit'=>'75.00',
         'gl_total_debit'=>'215.25','gl_total_credit'=>'215.25'])];
    $withCost=EmployeeCashControl::view($self,7,'2026-10-01','2026-10-19',1,50,$fake,$profile);
    ok($withCost['rows'][0]['journal_check']==='journal_amounts_match'
       &&$withCost['rows'][0]['journal_cost_of_goods_reconcile']===true
       &&$withCost['rows'][0]['journal_cogs_debit_paise']===7500,
       'balanced canonical COGS/INVENTORY are part of a valid sale journal');

    $fake->rows=[row(20,2,'120.25','20.00','140.25','120.25','20.00',1,
        ['gl_cogs_debit'=>'75.00','gl_inventory_credit'=>'74.00',
         'gl_total_debit'=>'215.25','gl_total_credit'=>'215.25'])];
    $badCost=EmployeeCashControl::view($self,7,'2026-10-01','2026-10-19',1,50,$fake,$profile);
    ok($badCost['rows'][0]['journal_check']==='journal_amount_mismatch'
       &&$badCost['rows'][0]['journal_cost_of_goods_reconcile']===false,
       'balanced but unequal COGS/INVENTORY is not a clean posting');

    $fake->rows=[row(21,2,'120.25','20.00','140.25','120.25','20.00',1,
        ['gl_unexpected_amount'=>'10.00',
         'gl_total_debit'=>'145.25','gl_total_credit'=>'145.25'])];
    $extra=EmployeeCashControl::view($self,7,'2026-10-01','2026-10-19',1,50,$fake,$profile);
    ok($extra['rows'][0]['journal_check']==='journal_amount_mismatch'
       &&$extra['rows'][0]['journal_unexpected_legs_paise']===1000,
       'offsetting unrelated Dr/Cr legs cannot forge a clean reconciliation');

    $fake->rows=[row(22,2,'120.25','20.00','140.25','120.25','20.00',1,
        ['gl_cogs_debit'=>'75.00','gl_inventory_credit'=>'75.00',
         'gl_unexpected_amount'=>'0.01','gl_total_debit'=>'215.26',
         'gl_total_credit'=>'215.26'])];
    $penny=EmployeeCashControl::view($self,7,'2026-10-01','2026-10-19',1,50,$fake,$profile);
    ok($penny['rows'][0]['journal_check']==='journal_amount_mismatch',
       'unclassified penny is a mismatch even with matching totals');
    $noFinance=new Actor(11,7,1,2,[2],[],'FSE');
    $fake->calls=[];
    deny(fn()=>EmployeeCashControl::view($noFinance,7,'2026-10-01','2026-10-19',1,50,$fake,$profile),'permission_denied');
    ok(count($fake->calls)===0,'no query if accounting permission denied');
    deny(fn()=>EmployeeCashControl::view(new Actor(9,4,1,2,[2],[Capabilities::ACCOUNTING_VIEW],'BM'),7,'2026-10-01','2026-10-19',1,50,$fake,$profile),'permission_denied');
    deny(fn()=>EmployeeCashControl::view(new Actor(9,4,1,4,[4],[Capabilities::ACCOUNTING_VIEW,Capabilities::EMP_VIEW],'BM'),7,'2026-10-01','2026-10-19',1,50,$fake,$profile),'branch_forbidden');
    HierarchyScope::$allow=false;
    deny(fn()=>EmployeeCashControl::view($m,7,'2026-10-01','2026-10-19',1,50,$fake,$profile),'employee_scope_forbidden');
    HierarchyScope::$allow=true;
    $cross=new ProfileFake();$cross->value['company_id']=100;
    deny(fn()=>EmployeeCashControl::view($self,7,'2026-10-01','2026-10-19',1,50,$fake,$cross),'employee_not_found');
    deny(fn()=>EmployeeCashControl::view($self,7,'2026-10-30','2026-10-01',1,50,$fake,$profile),'period_invalid');
    deny(fn()=>EmployeeCashControl::view($self,7,'2026-10-01','2026-10-19',0,50,$fake,$profile),'register_pagination_invalid');
    deny(fn()=>EmployeeCashControl::view($self,7,'2026-10-01','2026-10-19',1,101,$fake,$profile),'register_pagination_invalid');
    $fake->rows=[row(8,4)];
    deny(fn()=>EmployeeCashControl::view($m,7,'2026-10-01','2026-10-19',1,50,$fake,$profile),'cash_control_scope_invalid');
    $fake->rows=[row(8,2,'70.00','9.00','80.00')];
    deny(fn()=>EmployeeCashControl::view($self,7,'2026-10-01','2026-10-19',1,50,$fake,$profile),'cash_control_corrupt');
    $fake->rows=[row(8,2,'120.255','0.00','120.25')];
    deny(fn()=>EmployeeCashControl::view($self,7,'2026-10-01','2026-10-19',1,50,$fake,$profile),'cash_control_corrupt');
    $fake->rows=[row(8,2,'-2.00','0.00','120.25')];
    deny(fn()=>EmployeeCashControl::view($self,7,'2026-10-01','2026-10-19',1,50,$fake,$profile),'cash_control_corrupt');
    $fake->rows=[row(8,2,'99999999999999.99','0.00','99999999999999.99')];
    deny(fn()=>EmployeeCashControl::view($self,7,'2026-10-01','2026-10-19',1,50,$fake,$profile),'cash_control_corrupt');
    $fake->rows=[row(8,2,'120.25','0.00','120.25')];$fake->rows[0]['business_date']='2026-09-19';
    deny(fn()=>EmployeeCashControl::view($self,7,'2026-10-01','2026-10-19',1,50,$fake,$profile),'cash_control_corrupt');
    $reader=new EmployeeCashControlWpReader();
    $GLOBALS['fakeWpdb']=new class{
        public array $prepared=[];public ?array $result=[];
        public function prepare(string $sql,...$args):string{$this->prepared[]=[$sql,$args];return $sql;}
        public function get_results(string $sql,$format):?array{return $this->result;}
    };
    Db::$stub=$GLOBALS['fakeWpdb'];if(!defined('ARRAY_A'))define('ARRAY_A','ARRAY_A');
    $reader->posted(1,7,'2026-10-01','2026-10-19',[2,4],51,100);
    $sql=$GLOBALS['fakeWpdb']->prepared[0][0];$args=$GLOBALS['fakeWpdb']->prepared[0][1];
    ok(str_contains($sql,'wp_eh7_daily_cycles')&&str_contains($sql,'wp_eh7_evening_settlements'),'canonical posted sales registers');
    ok(str_contains($sql,"es.status='posted'")&&str_contains($sql,"c.status='completed'"),'posted only');
    ok(str_contains($sql,"je.source_type='daily_cycle'")&&str_contains($sql,"je.status='posted'"),'posted journal source only');
    ok(str_contains($sql,'COUNT(DISTINCT je.id)'),'duplicate journal count');
    ok(str_contains($sql,'LOWER(a.subtype)'),'cash/upi account type classification');
    ok(str_contains($sql,"a.code='SALES' AND a.type IN ('income','revenue')"),
       'posted SALES credit accepts canonical revenue and legacy income account types, not arbitrary assets');
    ok(str_contains($sql,"a.code='COGS' AND a.type='expense'")
       &&str_contains($sql,"a.code='INVENTORY' AND a.type='asset'"),
       'only legitimate COGS and INVENTORY ledger classifications recognized');
    ok(str_contains($sql,'gl_unexpected_amount')&&str_contains($sql,'THEN jl.debit+jl.credit'),
       'unknown accounts and wrong-side legs cannot disappear in balanced totals');
    ok(str_contains($sql,'SUM(jl.debit)')&&str_contains($sql,'SUM(jl.credit)')
        &&str_contains($sql,'gl_cash_credit')&&str_contains($sql,'gl_upi_credit'),
       'full posted GL and reverse payment legs are also reconciled');
    ok(str_contains($sql,'LEFT JOIN wp_eh7_accounts')
        &&str_contains($sql,'gl_orphan_account_lines'),
       'foreign or missing account reference cannot be silently excluded from GL totals');
    ok(str_contains($sql,'GROUP BY je.company_id,je.branch_id,je.source_id'),
       'GL source grouped by company branch and daily cycle');
    ok(str_contains($sql,'j.branch_id=c.branch_id'),
       'wrong-branch journal cannot reconcile an employee daily cycle');
    ok(str_contains($sql,'COUNT(DISTINCT je.id)'),
       'per-branch count still protects against duplicate posted GL');
    ok(!str_contains($sql,'CROSS JOIN') && !str_contains($sql,'INSERT INTO'),
       'finance profile report never posts a journal');
    ok(str_contains($sql,'c.branch_id IN (%d,%d)'),'branch-scoped canonical read');
    ok($args===[1,1,7,'2026-10-01','2026-10-19',2,4,51,100],'all SQL parameters bound');
    ok(!str_contains($sql,'DELETE ')&&!str_contains($sql,'UPDATE '),'read only report');
    echo 'PASS '.$pass.'/'.$pass." employee finance cash-control regressions\n";
}
