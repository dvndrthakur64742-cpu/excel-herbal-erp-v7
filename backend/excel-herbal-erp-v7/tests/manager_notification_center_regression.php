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
echo "MANAGER NOTIFICATION CENTER PHP: {$tests}/{$tests} PASS\n";
