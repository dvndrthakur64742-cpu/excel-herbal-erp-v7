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
        $db=Db::wpdb();$t=Db::table('holidays');$exists=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$t} WHERE company_id=%d AND holiday_date=%s AND active=1 AND ((branch_id IS NULL AND %d=0) OR branch_id=%d)",$a->companyId,$date,$branch??0,$branch??0));
        if($exists)throw new DomainException('An active holiday already exists for this date and scope.','holiday_duplicate',409);
        Db::mustInsert($db,$t,['company_id'=>$a->companyId,'branch_id'=>$branch,'holiday_date'=>$date,'name'=>$name,'active'=>1,'created_by'=>$a->employeeId,'created_at'=>Db::now()]);$id=(int)$db->insert_id;
        Audit::add($a,'holiday.create','holiday',$id,['branch_id'=>$branch,'holiday_date'=>$date]);return ['id'=>$id,'branch_id'=>$branch,'holiday_date'=>$date,'name'=>$name,'active'=>true];
    }
    public static function update(Actor $a,int $id,array $data):array {
        Guard::cap($a,Capabilities::LEAVE_MANAGE);return Transaction::run(function()use($a,$id,$data){$db=Db::wpdb();$t=Db::table('holidays');$r=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE id=%d AND company_id=%d FOR UPDATE",$id,$a->companyId),ARRAY_A);if(!$r)throw new DomainException('Holiday not found.','holiday_not_found',404);if((int)($r['branch_id']??0)>0)Guard::branch($a,(int)$r['branch_id'],Capabilities::LEAVE_MANAGE);
            $branch=array_key_exists('branch_id',$data)?self::branch($a,$data['branch_id']):($r['branch_id']===null?null:(int)$r['branch_id']);$date=array_key_exists('holiday_date',$data)?Input::date((string)$data['holiday_date'],'Holiday date'):(string)$r['holiday_date'];$name=array_key_exists('name',$data)?trim((string)$data['name']):(string)$r['name'];if($name===''||strlen($name)>190)throw new DomainException('Holiday name is invalid.','holiday_invalid',422);
            $exists=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM {$t} WHERE company_id=%d AND id<>%d AND holiday_date=%s AND active=1 AND ((branch_id IS NULL AND %d=0) OR branch_id=%d)",$a->companyId,$id,$date,$branch??0,$branch??0));if($exists)throw new DomainException('An active holiday already exists for this date and scope.','holiday_duplicate',409);Db::mustUpdate($db,$t,['branch_id'=>$branch,'holiday_date'=>$date,'name'=>$name],['id'=>$id]);Audit::add($a,'holiday.update','holiday',$id,['branch_id'=>$branch,'holiday_date'=>$date]);return ['id'=>$id,'branch_id'=>$branch,'holiday_date'=>$date,'name'=>$name,'active'=>(bool)$r['active']];});
    }
    public static function deactivate(Actor $a,int $id):array {
        Guard::cap($a,Capabilities::LEAVE_MANAGE);$db=Db::wpdb();$t=Db::table('holidays');$r=$db->get_row($db->prepare("SELECT id,branch_id,active FROM {$t} WHERE id=%d AND company_id=%d",$id,$a->companyId),ARRAY_A);if(!$r)throw new DomainException('Holiday not found.','holiday_not_found',404);if((int)($r['branch_id']??0)>0)Guard::branch($a,(int)$r['branch_id'],Capabilities::LEAVE_MANAGE);if((int)$r['active']===1)Db::mustUpdate($db,$t,['active'=>0],['id'=>$id]);Audit::add($a,'holiday.deactivate','holiday',$id,[]);return ['id'=>$id,'active'=>false];
    }
    private static function branch(Actor $a,mixed $raw):?int {$branch=($raw===null||$raw==='')?null:(int)$raw;if($branch!==null){if($branch<1)throw new DomainException('branch_id must be positive or omitted for company-wide holiday.','holiday_invalid',422);Guard::branch($a,$branch,Capabilities::LEAVE_MANAGE);return $branch;}self::companyWide($a);return null;}
    private static function companyWide(Actor $a):void {if($a->can(Capabilities::ACCESS_MANAGE))return;$db=Db::wpdb();$total=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('branches')." WHERE company_id=%d AND status='active'",$a->companyId));$owned=count(array_unique(array_filter(array_map('intval',$a->branchIds),fn($v)=>$v>0)));if($total<1||$owned<$total)throw new DomainException('Company-wide holiday requires authority over all active branches.','company_scope_forbidden',403);}
}
