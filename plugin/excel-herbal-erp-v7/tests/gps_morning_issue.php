<?php
/** Executable GPS evidence contract; all employee data is synthetic. */
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Workforce\AttendanceGpsEvidence;

class SyntheticGpsDb {
    public string $prefix='wp_';
    public bool $pointExists=false;
    public bool $failUpdate=false;
    public array $lastPreparedArgs=[];
    public string $lastSql='';
    public array $updates=[];
    public function prepare($sql,...$args):string {
        $this->lastSql=$sql;
        $this->lastPreparedArgs=$args;
        return $sql;
    }
    public function get_var($sql):int {return $this->pointExists?1:0;}
    public function update($table,$data,$where) {
        $this->updates[]=[$table,$data,$where];
        return $this->failUpdate?false:1;
    }
}
$wpdb=new SyntheticGpsDb();
function ensureGps(bool $truth,string $label):void{
    if(!$truth)throw new RuntimeException('FAIL '.$label);
    echo 'PASS '.$label."\n";
}
ensureGps(!AttendanceGpsEvidence::hasVerifiedMorningPoint(12,5,42,'2026-11-02'),'scheduled attendance alone cannot authorize stock issue');
ensureGps($wpdb->lastPreparedArgs===[12,5,42,'2026-11-02'],'GPS matching uses company branch employee and date');
foreach([
    'INNER JOIN wp_eh7_gps_points g','g.attendance_id=a.id',
    'g.company_id=a.company_id','g.branch_id=a.branch_id',
    'g.employee_id=a.employee_id','g.recorded_at>=a.check_in_at',
    'g.recorded_at<=UTC_TIMESTAMP()'
] as $required){
    ensureGps(str_contains($wpdb->lastSql,$required),'GPS evidence filter: '.$required);
}
$wpdb->pointExists=true;
ensureGps(AttendanceGpsEvidence::hasVerifiedMorningPoint(12,5,42,'2026-11-02'),'real matched GPS point authorizes stock request');
AttendanceGpsEvidence::captureFirstPoint($wpdb,700,12,42,31.701,76.93);
[$table,$data,$where]=$wpdb->updates[0];
ensureGps($table==='wp_eh7_attendance'&&$data===['check_in_lat'=>31.701,'check_in_lng'=>76.93],'first actual GPS point is projected to attendance');
ensureGps($where===['id'=>700,'company_id'=>12,'employee_id'=>42,'check_in_lat'=>null,'check_in_lng'=>null],'first point cannot overwrite existing check-in coordinate');
$wpdb->failUpdate=true;
try {
    AttendanceGpsEvidence::captureFirstPoint($wpdb,700,12,42,31.702,76.931);
    throw new RuntimeException('Failed database write was accepted');
} catch(DomainException $e) {
    ensureGps($e->codeKey==='database_update_failed','failed GPS coordinate projection rolls back insert transaction');
}
$daily=file_get_contents(__DIR__.'/../src/DailyOrder/DailyOrderService.php');
$recovery=file_get_contents(__DIR__.'/../src/Recovery/RecoveryService.php');
ensureGps(str_contains($daily,'AttendanceGpsEvidence::hasVerifiedMorningPoint('),'morning issue uses GPS evidence not scheduled presence');
ensureGps(str_contains($recovery,'AttendanceGpsEvidence::captureFirstPoint('),'GPS insert projects evidence into attendance');
echo "PASSED GPS morning issue evidence contract\n";
