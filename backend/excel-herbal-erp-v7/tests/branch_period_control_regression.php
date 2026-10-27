<?php
declare(strict_types=1);

require_once __DIR__.'/../src/Domain/DomainException.php';
require_once __DIR__.'/../src/Security/Actor.php';
require_once __DIR__.'/../src/Security/Capabilities.php';
require_once __DIR__.'/../src/Security/Guard.php';
require_once __DIR__.'/../src/Core/Input.php';
require_once __DIR__.'/../src/Reporting/BranchPeriodControlReport.php';

use ExcelHerbal\ERP7\Reporting\{BranchPeriodControlReport,BranchPeriodControlReader};
use ExcelHerbal\ERP7\Security\{Actor,Capabilities};
use ExcelHerbal\ERP7\Domain\DomainException;

if (!function_exists('wp_timezone')) {
    function wp_timezone():DateTimeZone{return new DateTimeZone('Asia/Kolkata');}
}
$checks=0;
function ok(bool $pass,string $why):void {
    global $checks;
    if(!$pass)throw new RuntimeException('FAIL '.$why);
    ++$checks;echo "PASS {$why}\n";
}
function rejects(callable $fn,string $key):void {
    try{$fn();throw new RuntimeException('Expected exception '.$key);}
    catch(DomainException $e){ok($e->codeKey===$key,'fail-closed '.$key);}
}
$reader=new class implements BranchPeriodControlReader {
    public array $calls=[];
    public array $current=[
        ['cycle_id'=>100,'employee_id'=>7,'employee_name'=>'Field Seven','branch_id'=>2,
            'business_date'=>'2026-10-19','cycle_status'=>'completed','settlement_status'=>'posted',
            'expected_amount'=>'300.00','cash_amount'=>'100.00','upi_amount'=>'200.00',
            'closing_sale_amount'=>'300.00','issued_quantity'=>'5.000',
            'sold_quantity'=>'3.000','returned_quantity'=>'2.000','pending_requests'=>0],
        ['cycle_id'=>101,'employee_id'=>7,'employee_name'=>'Field Seven','branch_id'=>2,
            'business_date'=>'2026-10-20','cycle_status'=>'issued','settlement_status'=>null,
            'expected_amount'=>null,'cash_amount'=>null,'upi_amount'=>null,
            'closing_sale_amount'=>'0.00','issued_quantity'=>'2.000',
            'sold_quantity'=>'0','returned_quantity'=>'0','pending_requests'=>2],
        ['cycle_id'=>102,'employee_id'=>8,'employee_name'=>'Field Eight','branch_id'=>2,
            'business_date'=>'2026-10-20','cycle_status'=>'completed','settlement_status'=>'posted',
            'expected_amount'=>'50.00','cash_amount'=>'50.00','upi_amount'=>'0.00',
            'closing_sale_amount'=>'50.00','issued_quantity'=>'1.000',
            'sold_quantity'=>'1.000','returned_quantity'=>'0.000','pending_requests'=>0],
    ];
    public array $prior=[
        ['cycle_id'=>90,'employee_id'=>7,'employee_name'=>'Field Seven','branch_id'=>2,
            'business_date'=>'2026-10-12','cycle_status'=>'completed','settlement_status'=>'posted',
            'expected_amount'=>'200.00','cash_amount'=>'200.00','upi_amount'=>'0.00',
            'closing_sale_amount'=>'200.00','issued_quantity'=>'2.000',
            'sold_quantity'=>'2.000','returned_quantity'=>'0.000','pending_requests'=>0],
    ];
    public array $custody=[
        ['employee_id'=>7,'employee_name'=>'Field Seven','branch_id'=>2,'qty_in'=>'7.000','qty_out'=>'5.000'],
        ['employee_id'=>8,'employee_name'=>'Field Eight','branch_id'=>2,'qty_in'=>'1.000','qty_out'=>'1.000'],
    ];
    public array $points=[
        ['employee_id'=>7,'employee_name'=>'Field Seven','branch_id'=>2,'points'=>'6.50'],
        ['employee_id'=>8,'employee_name'=>'Field Eight','branch_id'=>2,'points'=>'-0.50'],
    ];
    public array $counter=[
        ['branch_id'=>2,'count_sales'=>1,'gross_amount'=>'75.00','paid_amount'=>'50.00','outstanding_amount'=>'25.00'],
    ];
    public array $finance=[
        ['branch_id'=>2,'employee_id'=>7,'employee_name'=>'Field Seven',
            'opening_debit_minus_credit'=>'80.00','period_debit'=>'100.00','period_credit'=>'60.00'],
    ];
    public function cycles(int $co,int $branch,string $from,string $to):array {
        $this->calls[]=['cycles',$co,$branch,$from,$to];
        return $from==='2026-10-19'?$this->current:($from==='2026-10-12'?$this->prior:[]);
    }
    public function custody(int $co,int $branch,string $start,string $end):array {
        $this->calls[]=['custody',$co,$branch,$start,$end];
        return $start==='2026-10-18 18:30:00'?$this->custody:[];
    }
    public function performance(int $co,int $branch,string $from,string $to):array {
        $this->calls[]=['points',$co,$branch,$from,$to];return $from==='2026-10-19'?$this->points:[];
    }
    public function counter(int $co,int $branch,string $start,string $end):array {
        $this->calls[]=['counter',$co,$branch,$start,$end];return $start==='2026-10-18 18:30:00'?$this->counter:[];
    }
    public function employeeCashTransit(int $co,int $branch,string $start,string $end):array {
        $this->calls[]=['finance',$co,$branch,$start,$end];return $start==='2026-10-19 00:00:00'?$this->finance:[];
    }
};
$bm=new Actor(900,91,1,2,[2],[Capabilities::REPORTS_VIEW],'BM');
$report=BranchPeriodControlReport::view($bm,2,'week','2026-10-20',$reader);
ok($report['read_only']===true&&$report['financial_visibility']==='hidden','weekly report read-only; manager without finance cannot see GL');
ok($report['period']===['from'=>'2026-10-19','to'=>'2026-10-25'],'ISO Monday-Sunday bounded week');
ok($report['previous_period']['period']===['from'=>'2026-10-12','to'=>'2026-10-18'],'previous full calendar week comparator');
ok($report['totals']['posted_daily_order_sales']==='350.00'
    &&$report['previous_period']['totals']['posted_daily_order_sales']==='200.00'
    &&$report['posted_daily_order_sales_delta']==='150.00','posted sales change is exactly INR 150');
