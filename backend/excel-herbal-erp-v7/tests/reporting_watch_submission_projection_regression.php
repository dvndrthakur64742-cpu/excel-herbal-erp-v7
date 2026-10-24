<?php
declare(strict_types=1);
require_once __DIR__.'/../src/Domain/DomainException.php';
require_once __DIR__.'/../src/Core/Input.php';
require_once __DIR__.'/../src/Security/Actor.php';
require_once __DIR__.'/../src/Security/Capabilities.php';
require_once __DIR__.'/../src/Security/Guard.php';
require_once __DIR__.'/../src/Reporting/BranchReportingWatch.php';
require_once __DIR__.'/../src/Reporting/ReportingWatchSubmissionProjection.php';
use ExcelHerbal\ERP7\Reporting\{
    BranchReportingWatchReader,ReportingWatchSubmissionReader,ReportingWatchSubmissionProjection
};
use ExcelHerbal\ERP7\Security\{Actor,Capabilities};
use ExcelHerbal\ERP7\Domain\DomainException;
if(!function_exists('wp_timezone')){
    function wp_timezone():DateTimeZone{return new DateTimeZone('Asia/Kolkata');}
}
$n=0;
function ok(bool $test,string $why):void{
    global $n;
    if(!$test)throw new RuntimeException('FAIL '.$why);
    $n++;echo "PASS {$why}\n";
}
function denies(callable $fn,string $code):void{
    try{$fn();throw new RuntimeException('Expected '.$code);}
    catch(DomainException $e){ok($e->codeKey===$code,'fail closed '.$code);}
}
$watch=new class implements BranchReportingWatchReader{
    public function branches(int $company,array $ids):array {
        $all=[2=>'North',4=>'South'];return array_intersect_key($all,array_flip($ids));
    }
    public function dailyRoster(int $company,int $branch,string $date):array {
        return [['employee_id'=>$branch+100,'employee_name'=>'Employee',
            'branch_id'=>$branch,'cycle_id'=>null,'cycle_status'=>null,'settlement_status'=>null]];
    }
    public function dailyReport(Actor $a,int $branch,string $date):array{
        return ['read_only'=>true,'branch_id'=>$branch,'business_date'=>$date,
            'scope'=>'single_authorized_branch_canonical_v7',
            'coverage'=>['cashier_handover_verified'=>false,'upi_bank_verified'=>false],
            'totals'=>['posted_daily_order_sales'=>'0.00','pending_requests'=>0]];
    }
};
$source=new class implements ReportingWatchSubmissionReader {
    public array $records=[];
    public array $calls=[];
    public function rows(int $co,array $branches,string $date):array{
        $this->calls[]=[$co,$branches,$date];
        return $this->records;
    }
};
$actor=new Actor(10,110,1,2,[4,2],[Capabilities::REPORTS_VIEW],'RM');
$clock=new DateTimeImmutable('2026-10-20 21:00:00',wp_timezone());
$source->records=[
 ['id'=>301,'company_id'=>1,'branch_id'=>2,'report_type'=>'product_order_tue',
  'period_date'=>'2026-10-20','status'=>'submitted','revision'=>1,'submitted_by'=>22,'reviewed_by'=>null],
 ['id'=>302,'company_id'=>1,'branch_id'=>4,'report_type'=>'product_order_tue',
  'period_date'=>'2026-10-20','status'=>'rejected','revision'=>2,'submitted_by'=>44,'reviewed_by'=>55],
];
$r=ReportingWatchSubmissionProjection::view($actor,'2026-10-20',null,$watch,$source,$clock);
ok($r['read_only']&&$r['submission_registry_read_only']===true
    &&$r['coverage']['weekly_monthly_product_salary_submission_evidence_integrated']===true,
    'watch now explicitly grounded in registered manager attestations');
ok($r['summary']['eligible_field_staff']===2&&$r['summary']['missing_daily_cycles']===2,
    'existing canonical daily closing evidence retained unchanged');
ok($source->calls[0]=== [1,[2,4],'2026-10-20'],
    'one submission query covers effective actor company and authorized branches');
ok($r['submission_evidence_summary']['submitted']===1
    &&$r['submission_evidence_summary']['rejected']===1,
    'correct branch-level current revision evidence counted');
ok($r['schedule'][1]['submission_state']==='mixed_branch_submission_states'
    &&$r['schedule'][1]['evidence']==='canonical_v7_manager_attestation_only',
    'mixed report approvals cannot be reported as entirely submitted');
ok($r['schedule'][1]['due_state']==='deadline_unspecified'
    &&$r['schedule'][1]['time']===null,
    'Tuesday order has no guessed clock cutoff or overdue claim');
ok($r['branches'][0]['reporting_submissions'][0]['submission_state']==='submitted'
    &&$r['branches'][1]['reporting_submissions'][0]['submission_state']==='rejected',
    'per-branch status distinguishes awaiting review vs rejection');
ok($r['delivery_enabled']===false&&$r['reminder_outbox_dispatch_enabled']===false
    &&$r['automatic_notifications_sent']===0,
    'neither overlay nor original watch sends notification');
