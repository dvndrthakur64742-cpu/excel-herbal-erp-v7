<?php
declare(strict_types=1);
require_once __DIR__.'/../src/Domain/DomainException.php';
require_once __DIR__.'/../src/Security/Actor.php';
require_once __DIR__.'/../src/Security/Capabilities.php';
require_once __DIR__.'/../src/Security/Guard.php';
require_once __DIR__.'/../src/Reporting/ReportReminderDrafts.php';

use ExcelHerbal\ERP7\Reporting\ReportReminderDrafts;
use ExcelHerbal\ERP7\Security\{Actor,Capabilities};
use ExcelHerbal\ERP7\Domain\DomainException;
$tests=0;
function ok(bool $pass,string $name):void{
    global $tests;
    if(!$pass)throw new RuntimeException('FAIL '.$name);
    ++$tests;echo 'PASS '.$name.PHP_EOL;
}
function denies(callable $fn,string $key):void {
    try{$fn();throw new RuntimeException('Expected '.$key);}
    catch(DomainException $e){ok($e->codeKey===$key,'Denied '.$key);}
}
$bm=new Actor(1,11,1,2,[2],[Capabilities::REPORTS_VIEW,Capabilities::REPORT_SUBMIT],'BM');
$reviewer=new Actor(2,22,1,2,[2,4],[Capabilities::REPORTS_VIEW,Capabilities::REPORT_REVIEW],'RM');
denies(fn()=>ReportReminderDrafts::dismiss($bm,2,1,'Dismiss report reminder draft for a reason'),'permission_denied');
denies(fn()=>ReportReminderDrafts::dismiss($reviewer,3,1,'Dismiss report reminder draft for a reason'),'branch_forbidden');
denies(fn()=>ReportReminderDrafts::dismiss($reviewer,2,0,'Dismiss report reminder draft for a reason'),'report_draft_dismiss_invalid');
denies(fn()=>ReportReminderDrafts::dismiss($reviewer,2,1,'short'),'report_draft_dismiss_invalid');
denies(fn()=>ReportReminderDrafts::dismiss($reviewer,2,1,str_repeat('x',501)),'report_draft_dismiss_invalid');
denies(fn()=>ReportReminderDrafts::dismiss($reviewer,2,1,"Invalid\x01 reason for audit"),'report_draft_dismiss_invalid');
$source=file_get_contents(__DIR__.'/../src/Reporting/ReportReminderDrafts.php');
$schema=file_get_contents(__DIR__.'/../src/Database/Schema.php');
$routes=file_get_contents(__DIR__.'/../src/Http/RouteRegistry.php');
$dispatch=file_get_contents(__DIR__.'/../src/Http/ApiDispatch.php');
ok(str_contains($source,'FOR UPDATE')
    &&str_contains($source,"'state'=>'dismissed'")
    &&str_contains($source,"'state'=>'draft'")
    &&str_contains($source,"'report.reminder_draft.dismiss'"),
    'Dismiss uses row lock, checked state transition and append-only audit');
ok(str_contains($schema,'UNIQUE KEY uniq_draft_key(dedupe_key)')
    &&str_contains($schema,'dismissal_reason VARCHAR(500)')
    &&str_contains($schema,'dismissed_by BIGINT UNSIGNED'),
    'DB keeps anti-duplicate and reviewer reason column');
ok(str_contains($routes,'/reports/reminder-drafts/prepare')
    &&str_contains($routes,"/reports/reminder-drafts/(?P<id>\\\\d+)/dismiss"),
    'Only internal prepare and dismiss mutation routes are registered');
ok(str_contains($dispatch,"'reports.reminder_dismiss'=>ReportReminderDrafts::dismiss")
    &&str_contains($source,"'dispatch_enabled'=>false")
    &&str_contains($source,"'notifications_sent'=>0"),
    'REST transition never asserts outbound notification delivery');
ok(!str_contains($source,'wp_mail(')
    &&!str_contains($source,'wp_schedule_event(')
    &&!str_contains($source,'curl_exec('),
    'Outbox review cannot send email, cron or network messages');

