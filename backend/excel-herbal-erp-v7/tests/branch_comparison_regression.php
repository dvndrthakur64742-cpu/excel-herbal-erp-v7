<?php
declare(strict_types=1);

require_once __DIR__.'/../src/Domain/DomainException.php';
require_once __DIR__.'/../src/Security/Actor.php';
require_once __DIR__.'/../src/Security/Capabilities.php';
require_once __DIR__.'/../src/Security/Guard.php';
require_once __DIR__.'/../src/Core/Input.php';
require_once __DIR__.'/../src/Reporting/BranchComparisonReport.php';

use ExcelHerbal\ERP7\Reporting\BranchComparisonReport;
use ExcelHerbal\ERP7\Security\{Actor,Capabilities};
use ExcelHerbal\ERP7\Domain\DomainException;

$checks=0;
function ok(bool $good,string $description):void {
    global $checks;
    if(!$good)throw new RuntimeException('FAIL '.$description);
    ++$checks;echo "PASS {$description}\n";
}
function denied(callable $run,string $code):void{
    try{$run();throw new RuntimeException('Expected rejection '.$code);}
    catch(DomainException $e){ok($e->codeKey===$code,'reject '.$code);}
}
$totals=static function(int $sale,string $points,int $pending):array {
    return [
        'posted_daily_order_sales'=>$sale.'.00',
        'daily_cash_allocations'=>($sale/2).'.00',
        'daily_upi_allocations'=>($sale/2).'.00',
        'counter_sales_gross'=>'20.00',
        'counter_sales_paid'=>'10.00','counter_sales_outstanding'=>'10.00',
        'issued_quantity'=>'5.000','sold_quantity'=>'3.000','returned_quantity'=>'2.000',
        'custody_in_quantity'=>'5.000','custody_out_quantity'=>'5.000',
        'performance_points'=>$points,
        'posted_daily_orders'=>1,'pending_daily_orders'=>$pending,
        'pending_stock_requests'=>$pending,'sale_amount_mismatches'=>0,
        'stock_quantity_mismatches'=>0,'posted_counter_sales'=>1,
        'employees_with_activity'=>1,'employees_needing_attention'=>$pending>0?1:0,
    ];
};
$source=function(Actor $actor,int $branch,string $mode,string $date)use($totals):array {
    $employeeId=$branch*100+1;
    $name=$branch===2?'=HYPERLINK("bad","open"), "CSV"':'Ravi Kumar';
    $money=$branch===2?200:100;
    $points=$branch===2?'-1.50':'3.00';
    $period=$mode==='week'
        ?['from'=>'2026-10-19','to'=>'2026-10-25']
        :['from'=>'2026-10-01','to'=>'2026-10-31'];
    $previous=$mode==='week'
        ?['from'=>'2026-10-12','to'=>'2026-10-18']
        :['from'=>'2026-09-01','to'=>'2026-09-30'];
    return [
        'company_id'=>$actor->companyId,'branch_id'=>$branch,'mode'=>$mode,
        'scope'=>'single_authorized_branch_canonical_v7','read_only'=>true,
        'coverage'=>[
            'cashier_handover_verified'=>false,'upi_bank_verified'=>false,
            'counter_sales_separate_from_daily_orders'=>true],
        'period'=>$period,'totals'=>$totals($money,$points,$branch===3?1:0),
        'previous_period'=>['period'=>$previous,'totals'=>$totals(100,'0.00',0)],
        'employees'=>[
            [
                'employee_id'=>$employeeId,'employee_name'=>$name,
                'posted_daily_order_sales'=>$money.'.00',
                'daily_cash_allocations'=>($money/2).'.00',
                'daily_upi_allocations'=>($money/2).'.00',
                'issued_quantity'=>'5.000','sold_quantity'=>'3.000',
                'returned_quantity'=>'2.000','custody_in_quantity'=>'5.000',
                'custody_out_quantity'=>'5.000','performance_points'=>$points,
                'posted_days'=>1,'pending_days'=>$branch===3?1:0,
                'pending_requests'=>$branch===3?1:0,
                'sale_amount_mismatches'=>0,'stock_quantity_mismatches'=>0,
                // Attempt to inject finance-only projection; MUST be removed.
                'tagged_cash_in_transit'=>[
                    'opening_debit_minus_credit'=>'999999.00',
                    'closing_debit_minus_credit'=>'999999.00',
                ],
            ],
        ],
    ];
};
$actor=new Actor(91,9901,1,2,[3,2],[Capabilities::REPORTS_VIEW],'RM');
$report=BranchComparisonReport::view($actor,'week','2026-10-20','','',$source);
ok($report['branch_ids']===[2,3]&&count($report['branches'])===2,
   'authorized branches sorted/deduplicated, no client expansion');
ok($report['scope']==='only_effective_authorized_branches'&&$report['read_only']===true,
    'authenticated read-only multi-branch report');
ok($report['total']['posted_daily_order_sales']==='300.00'
   &&$report['previous_total']['posted_daily_order_sales']==='200.00'
   &&$report['sales_change_inr']==='100.00','week comparison all authorized sources exact in paise');
ok($report['total']['performance_points']==='1.50'
   &&$report['total']['issued_quantity']==='10.000'
   &&$report['total']['counter_sales_gross']==='40.00',
   'signed points, PCS and separate counter sale totals not mixed as INR');
ok($report['total']['pending_daily_orders']===1
   &&$report['total']['pending_stock_requests']===1
   &&$report['top_posted_sales_branch_id']===2,
   'pending exception counts plus deterministic top-posted-sales branch');
