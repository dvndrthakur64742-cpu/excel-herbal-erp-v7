<?php
declare(strict_types=1);

require_once __DIR__.'/../src/Domain/DomainException.php';
require_once __DIR__.'/../src/Security/Actor.php';
require_once __DIR__.'/../src/Security/Capabilities.php';
require_once __DIR__.'/../src/Security/Guard.php';
require_once __DIR__.'/../src/Core/Input.php';
require_once __DIR__.'/../src/Reporting/BranchDailyControlReport.php';

use ExcelHerbal\ERP7\Reporting\{BranchDailyControlReport,BranchDailyControlReader};
use ExcelHerbal\ERP7\Security\{Actor,Capabilities};
use ExcelHerbal\ERP7\Domain\DomainException;

if(!function_exists('wp_timezone')){
    function wp_timezone():DateTimeZone{return new DateTimeZone('Asia/Kolkata');}
}
$n=0;
function pass(bool $ok,string $why):void{
    global $n;
    if(!$ok)throw new RuntimeException('FAIL '.$why);
    ++$n;
    echo "PASS {$why}\n";
}
function denied(callable $fn,string $reason):void{
    try{$fn();throw new RuntimeException('Expected to reject: '.$reason);}
    catch(DomainException $e){pass($e->codeKey===$reason,'denied '.$reason);}
}
$reader=new class implements BranchDailyControlReader {
    public array $calls=[];
    public array $cycleRows=[
        ['cycle_id'=>1,'employee_id'=>11,'employee_name'=>'Field One','branch_id'=>2,'cycle_status'=>'completed',
          'settlement_status'=>'posted','expected_amount'=>'300.00','cash_amount'=>'100.00','upi_amount'=>'200.00',
          'closing_sale_amount'=>'300.00','issued_quantity'=>'5.000','sold_quantity'=>'3.000','returned_quantity'=>'2.000',
          'pending_requests'=>1],
        ['cycle_id'=>2,'employee_id'=>12,'employee_name'=>'Field Two','branch_id'=>2,'cycle_status'=>'issued',
          'settlement_status'=>null,'expected_amount'=>null,'cash_amount'=>null,'upi_amount'=>null,
          'closing_sale_amount'=>'0','issued_quantity'=>'2.000','sold_quantity'=>'0','returned_quantity'=>'0','pending_requests'=>1],
    ];
    public array $stockRows=[
        ['branch_id'=>2,'employee_id'=>11,'employee_name'=>'Field One','qty_in'=>'5.000','qty_out'=>'5.000'],
        ['branch_id'=>2,'employee_id'=>0,'qty_in'=>'50.000','qty_out'=>'0'],
        ['branch_id'=>2,'employee_id'=>13,'employee_name'=>'Field Three','qty_in'=>'1.000','qty_out'=>'0.000'],
    ];
    public array $pointsRows=[
        ['branch_id'=>2,'employee_id'=>11,'employee_name'=>'Field One','points'=>'7.00'],
        ['branch_id'=>2,'employee_id'=>13,'employee_name'=>'Field Three','points'=>'2.00'],
    ];
    public array $counterRows=[
        ['branch_id'=>2,'status'=>'posted','gross_amount'=>'25.00','paid_amount'=>'20.00','outstanding_amount'=>'5.00'],
    ];
    public function cycles(int $co,int $br,string $date):array{
        $this->calls[]=['cycles',$co,$br,$date];return $this->cycleRows;
    }
    public function custody(int $co,int $br,string $start,string $end):array{
        $this->calls[]=['custody',$co,$br,$start,$end];return $this->stockRows;
    }
    public function performance(int $co,int $br,string $date):array{
        $this->calls[]=['performance',$co,$br,$date];return $this->pointsRows;
    }
    public function counterSales(int $co,int $br,string $start,string $end):array{
        $this->calls[]=['counter',$co,$br,$start,$end];return $this->counterRows;
    }
};
$actor=new Actor(20,15,1,2,[2],[Capabilities::REPORTS_VIEW],'BM');
$data=BranchDailyControlReport::view($actor,2,'2026-10-20',$reader);
$t=$data['totals'];
pass($data['read_only']===true&&$data['scope']==='single_authorized_branch_canonical_v7','manager report read-only branch scoped');
pass($t['posted_daily_order_sales']==='300.00'&&$t['daily_cash_split']==='100.00'
    &&$t['daily_upi_split']==='200.00','posted Daily Order split exact with separate money units');