// Real method regression with a WordPress-shaped, branch-scoped in-memory
// reader: no database writes, outgoing messages or production fixtures.
require_once __DIR__.'/../src/Core/Input.php';
require_once __DIR__.'/../src/Database/Db.php';
if(!defined('ARRAY_A'))define('ARRAY_A','ARRAY_A');
final class ReminderReviewFakeDb {
    public string $prefix='wp_';
    public string $lastSql='';
    public array $lastArgs=[];
    public array $rows=[];
    public function prepare(string $sql,mixed ...$args):string {
        $this->lastSql=$sql;$this->lastArgs=$args;return $sql;
    }
    public function get_results(string $sql,string $output):array {
        if($output!==ARRAY_A||$sql!==$this->lastSql)throw new RuntimeException('Unexpected SQL query.');
        [$company,$branch,$date]=$this->lastArgs;
        return array_values(array_filter($this->rows,function(array $row)use($company,$branch,$date):bool{
            if($row['company_id']!==$company||$row['branch_id']!==$branch||$row['period_date']!==$date)
                return false;
            if(str_contains($this->lastSql,"report_type <> 'salary_receipts'")
                &&$row['report_type']==='salary_receipts')return false;
            if(str_contains($this->lastSql,"state IN ('draft','dismissed')"))
                return in_array($row['state'],['draft','dismissed'],true);
            return $row['state']===$this->lastArgs[3];
        }));
    }
}
$wpdb=new ReminderReviewFakeDb();
foreach([
    [1,2,'evening_daily_closing','draft'],
    [1,2,'monthly_report','dismissed'],
    [1,2,'salary_receipts','draft'],
    [1,2,'salary_receipts','dismissed'],
    [1,4,'monthly_report','draft'],
    [5,2,'monthly_report','draft'],
] as $i=>$row){
    $wpdb->rows[]=['id'=>$i+1,'company_id'=>$row[0],'branch_id'=>$row[1],
        'report_type'=>$row[2],'state'=>$row[3],'period_date'=>'2026-10-21'];
}
$view=ReportReminderDrafts::list($reviewer,2,'2026-10-21');
ok($view['state_filter']==='draft'&&count($view['drafts'])===1
    &&$view['drafts'][0]['report_type']==='evening_daily_closing',
    'Default inbox hides salary and dismissed records without changing existing behavior');
$view=ReportReminderDrafts::list($reviewer,2,'2026-10-21','all');
ok(count($view['drafts'])===2&&$view['notifications_sent']===0
    &&$view['dispatch_enabled']===false,
    'All-state audit view is company/branch scoped and excludes salary data');
$view=ReportReminderDrafts::list($reviewer,2,'2026-10-21','dismissed');
ok(count($view['drafts'])===1&&$view['drafts'][0]['report_type']==='monthly_report',
    'Dismissed history can be reviewed without revealing payroll records');
$salaryReviewer=new Actor(3,33,1,2,[2],[
    Capabilities::REPORTS_VIEW,Capabilities::REPORT_REVIEW,Capabilities::SALARY_VIEW],'RM');
$view=ReportReminderDrafts::list($salaryReviewer,2,'2026-10-21','all');
ok(count($view['drafts'])===4
    &&!str_contains($wpdb->lastSql,"report_type <> 'salary_receipts'"),
    'Effective salary-view capability explicitly enables salary reminder history');
denies(fn()=>ReportReminderDrafts::list($reviewer,4,'2026-10-21','unknown'),
    'report_draft_state_invalid');
denies(fn()=>ReportReminderDrafts::list($reviewer,3,'2026-10-21'),
    'branch_forbidden');
denies(fn()=>ReportReminderDrafts::list($bm,2,'2026-10-21'),
    'permission_denied');
denies(fn()=>ReportReminderDrafts::list($reviewer,2,'2026-02-30'),
    'date_invalid');
ok(substr_count($source,"report_type <> 'salary_receipts'")===2,
    'Salary visibility restriction applies to both list and dismiss SQL');

ok(str_contains($routes,"/reports/reminder-drafts/freshness")
    &&str_contains($dispatch,"'reports.reminder_freshness'=>ReportReminderDrafts::inspect"),
    'Read-only freshness review is registered separately from all mutations');
ok(str_contains($source,"$list['snapshot_atomic']=false")
    &&str_contains($source,"$list['automatic_dismissal']=false")
    &&str_contains($source,"$list['source_rechecked']=true"),
    'Freshness states disclose non-atomic evidence and never auto-dismiss');
ok(!str_contains($source,'wp_mail(')&&!str_contains($source,'wp_schedule_event('),
    'Freshness inspection has no transport or scheduler');
echo "MANAGER NOTIFICATION CENTER PHP: {$tests}/{$tests} PASS\n";
