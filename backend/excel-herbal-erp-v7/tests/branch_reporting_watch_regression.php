<?php
declare(strict_types=1);
require_once __DIR__.'/../src/Domain/DomainException.php';
require_once __DIR__.'/../src/Core/Input.php';
require_once __DIR__.'/../src/Security/Actor.php';
require_once __DIR__.'/../src/Security/Capabilities.php';
require_once __DIR__.'/../src/Security/Guard.php';
require_once __DIR__.'/../src/Reporting/BranchReportingWatch.php';

use ExcelHerbal\ERP7\Reporting\{BranchReportingWatch,BranchReportingWatchReader};
use ExcelHerbal\ERP7\Security\{Actor,Capabilities};
use ExcelHerbal\ERP7\Domain\DomainException;

if(!function_exists('wp_timezone'))function wp_timezone():DateTimeZone{return new DateTimeZone('Asia/Kolkata');}
$n=0;
function check(bool $ok,string $why):void {
    global $n;if(!$ok)throw new RuntimeException('FAIL '.$why);
    $n++;echo "PASS {$why}\n";
}
function reject(callable $fn,string $key):void {
    try{$fn();throw new RuntimeException('Expected denial: '.$key);}
    catch(DomainException $e){check($e->codeKey===$key,'reject '.$key);}
}
$source=new class implements BranchReportingWatchReader {
    public array $branchNames=[2=>'North',4=>'South'];
    public array $calls=[];
    public array $staff=[
        2=>[
            ['employee_id'=>11,'employee_name'=>'Field A','branch_id'=>2,'cycle_id'=>401,'cycle_status'=>'completed','settlement_status'=>'posted'],
            ['employee_id'=>12,'employee_name'=>'Field B','branch_id'=>2,'cycle_id'=>null,'cycle_status'=>null,'settlement_status'=>null],
        ],
        4=>[
            ['employee_id'=>13,'employee_name'=>'Field C','branch_id'=>4,'cycle_id'=>402,'cycle_status'=>'issued','settlement_status'=>null],
        ],
    ];
    public array $dailyOverride=[];
    public function branches(int $company,array $ids):array {
        $this->calls[]=['branches',$company,$ids];
        return array_intersect_key($this->branchNames,array_flip($ids));
    }
    public function dailyRoster(int $company,int $branch,string $date):array {
        $this->calls[]=['roster',$company,$branch,$date];
        return $this->staff[$branch]??[];
    }
    public function dailyReport(Actor $actor,int $branch,string $date):array {
        $this->calls[]=['daily',$actor->companyId,$branch,$date];
        return $this->dailyOverride[$branch]??[
            'branch_id'=>$branch,'business_date'=>$date,'read_only'=>true,
            'scope'=>'single_authorized_branch_canonical_v7',
            'coverage'=>['cashier_handover_verified'=>false,'upi_bank_verified'=>false],
            'totals'=>['posted_daily_order_sales'=>$branch===2?'300.00':'0.00','pending_requests'=>1]
        ];
    }
};
$tz=new DateTimeZone('Asia/Kolkata');
$now=new DateTimeImmutable('2026-10-20 21:00:00',$tz);
$actor=new Actor(21,5,1,2,[4,2],[Capabilities::REPORTS_VIEW],'RM');
$report=BranchReportingWatch::view($actor,'2026-10-20',null,$source,$now);
check($report['read_only'] && $report['delivery_enabled']===false
    &&$report['automatic_notifications_sent']===0,'scheduled watch is read-only, no messages dispatched');
check($source->calls[0]===['branches',1,[2,4]],'active branches resolved from actor scope, not HTTP client');
check($report['summary']['branches']===2&&$report['summary']['eligible_field_staff']===3
    &&$report['summary']['posted_evening_closings']===1,'multi-branch FSE roster compares posted evening evidence');
check($report['summary']['missing_daily_cycles']===1
    &&$report['summary']['unposted_evening_closings']===1
    &&$report['summary']['past_due_unposted_or_missing']===2,
    'after 19:30 absent cycle and unposted closing are distinct overdue exceptions');
check($report['branches'][0]['branch_id']===2&&$report['branches'][1]['branch_id']===4,
    'regional dashboard ranks branches by overdue count with deterministic tie');
check(count($report['reminder_candidates'])===2
    &&$report['reminder_candidates'][0]['delivery_state']==='not_dispatched'
    &&strlen($report['reminder_candidates'][0]['deduplication_key'])===64,
    'idempotent reminder candidates are NOT notifications');
$again=BranchReportingWatch::view($actor,'2026-10-20',null,$source,$now);
check($again['reminder_candidates']===$report['reminder_candidates'],
    'candidate idempotency keys are stable between refreshes');