ok($r['coverage']['cashier_handover_verified']===false&&$r['coverage']['upi_bank_verified']===false,
    'report approved state never implies Cash/UPI proof');
$source->records=[[
 'id'=>303,'company_id'=>1,'branch_id'=>2,'report_type'=>'weekly_report',
 'period_date'=>'2026-10-19','status'=>'approved','revision'=>2,
 'submitted_by'=>22,'reviewed_by'=>33
]];
$monday=ReportingWatchSubmissionProjection::view($actor,'2026-10-19',null,$watch,$source,$clock);
ok($monday['submission_evidence_summary']['approved']===1
    &&$monday['submission_evidence_summary']['not_submitted']===3,
    'Monday two report types times two branches, one approval and three genuinely unattested');
ok($monday['schedule'][1]['submission_state']==='mixed_branch_submission_states'
    &&$monday['schedule'][2]['submission_state']==='not_submitted_all_branches',
    'weekly approval and product-order gap remain independent types');
ok($monday['schedule'][1]['due_state']==='date_passed_deadline_unspecified',
    'past date without signed SLA does not invent clock-time overdue');
$source->records=[];
$first=ReportingWatchSubmissionProjection::view($actor,'2026-10-01',null,$watch,$source,
    new DateTimeImmutable('2026-10-01 11:00:00',wp_timezone()));
$monthly=array_values(array_filter($first['schedule'],fn($s)=>$s['id']==='monthly_first_report'));
ok(count($monthly)===1&&$monthly[0]['time']==='10:30'
    &&$monthly[0]['submission_state']==='not_submitted_all_branches',
    'monthly report has known 10:30 cutoff and proven no attestation');
$salaryRow=[
 'id'=>304,'company_id'=>1,'branch_id'=>2,'report_type'=>'salary_receipts',
 'period_date'=>'2026-10-10','status'=>'approved','revision'=>1,
 'submitted_by'=>22,'reviewed_by'=>44,
];
$source->records=[$salaryRow];
$withoutSalary=ReportingWatchSubmissionProjection::view($actor,'2026-10-10',2,$watch,$source,
    new DateTimeImmutable('2026-10-10 14:00:00',wp_timezone()));
ok(!in_array('salary_receipt_deadline',array_column($withoutSalary['schedule'],'id'),true)
    &&$withoutSalary['submission_evidence_summary']['hidden_salary_slots']===1
    &&$withoutSalary['branches'][0]['reporting_submissions']===[],
    'salary status and owner hidden from users without salary-view capability');
$finance=new Actor(11,111,1,2,[2],[Capabilities::REPORTS_VIEW,Capabilities::SALARY_VIEW],'RM');
$withSalary=ReportingWatchSubmissionProjection::view($finance,'2026-10-10',2,$watch,$source,
    new DateTimeImmutable('2026-10-10 14:00:00',wp_timezone()));
ok($withSalary['schedule'][1]['id']==='salary_receipt_deadline'
    &&$withSalary['schedule'][1]['submission_state']==='approved_all_branches'
    &&$withSalary['submission_evidence_summary']['approved']===1,
    'authorized salary reviewer gets real salary-attestation status, not payout verification');
$source->records=[array_merge($salaryRow,['company_id'=>2])];
denies(fn()=>ReportingWatchSubmissionProjection::view($actor,'2026-10-10',2,$watch,$source,
    new DateTimeImmutable('2026-10-10 14:00:00',wp_timezone())),'report_watch_source_invalid');
$source->records=[array_merge($salaryRow,['branch_id'=>4])];
denies(fn()=>ReportingWatchSubmissionProjection::view($actor,'2026-10-10',2,$watch,$source,
    new DateTimeImmutable('2026-10-10 14:00:00',wp_timezone())),'report_watch_source_invalid');
$source->records=[array_merge($salaryRow,['period_date'=>'2026-10-11'])];
denies(fn()=>ReportingWatchSubmissionProjection::view($actor,'2026-10-10',2,$watch,$source,
    new DateTimeImmutable('2026-10-10 14:00:00',wp_timezone())),'report_watch_source_invalid');
$source->records=[$salaryRow,$salaryRow];
denies(fn()=>ReportingWatchSubmissionProjection::view($actor,'2026-10-10',2,$watch,$source,
    new DateTimeImmutable('2026-10-10 14:00:00',wp_timezone())),'report_watch_source_invalid');
$source->records=[array_merge($salaryRow,['status'=>'posted_to_bank'])];
denies(fn()=>ReportingWatchSubmissionProjection::view($actor,'2026-10-10',2,$watch,$source,
    new DateTimeImmutable('2026-10-10 14:00:00',wp_timezone())),'report_watch_source_invalid');
$source->records=array_fill(0,61,$salaryRow);
denies(fn()=>ReportingWatchSubmissionProjection::view($actor,'2026-10-10',2,$watch,$source,
    new DateTimeImmutable('2026-10-10 14:00:00',wp_timezone())),'report_watch_source_invalid');
echo "WATCH + SUBMISSION REGISTRY PROJECTION: {$n}/{$n} PASS\n";