ok($report['totals']['daily_cash_allocations']==='150.00'
    &&$report['totals']['daily_upi_allocations']==='200.00','Cash/UPI allocation sums count posted cycles only');
ok($report['totals']['issued_quantity']==='8.000'
    &&$report['totals']['sold_quantity']==='4.000'
    &&$report['totals']['returned_quantity']==='2.000','unposted issue included; unposted sale excluded');
ok($report['totals']['performance_points']==='6.00','negative performance point correction preserved without treating as INR');
ok($report['totals']['pending_daily_orders']===1
    &&$report['totals']['pending_stock_requests']===2
    &&$report['totals']['employees_needing_attention']===1,'pending closing counted separately from posted sales');
ok($report['totals']['counter_sales_gross']==='75.00'
    &&$report['totals']['counter_sales_outstanding']==='25.00','posted counter sales remain separate, with outstanding');
ok(count($report['employees'])===2&&$report['employees'][0]['employee_id']===7
    &&!isset($report['employees'][0]['tagged_cash_in_transit']),'no financial employee liability leaked to REPORTS_VIEW role');
ok($report['coverage']['cashier_handover_verified']===false
    &&$report['coverage']['upi_bank_verified']===false
    &&$report['coverage']['b2b_unmigrated_preview_excluded']===true,
    'report does not invent cashier, bank verification or optional B2B production data');
ok(count(array_filter($reader->calls,fn($call)=>$call[0]==='finance'))===0,'finance SQL not even executed for unauthorized actor');
ok($reader->calls[1]===['custody',1,2,'2026-10-18 18:30:00','2026-10-25 18:30:00'],
    'India business week translated to exact UTC stock range');
