<?php
declare(strict_types=1);

/** No WordPress/database connection: exercise Step-1 attendance boundary and mutations. */
define('ARRAY_A','ARRAY_A');
$GLOBALS['eh8_test_time'] = '09:00:00';
function current_time(string $type, bool $gmt = false): string {
    if ($type === 'H:i:s') return $GLOBALS['eh8_test_time'];
    if ($type === 'Y-m-d') return '2026-10-22';
    if ($type === 'mysql') return '2026-10-22 09:00:00';
    throw new RuntimeException('Unexpected clock request '.$type);
}
function get_gmt_from_date(string $date): string { return $date; }
function wp_json_encode($v): string { return json_encode($v, JSON_THROW_ON_ERROR); }

require __DIR__.'/../src/Domain/DomainException.php';
require __DIR__.'/../src/Database/Db.php';
require __DIR__.'/../src/Database/Transaction.php';
require __DIR__.'/../src/Security/Actor.php';
require __DIR__.'/../src/Security/Capabilities.php';
require __DIR__.'/../src/Security/Guard.php';
require __DIR__.'/../src/Security/Audit.php';
require __DIR__.'/../src/Workforce/AttendancePolicy.php';
require __DIR__.'/../src/Workforce/ScheduledAttendanceService.php';
require __DIR__.'/../src/Workforce/GpsDutyPolicy.php';
require __DIR__.'/../src/Workforce/WorkforceService.php';

use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Workforce\AttendancePolicy;
use ExcelHerbal\ERP7\Workforce\GpsDutyPolicy;
use ExcelHerbal\ERP7\Workforce\ScheduledAttendanceService;
use ExcelHerbal\ERP7\Workforce\WorkforceService;

function check(bool $good,string $message): void { if (!$good) throw new RuntimeException($message); }
function rejects(callable $fn,string $code): void {
    try{$fn();}catch(DomainException $e){
        check($e->codeKey===$code,'Unexpected rejection: '.$e->codeKey.' (wanted '.$code.')');
        return;
    }
    throw new RuntimeException('Unexpected success; expected '.$code);
}
class AttendanceMockDb {
    public int $insert_id = 0;
    public string $prefix = 'wp_';
    public ?array $attendance = null;
    public array $queries = [];
    public array $audits = [];

    public function prepare(string $sql, ...$args): string {
        $index=0;
        return preg_replace_callback('/%[ds]/',function($found) use ($args,&$index){
            $value=$args[$index++];
            return $found[0]==='%d'?(string)(int)$value:"'".str_replace("'","''",(string)$value)."'";
        },$sql);
    }
    public function query(string $sql): int {
        $this->queries[]=$sql;
        return 1;
    }
    public function get_row(string $sql,$type=null): ?array {
        if(str_contains($sql,'FROM wp_eh7_employees'))return ['id'=>10];
        if(str_contains($sql,'FROM wp_eh7_attendance'))return $this->attendance;
        return null;
    }
    public function get_var(string $sql): int { return 0; }
    public function insert(string $table,array $row): int {
        if($table==='wp_eh7_attendance'){
            check($this->attendance===null,'Duplicate attendance insert');
            $this->insert_id=17;
            $this->attendance=['id'=>17,'company_id'=>1,'branch_id'=>3,
                'check_in_at'=>$row['check_in_at'],'check_out_at'=>null];
        }elseif($table==='wp_eh7_audit_log'){
            $this->audits[]=$row;
        }else throw new RuntimeException('Unexpected insert into '.$table);
        return 1;
    }
    public function update(string $table,array $data,array $where): int {
        if($table!=='wp_eh7_attendance')throw new RuntimeException('Unexpected update table.');
        if($this->attendance===null||$this->attendance['check_out_at']!==null)return 0;
        $this->attendance=array_merge($this->attendance,$data);
        return 1;
    }
}
$GLOBALS['wpdb'] = new AttendanceMockDb();
$actor=new Actor(5,10,1,3,[3],[Capabilities::ATT_SELF],'EMPLOYEE');

rejects(fn()=>AttendancePolicy::assertCheckInTime('08:59:59'),'attendance_checkin_window');
AttendancePolicy::assertCheckInTime('09:00:00');
AttendancePolicy::assertCheckInTime('17:59:59');
rejects(fn()=>AttendancePolicy::assertCheckInTime('18:00:00'),'attendance_checkin_window');
rejects(fn()=>AttendancePolicy::assertCheckOutTime('17:59:59'),'attendance_checkout_window');
AttendancePolicy::assertCheckOutTime('18:00:00');
AttendancePolicy::assertCheckOutTime('19:59:59');
rejects(fn()=>AttendancePolicy::assertCheckOutTime('20:00:00'),'attendance_checkout_window');
check(!AttendancePolicy::autoCheckOutDue('19:59:59'),'Early auto checkout');
check(AttendancePolicy::autoCheckOutDue('20:00:00'),'8 PM auto checkout missing');
check(GpsDutyPolicy::START==='10:30:00' && GpsDutyPolicy::STOP==='17:00:00',
    'GPS duty schedule must remain independent');

rejects(fn()=>WorkforceService::checkIn($actor,2,null,null),'attendance_branch_forbidden');
$GLOBALS['eh8_test_time']='08:59:59';
rejects(fn()=>WorkforceService::checkIn($actor,3,null,null),'attendance_checkin_window');
$GLOBALS['eh8_test_time']='09:15:00';
$checkIn=WorkforceService::checkIn($actor,3,null,null);
check($checkIn['id']===17 && count($GLOBALS['wpdb']->audits)===1,'Self check-in not inserted/audited');
rejects(fn()=>WorkforceService::checkIn($actor,3,null,null),'attendance_already_checked_in');
$GLOBALS['eh8_test_time']='17:59:59';
rejects(fn()=>WorkforceService::checkOut($actor,null,null),'attendance_checkout_window');
$GLOBALS['eh8_test_time']='18:00:00';
$checkOut=WorkforceService::checkOut($actor,null,null);
check($checkOut['id']===17 && count($GLOBALS['wpdb']->audits)===2,'Self checkout not updated/audited');
rejects(fn()=>WorkforceService::checkOut($actor,null,null),'attendance_already_checked_out');
$before=count($GLOBALS['wpdb']->queries);
$GLOBALS['eh8_test_time']='19:59:59';
ScheduledAttendanceService::run();
check(count($GLOBALS['wpdb']->queries)===$before,'Scheduled close ran before 8 PM');
$GLOBALS['eh8_test_time']='20:00:00';
ScheduledAttendanceService::run();
$sql=end($GLOBALS['wpdb']->queries);
check(str_starts_with(trim($sql),'UPDATE wp_eh7_attendance'),'Auto-close must only UPDATE');
check(str_contains($sql,"business_date='2026-10-22'"),'Auto-close must not rewrite historical rows');
check(str_contains($sql,'check_in_at IS NOT NULL AND check_out_at IS NULL'),'Never fabricate attendance or replace manual check-outs');
echo "PASS attendance: 9 AM self check-in, 6 PM self checkout, 8 PM auto close, strict branch, GPS window unchanged\n";