pass($t['counter_sales_gross']==='25.00'&&$t['posted_counter_sales']===1,
    'counter sale appears once, separate from Daily Order total');
pass($t['issued_quantity']==='7.000'&&$t['sold_quantity']==='3.000'
    &&$t['returned_quantity']==='2.000','issued includes unposted issues; sold and returned posted only');
pass($t['custody_in_quantity']==='6.000'&&$t['custody_out_quantity']==='5.000',
    'warehouse movements excluded from employee custody totals');
pass($t['performance_points']==='9.00'&&$t['employees_with_activity']===3,
    'employee with points/stock but no Daily Order is reported');
pass($t['pending_requests']===2&&$t['pending_cycles']===1
    &&$t['employees_needing_attention']===3,'pending, unposted and missing-cycle exceptions are independent');
pass($data['coverage']['cashier_handover_verified']===false
    &&$data['coverage']['upi_bank_verified']===false
    &&$data['coverage']['physical_stock_count_verified']===false,
    'reported cash and stock never imply external verification');
pass($reader->calls[1]===[
    'custody',1,2,'2026-10-19 18:30:00','2026-10-20 18:30:00'],
    'business-date custody sourced from correct Asia Kolkata UTC bounds');
denied(fn()=>BranchDailyControlReport::view(new Actor(21,17,1,2,[2],[],'FSE'),2,'2026-10-20',$reader),'permission_denied');
denied(fn()=>BranchDailyControlReport::view(new Actor(22,17,1,3,[3],[Capabilities::REPORTS_VIEW],'BM'),2,'2026-10-20',$reader),'branch_forbidden');
denied(fn()=>BranchDailyControlReport::view($actor,2,'2026-02-30',$reader),'date_invalid');
$reader->cycleRows[0]['cash_amount']='100.01';
$split=BranchDailyControlReport::view($actor,2,'2026-10-20',$reader);
pass(in_array('posted_amount_split_mismatch',$split['employees'][0]['exceptions'],true),
    'posted Cash/UPI split mismatch is surfaced, never silently accepted');
$reader->cycleRows[0]['cash_amount']='100.00';
$reader->cycleRows[0]['sold_quantity']='2.000';
$mismatch=BranchDailyControlReport::view($actor,2,'2026-10-20',$reader);
pass(in_array('issued_sold_returned_mismatch',$mismatch['employees'][0]['exceptions'],true),
    'issued versus sold/return stock mismatch detected independently');
$reader->cycleRows[0]['sold_quantity']='3.000';
$reader->pointsRows[0]['points']='7.123';
denied(fn()=>BranchDailyControlReport::view($actor,2,'2026-10-20',$reader),'branch_report_source_invalid');
$reader->pointsRows[0]['points']='7.00';
$reader->stockRows[0]['branch_id']=999;
denied(fn()=>BranchDailyControlReport::view($actor,2,'2026-10-20',$reader),'branch_report_source_invalid');
$reader->stockRows[0]['branch_id']=2;
$reader->cycleRows[]=$reader->cycleRows[0];
denied(fn()=>BranchDailyControlReport::view($actor,2,'2026-10-20',$reader),'branch_report_source_invalid');
$source=file_get_contents(__DIR__.'/../src/Reporting/BranchDailyControlReport.php');
pass(str_contains($source,'GROUP BY r.daily_cycle_id')
  &&str_contains($source,'GROUP BY el.evening_settlement_id')
  &&str_contains($source,'GROUP BY sl.branch_id,sl.custodian_employee_id'),
  'canonical lines aggregated BEFORE joining, no multi-batch or duplicated sales');
pass(!str_contains($source,'salary_fund_snapshot')&&!str_contains($source,'purchase_cost_snapshot'),
  'manager daily read-only control does not expose product costs or salary amounts');
echo "BRANCH DAILY CONTROL PHP UNIT: {$n}/{$n} PASS\n";