$accountant=new Actor(901,92,1,2,[2],[Capabilities::REPORTS_VIEW,Capabilities::ACCOUNTING_VIEW],'BM');
$financial=BranchPeriodControlReport::view($accountant,2,'week','2026-10-20',$reader);
ok($financial['financial_visibility']==='accounting_role_only'
    &&$financial['employees'][0]['tagged_cash_in_transit']['closing_debit_minus_credit']==='120.00',
    'finance-only tagged GL opening 80 + Dr 100 - Cr 60 = INR 120');
ok($financial['employees'][0]['tagged_cash_in_transit']['cashier_verified']===false,
    'tagged GL liability not cashier handover verification');
$month=BranchPeriodControlReport::view($bm,2,'month','2026-10-20',$reader);
ok($month['period']===['from'=>'2026-10-01','to'=>'2026-10-31']
    &&$month['previous_period']['period']===['from'=>'2026-09-01','to'=>'2026-09-30'],
    'calendar month and prior actual-month lengths; no fixed 30-day guess');
$jan=BranchPeriodControlReport::view($bm,2,'month','2026-01-20',$reader);
ok($jan['period']===['from'=>'2026-01-01','to'=>'2026-01-31']
   &&$jan['previous_period']['period']===['from'=>'2025-12-01','to'=>'2025-12-31'],
   'year boundary previous month correct');
rejects(fn()=>BranchPeriodControlReport::view($bm,2,'quarter','2026-10-20',$reader),'branch_period_invalid');
rejects(fn()=>BranchPeriodControlReport::view($bm,2,'month','2026-02-30',$reader),'date_invalid');
rejects(fn()=>BranchPeriodControlReport::view(new Actor(19,6,1,3,[3],[Capabilities::REPORTS_VIEW],'BM'),2,'week','2026-10-20',$reader),'branch_forbidden');
rejects(fn()=>BranchPeriodControlReport::view(new Actor(19,6,1,2,[2],[],'FSE'),2,'week','2026-10-20',$reader),'permission_denied');
$reader->current[0]['cash_amount']='100.01';
$bad=BranchPeriodControlReport::view($bm,2,'week','2026-10-20',$reader);
ok($bad['totals']['sale_amount_mismatches']===1&&$bad['employees'][0]['needs_attention'],
    'incorrect posted cash split raises visible exception');
$reader->current[0]['cash_amount']='100.00';
$reader->current[0]['sold_quantity']='2.000';
$bad=BranchPeriodControlReport::view($bm,2,'week','2026-10-20',$reader);
ok($bad['totals']['stock_quantity_mismatches']===1,'issued quantity mismatch raises independent exception');
$reader->current[0]['sold_quantity']='3.000';
$reader->points[0]['points']='6.345';
rejects(fn()=>BranchPeriodControlReport::view($bm,2,'week','2026-10-20',$reader),'branch_period_source_invalid');
$reader->points[0]['points']='6.50';
$reader->current[0]['branch_id']=4;
rejects(fn()=>BranchPeriodControlReport::view($bm,2,'week','2026-10-20',$reader),'branch_period_source_invalid');
$reader->current[0]['branch_id']=2;
$reader->current[]=$reader->current[0];
rejects(fn()=>BranchPeriodControlReport::view($bm,2,'week','2026-10-20',$reader),'branch_period_source_invalid');
$src=file_get_contents(__DIR__.'/../src/Reporting/BranchPeriodControlReport.php');
ok(str_contains($src,'GROUP BY r.daily_cycle_id')
   &&str_contains($src,'GROUP BY evening_settlement_id')
   &&str_contains($src,'GROUP BY sl.branch_id,sl.custodian_employee_id')
   &&str_contains($src,'GROUP BY p.branch_id,p.employee_id'),
   'cycle, lines, custody, performance aggregated independently to avoid duplicate joins');
ok(!str_contains($src,'purchase_cost_snapshot')&&!str_contains($src,'salary_fund_snapshot'),
   'branch period does not leak employee cost/Salary Fund commercially');
echo "BRANCH PERIOD WEEKLY MONTHLY PHP UNIT: {$checks}/{$checks} PASS\n";