check($report['schedule'][0]['id']==='evening_daily_closing'
    &&$report['schedule'][0]['submission_state']==='overdue_evidence'
    &&$report['schedule'][0]['time']==='19:30',
    'evening report deadline anchored at 7:30pm in business timezone');
check($report['schedule'][1]['id']==='tuesday_product_order'
    &&$report['schedule'][1]['submission_state']==='verification_unavailable'
    &&$report['schedule'][1]['notification_sent']===false,
    'Tuesday product order is due but missing/submitted cannot be invented');
check($report['coverage']['weekly_monthly_product_salary_submission_evidence_integrated']===false
    &&$report['coverage']['cashier_handover_verified']===false,
    'report evidence and cash verification remain explicitly unintegrated');
$early=BranchReportingWatch::view($actor,'2026-10-20',null,$source,new DateTimeImmutable('2026-10-20 19:15:00',$tz));
check($early['summary']['past_due_unposted_or_missing']===0
    &&count($early['reminder_candidates'])===0
    &&$early['schedule'][0]['submission_state']==='pending_before_cutoff',
    'no overdue candidates before daily 19:30 boundary');
$monday=BranchReportingWatch::view($actor,'2026-10-19',2,$source,$now);
check(array_column($monday['schedule'],'id')===
    ['evening_daily_closing','monday_weekly_report','monday_product_order'],
    'Monday creates weekly reporting and Monday product order slots');
check($monday['schedule'][1]['due_state']==='past_due'
    &&$monday['schedule'][1]['submission_state']==='verification_unavailable',
    'past weekly due slot remains unverified rather than falsely declared missing');
$first=BranchReportingWatch::view($actor,'2026-10-01',2,$source,new DateTimeImmutable('2026-10-01 11:00:00',$tz));
check(in_array('monthly_first_report',array_column($first['schedule'],'id'),true)
    &&end($first['schedule'])['time']==='10:30'
    &&end($first['schedule'])['due_state']==='past_due',
    'first-of-month report deadline at 10:30 not invented time');
$tenth=BranchReportingWatch::view($actor,'2026-10-10',2,$source,new DateTimeImmutable('2026-10-11 08:00:00',$tz));
$last=end($tenth['schedule']);
check($last['id']==='salary_receipt_deadline'&&$last['time']===null
    &&$last['submission_state']==='verification_unavailable',
    'salary receipt due by day 10 with no imaginary clock or submission');
$one=BranchReportingWatch::view($actor,'2026-10-20',2,$source,$now);
check($one['summary']['branches']===1&&$one['summary']['missing_daily_cycles']===1
    &&$one['reminder_candidates'][0]['branch_id']===2,
    'single authorized branch filter cannot see foreign branch exceptions');
$none=new Actor(22,8,1,2,[2],[],'FSE');
reject(fn()=>BranchReportingWatch::view($none,'2026-10-20',null,$source,$now),'permission_denied');
reject(fn()=>BranchReportingWatch::view($actor,'2026-10-20',3,$source,$now),'branch_forbidden');
reject(fn()=>BranchReportingWatch::view($actor,'2026-08-01',2,$source,$now),'watch_date_out_of_range');
reject(fn()=>BranchReportingWatch::view($actor,'2026-02-30',2,$source,$now),'date_invalid');
$source->branchNames=[2=>'North'];
reject(fn()=>BranchReportingWatch::view($actor,'2026-10-20',null,$source,$now),'watch_branch_inactive');
$source->branchNames=[2=>'North',4=>'South'];
$source->staff[4][0]['branch_id']=2;
reject(fn()=>BranchReportingWatch::view($actor,'2026-10-20',null,$source,$now),'watch_source_invalid');
$source->staff[4][0]['branch_id']=4;
$source->staff[4][]=$source->staff[4][0];
reject(fn()=>BranchReportingWatch::view($actor,'2026-10-20',null,$source,$now),'watch_source_invalid');
array_pop($source->staff[4]);
$source->dailyOverride[2]=['read_only'=>false,'branch_id'=>2,'business_date'=>'2026-10-20'];
reject(fn()=>BranchReportingWatch::view($actor,'2026-10-20',null,$source,$now),'watch_source_invalid');
$code=file_get_contents(__DIR__.'/../src/Reporting/BranchReportingWatch.php');
check(str_contains($code,"l.status='approved'")&&str_contains($code,'h.active=1')
    &&str_contains($code,"e.designation_code='FSE'"),
    'SQL roster excludes approved leave and active holiday; field staff FSE only');
check(str_contains($code,'s.daily_cycle_id=c.id')&&str_contains($code,"e.company_id=%d"),
    'canonical posting link and strict company/branch ID bindings');
echo "BRANCH REPORTING WATCH PHP: {$n}/{$n} PASS\n";