ok($report['financial_visibility']==='no_gl_data_exported'
   &&!array_key_exists('tagged_cash_in_transit',$report['branches'][0]['employees'][0]),
   'finance/cash liability fields stripped from compare even when supplied upstream');
ok($report['coverage']['cashier_handover_verified']===false
   &&$report['coverage']['upi_bank_verified']===false,
   'comparison never assumes external deposit or UPI proof');
$onlyTwo=BranchComparisonReport::view($actor,'week','2026-10-20','2','',$source);
ok($onlyTwo['branch_ids']===[2]&&$onlyTwo['total']['posted_daily_order_sales']==='200.00',
   'specific authorized branch selection excludes other branches from totals');
$monthly=BranchComparisonReport::view($actor,'month','2026-10-20','','',$source);
ok($monthly['period']===['from'=>'2026-10-01','to'=>'2026-10-31']
   &&$monthly['previous_period']===['from'=>'2026-09-01','to'=>'2026-09-30'],
   'full calendar month and prior month retained across source branches');
$csv=BranchComparisonReport::view($actor,'week','2026-10-20','','csv',$source);
ok($csv['mime_type']==='text/csv'&&$csv['encoding']==='utf-8-sig'
   &&str_starts_with($csv['csv'],"\xEF\xBB\xBF"),
   'CSV is UTF8 BOM Excel-ready and REST JSON envelope retains branch scope');
ok($csv['branch_ids']===[2,3]
   &&str_contains($csv['csv'],'"authorized_total","ALL"')
   &&str_contains($csv['csv'],'"employee","2","201"'),
   'export contains authorized branches, per-employee rows and one total');
ok(str_contains($csv['csv'],'"\'=HYPERLINK(""bad"",""open""), ""CSV"""')
   &&!str_contains($csv['csv'],'"=HYPERLINK'),
   'Excel formula-injection prefix and RFC4180 escaping disable malicious employee name');
ok(!str_contains($csv['csv'],'999999.00')
   &&!str_contains($csv['csv'],'tagged_cash_in_transit'),
   'finance-only tagged Cash never leaks into manager CSV');
denied(fn()=>BranchComparisonReport::view(
    new Actor(2,3,1,2,[2,3],[],'FSE'),'week','2026-10-20','','',$source),'permission_denied');
denied(fn()=>BranchComparisonReport::view($actor,'week','2026-10-20','2,99','',$source),'branch_forbidden');
denied(fn()=>BranchComparisonReport::view($actor,'week','2026-10-20','2,2','',$source),'branch_compare_branches_invalid');
denied(fn()=>BranchComparisonReport::view($actor,'week','2026-10-20','0','',$source),'branch_compare_branches_invalid');
denied(fn()=>BranchComparisonReport::view($actor,'week','2026-10-20','2,3;DROP','',$source),'branch_compare_branches_invalid');
denied(fn()=>BranchComparisonReport::view($actor,'year','2026-10-20','','',$source),'branch_period_invalid');
denied(fn()=>BranchComparisonReport::view($actor,'week','2026-02-30','','',$source),'date_invalid');
denied(fn()=>BranchComparisonReport::view($actor,'week','2026-10-20','','xlsx',$source),'branch_compare_export_invalid');
$over12=new Actor(2,4,1,1,range(1,13),[Capabilities::REPORTS_VIEW],'RM');
denied(fn()=>BranchComparisonReport::view($over12,'month','2026-10-20','','',$source),'branch_compare_too_many_branches');
$maliciousSource=static fn(Actor $a,int $b,string $m,string $d):array=>
    array_replace($source($a,$b,$m,$d),['branch_id'=>$b+100]);
denied(fn()=>BranchComparisonReport::view($actor,'week','2026-10-20','','',$maliciousSource),
    'branch_compare_source_invalid');
$leaking=static fn(Actor $a,int $b,string $m,string $d):array=>
    array_replace($source($a,$b,$m,$d),[
        'coverage'=>[
            'cashier_handover_verified'=>true,'upi_bank_verified'=>false,
            'counter_sales_separate_from_daily_orders'=>true]]);
denied(fn()=>BranchComparisonReport::view($actor,'week','2026-10-20','','',$leaking),
    'branch_compare_source_invalid');
$badDecimal=static function(Actor $a,int $b,string $m,string $d)use($source):array {
    $r=$source($a,$b,$m,$d);$r['totals']['posted_daily_order_sales']='1.001';return $r;
};
denied(fn()=>BranchComparisonReport::view($actor,'week','2026-10-20','','',$badDecimal),
    'branch_compare_source_invalid');
$badPeriod=static function(Actor $a,int $b,string $m,string $d)use($source):array {
    $r=$source($a,$b,$m,$d);
    if($b===3)$r['period']=['from'=>'2026-10-01','to'=>'2026-10-19'];
    return $r;
};
denied(fn()=>BranchComparisonReport::view($actor,'week','2026-10-20','','',$badPeriod),
    'branch_compare_source_invalid');
$wrongCompany=static function(Actor $a,int $b,string $m,string $d)use($source):array {
    $r=$source($a,$b,$m,$d);$r['company_id']=999;return $r;
};
denied(fn()=>BranchComparisonReport::view($actor,'week','2026-10-20','','',$wrongCompany),
    'branch_compare_source_invalid');
echo "BRANCH COMPARISON & CSV UNIT: {$checks}/{$checks} PASS\n";
