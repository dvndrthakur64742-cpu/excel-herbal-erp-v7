<?php
namespace ExcelHerbal\ERP7\Workforce;

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Audit;
use ExcelHerbal\ERP7\Security\BranchAuthority;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\Guard;

/** Company-owned dated revisions in the existing settings store.
 *  No global option, no retroactive edits and no changes to salary rules.
 */
final class SelfAttendanceSettings {
    private const PREFIX='attendance_policy@';

    private static function authorize(Actor $actor): void {
        Guard::allActiveBranches($actor,Capabilities::ACCESS_MANAGE);
        if (!BranchAuthority::isCompanyWideAdmin($actor->employeeId,$actor->companyId,$actor->designationCode)) {
            throw new DomainException('Company-wide system administration is required.','attendance_policy_forbidden',403);
        }
    }

    private static function decode(array $row): array {
        $value=json_decode((string)$row['setting_value'],true);
        if (!is_array($value)) throw new DomainException('Attendance policy is invalid.','attendance_policy_invalid',503);
        return ['effective_from'=>substr((string)$row['setting_key'],strlen(self::PREFIX)),
            'times'=>SelfAttendancePolicy::schedule($value)];
    }

    public static function forDate(int $companyId,string $date): ?array {
        $db=Db::wpdb();
        $row=$db->get_row($db->prepare(
            "SELECT setting_key,setting_value FROM ".Db::table('settings')."
             WHERE company_id=%d AND setting_key LIKE %s AND setting_key<=%s
             ORDER BY setting_key DESC LIMIT 1",$companyId,self::PREFIX.'%',self::PREFIX.$date),ARRAY_A);
        if (($db->last_error??'')!=='') throw new DomainException('Attendance policy could not be read.','attendance_policy_unavailable',503);
        return $row ? self::decode($row) : null;
    }

    public static function read(Actor $actor): array {
        self::authorize($actor);
        $db=Db::wpdb();$today=Db::today();
        $rows=$db->get_results($db->prepare(
            "SELECT setting_key,setting_value FROM ".Db::table('settings')."
             WHERE company_id=%d AND setting_key LIKE %s AND setting_key>%s ORDER BY setting_key",
            $actor->companyId,self::PREFIX.'%',self::PREFIX.$today),ARRAY_A);
        if (($db->last_error??'')!=='') throw new DomainException('Attendance policy could not be read.','attendance_policy_unavailable',503);
        return ['business_date'=>$today,'defaults'=>SelfAttendancePolicy::DEFAULTS,
            'current'=>self::forDate($actor->companyId,$today),
            'upcoming'=>array_map([self::class,'decode'],(array)$rows)];
    }

    public static function save(Actor $actor,array $input): array {
        self::authorize($actor);
        $date=trim((string)($input['effective_from']??''));
        $parsed=\DateTimeImmutable::createFromFormat('!Y-m-d',$date);
        if (!$parsed || $parsed->format('Y-m-d')!==$date || $date<=Db::today()) {
            throw new DomainException('Choose a future business date.','attendance_policy_date_invalid',422);
        }
        $reason=trim((string)($input['reason']??''));
        if (strlen($reason)<5 || strlen($reason)>250) throw new DomainException('Enter a reason of 5 to 250 characters.','reason_required',422);
        $raw=$input['times']??null;
        if (!is_array($raw) || array_diff_key(SelfAttendancePolicy::DEFAULTS,$raw)) {
            throw new DomainException('All five attendance times are required.','attendance_policy_invalid',422);
        }
        $times=SelfAttendancePolicy::schedule($raw);
        return Transaction::run(function()use($actor,$date,$reason,$times){
            $db=Db::wpdb();$table=Db::table('settings');$key=self::PREFIX.$date;
            $company=$db->get_var($db->prepare("SELECT id FROM ".Db::table('companies')." WHERE id=%d FOR UPDATE",$actor->companyId));
            if ((int)$company!==$actor->companyId || $date<=Db::today()) throw new DomainException('Policy cannot be changed retroactively.','attendance_policy_date_invalid',409);
            $old=$db->get_row($db->prepare("SELECT * FROM {$table} WHERE company_id=%d AND setting_key=%s FOR UPDATE",$actor->companyId,$key),ARRAY_A);
            if (($db->last_error??'')!=='') throw new DomainException('Attendance policy could not be read.','attendance_policy_unavailable',503);
            $data=['setting_value'=>wp_json_encode($times),'updated_by'=>$actor->employeeId,'updated_at'=>Db::now()];
            if ($old) {
                Db::mustUpdate($db,$table,$data,['id'=>(int)$old['id'],'company_id'=>$actor->companyId]);
                $id=(int)$old['id'];
            } else {
                Db::mustInsert($db,$table,$data+['company_id'=>$actor->companyId,'setting_key'=>$key]);
                $id=(int)$db->insert_id;
            }
            Audit::add($actor,'attendance.policy_schedule','setting',$id,['effective_from'=>$date,'before'=>$old?self::decode($old):null,'times'=>$times,'reason'=>$reason]);
            return ['effective_from'=>$date,'times'=>$times];
        });
    }
}
