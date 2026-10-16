<?php
namespace ExcelHerbal\ERP7\Workforce;

use ExcelHerbal\ERP7\Core\Input;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Audit;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\Guard;

final class HolidayService {
    public static function create(Actor $a,array $data):array {
        Guard::cap($a,Capabilities::LEAVE_MANAGE);$branch=self::branch($a,$data['branch_id']??null);$date=Input::date((string)($data['holiday_date']??''),'Holiday date');$name=trim((string)($data['name']??''));
        if($name===''||strlen($name)>190)throw new DomainException('Holiday name is required and must be 190 characters or fewer.','holiday_invalid',422);
        return Transaction::run(function()use($a,$branch,$date,$name){\ExcelHerbal\ERP7\Payroll\SalaryService::lockCompany($a->companyId);self::assertPayrollMutable($a,$branch,$date);$db=Db::wpdb();$t=Db::table('holidays');$exists=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$t} WHERE company_id=%d AND holiday_date=%s AND active=1 AND ((branch_id IS NULL AND %d=0) OR branch_id=%d)",$a->companyId,$date,$branch??0,$branch??0));if($exists)throw new DomainException('An active holiday already exists for this date and scope.','holiday_duplicate',409);Db::mustInsert($db,$t,['company_id'=>$a->companyId,'branch_id'=>$branch,'holiday_date'=>$date,'name'=>$name,'active'=>1,'created_by'=>$a->employeeId,'created_at'=>Db::now()]);$id=(int)$db->insert_id;Audit::add($a,'holiday.create','holiday',$id,['branch_id'=>$branch,'holiday_date'=>$date]);return ['id'=>$id,'branch_id'=>$branch,'holiday_date'=>$date,'name'=>$name,'active'=>true];});
    }
    public static function update(Actor $a,int $id,array $data):array {
        Guard::cap($a,Capabilities::LEAVE_MANAGE);return Transaction::run(function()use($a,$id,$data){\ExcelHerbal\ERP7\Payroll\SalaryService::lockCompany($a->companyId);$db=Db::wpdb();$t=Db::table('holidays');$r=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE id=%d AND company_id=%d FOR UPDATE",$id,$a->companyId),ARRAY_A);if(!$r)throw new DomainException('Holiday not found.','holiday_not_found',404);if((int)($r['branch_id']??0)>0)Guard::branch($a,(int)$r['branch_id'],Capabilities::LEAVE_MANAGE);else self::companyWide($a);
            $branch=array_key_exists('branch_id',$data)?self::branch($a,$data['branch_id']):($r['branch_id']===null?null:(int)$r['branch_id']);$date=array_key_exists('holiday_date',$data)?Input::date((string)$data['holiday_date'],'Holiday date'):(string)$r['holiday_date'];$name=array_key_exists('name',$data)?trim((string)$data['name']):(string)$r['name'];if($name===''||strlen($name)>190)throw new DomainException('Holiday name is invalid.','holiday_invalid',422);
            $oldBranch=$r['branch_id']===null?null:(int)$r['branch_id'];$scopeChanged=$oldBranch!==$branch||(string)$r['holiday_date']!==$date;if((int)$r['active']===1&&$scopeChanged){self::assertPayrollMutable($a,$oldBranch,(string)$r['holiday_date']);self::assertPayrollMutable($a,$branch,$date);}
            $exists=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$t} WHERE company_id=%d AND id<>%d AND holiday_date=%s AND active=1 AND ((branch_id IS NULL AND %d=0) OR branch_id=%d)",$a->companyId,$id,$date,$branch??0,$branch??0));if($exists)throw new DomainException('An active holiday already exists for this date and scope.','holiday_duplicate',409);Db::mustUpdate($db,$t,['branch_id'=>$branch,'holiday_date'=>$date,'name'=>$name],['id'=>$id]);Audit::add($a,'holiday.update','holiday',$id,['branch_id'=>$branch,'holiday_date'=>$date]);return ['id'=>$id,'branch_id'=>$branch,'holiday_date'=>$date,'name'=>$name,'active'=>(bool)$r['active']];});
    }
    public static function deactivate(Actor $a,int $id):array {
        Guard::cap($a,Capabilities::LEAVE_MANAGE);return Transaction::run(function()use($a,$id){\ExcelHerbal\ERP7\Payroll\SalaryService::lockCompany($a->companyId);$db=Db::wpdb();$t=Db::table('holidays');$r=$db->get_row($db->prepare("SELECT id,branch_id,holiday_date,active FROM {$t} WHERE id=%d AND company_id=%d FOR UPDATE",$id,$a->companyId),ARRAY_A);if(!$r)throw new DomainException('Holiday not found.','holiday_not_found',404);if((int)($r['branch_id']??0)>0)Guard::branch($a,(int)$r['branch_id'],Capabilities::LEAVE_MANAGE);else self::companyWide($a);if((int)$r['active']!==1)return ['id'=>$id,'active'=>false,'unchanged'=>true];self::assertPayrollMutable($a,$r['branch_id']===null?null:(int)$r['branch_id'],(string)$r['holiday_date']);Db::mustUpdate($db,$t,['active'=>0],['id'=>$id]);Audit::add($a,'holiday.deactivate','holiday',$id,[]);return ['id'=>$id,'active'=>false,'unchanged'=>false];});
    }
    private static function assertPayrollMutable(Actor $a,?int $branch,string $date):void {$db=Db::wpdb();$sql="SELECT COUNT(*) FROM ".Db::table('payroll_runs')." WHERE company_id=%d AND period_start<=%s AND period_end>=%s";$args=[$a->companyId,$date,$date];if($branch!==null){$sql.=" AND branch_id=%d";$args[]=$branch;}$count=(int)$db->get_var($db->prepare($sql,...$args));if($count)throw new DomainException('Holiday change conflicts with an existing payroll period. Regenerate or review payroll first.','holiday_payroll_conflict',409);}
    private static function branch(Actor $a,mixed $raw):?int {$branch=($raw===null||$raw==='')?null:(int)$raw;if($branch!==null){if($branch<1)throw new DomainException('branch_id must be positive or omitted for company-wide holiday.','holiday_invalid',422);Guard::branch($a,$branch,Capabilities::LEAVE_MANAGE);return $branch;}self::companyWide($a);return null;}
    private static function companyWide(Actor $a):void {if($a->can(Capabilities::ACCESS_MANAGE))return;$db=Db::wpdb();$total=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('branches')." WHERE company_id=%d AND status='active'",$a->companyId));$owned=count(array_unique(array_filter(array_map('intval',$a->branchIds),fn($v)=>$v>0)));if($total<1||$owned<$total)throw new DomainException('Company-wide holiday requires authority over all active branches.','company_scope_forbidden',403);}
}
