<?php
namespace ExcelHerbal\ERP7\Workforce;

use ExcelHerbal\ERP7\Database\Db;

/**
 * Attendance is scheduled by the server, but field-stock custody must only
 * proceed after a real authenticated GPS point has been recorded.
 */
final class AttendanceGpsEvidence {
    public static function captureFirstPoint(object $db,int $attendanceId,int $companyId,int $employeeId,float $lat,float $lng):void {
        // Persist only the first accepted GPS coordinate; do not overwrite it
        // with later route points. This runs in the GPS insert transaction.
        Db::mustUpdate($db,Db::table('attendance'),
            ['check_in_lat'=>$lat,'check_in_lng'=>$lng],
            ['id'=>$attendanceId,'company_id'=>$companyId,'employee_id'=>$employeeId,
             'check_in_lat'=>null,'check_in_lng'=>null]);
    }

    public static function hasVerifiedMorningPoint(int $companyId,int $branchId,int $employeeId,string $businessDate):bool {
        $db=Db::wpdb();
        $attendance=Db::table('attendance');
        $points=Db::table('gps_points');
        // A scheduled check-in alone is NOT GPS evidence. The recorded GPS
        // point must belong to the same attendance, company, branch and employee.
        $query="SELECT COUNT(*) FROM {$attendance} a
                INNER JOIN {$points} g
                  ON g.attendance_id=a.id
                 AND g.company_id=a.company_id
                 AND g.branch_id=a.branch_id
                 AND g.employee_id=a.employee_id
                WHERE a.company_id=%d AND a.branch_id=%d
                  AND a.employee_id=%d AND a.business_date=%s
                  AND a.check_in_at IS NOT NULL
                  AND g.recorded_at>=a.check_in_at
                  AND g.recorded_at<=UTC_TIMESTAMP()";
        return (int)$db->get_var($db->prepare($query,$companyId,$branchId,$employeeId,$businessDate))>0;
    }
}
