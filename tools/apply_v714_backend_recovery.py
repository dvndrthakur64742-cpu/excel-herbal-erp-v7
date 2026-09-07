#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path('recovered-source')
BACKEND = ROOT / 'backend' / 'excel-herbal-erp-v7'
SRC = BACKEND / 'src'


def read(path):
    return path.read_text()


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def replace_once(path, old, new, label):
    s = read(path)
    if new in s:
        return
    count = s.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one marker in {path}, got {count}')
    write(path, s.replace(old, new, 1))


quantity_rules = r'''<?php
namespace ExcelHerbal\ERP7\Domain;

final class QuantityRules {
    public static function whole(mixed $value,string $field='quantity',bool $allowZero=false,bool $signed=false):int {
        if($value===null||$value===''||!is_numeric($value)) throw new DomainException($field.' must be whole PCS.','whole_pcs_required',422);
        $n=(float)$value;
        if(!is_finite($n)||abs($n-round($n))>.000001) throw new DomainException($field.' must be whole PCS.','whole_pcs_required',422);
        $i=(int)round($n);
        if(!$signed&&$i<0) throw new DomainException($field.' cannot be negative.','whole_pcs_invalid',422);
        if(!$allowZero&&$i===0) throw new DomainException($field.' must be greater than zero.','whole_pcs_invalid',422);
        return $i;
    }
    public static function positive(mixed $value,string $field='quantity'):int{return self::whole($value,$field,false,false);}
    public static function nonNegative(mixed $value,string $field='quantity'):int{return self::whole($value,$field,true,false);}
    public static function signedNonZero(mixed $value,string $field='quantity'):int{return self::whole($value,$field,false,true);}
    public static function positiveLines(array $lines,string $field='quantity'):void{foreach($lines as$i=>$line){self::positive(is_array($line)?($line[$field]??null):null,$field.' line '.($i+1));}}
    public static function nonNegativeLines(array $lines,array $fields):void{foreach($lines as$i=>$line){foreach($fields as$field)self::nonNegative(is_array($line)?($line[$field]??0):null,$field.' line '.($i+1));}}
    public static function signedNonZeroLines(array $lines,string $field='quantity_delta'):void{foreach($lines as$i=>$line){self::signedNonZero(is_array($line)?($line[$field]??null):null,$field.' line '.($i+1));}}
}
'''
write(SRC/'Domain'/'QuantityRules.php', quantity_rules)

recovery_schema = r'''<?php
namespace ExcelHerbal\ERP7\Recovery;

use ExcelHerbal\ERP7\Database\Db;

final class RecoverySchema {
    public const VERSION='7.1.14-recovery-1';
    public static function installIfNeeded():void {
        if((string)get_option('eh7_recovery_schema_version','')===self::VERSION)return;
        self::install();
    }
    public static function install():void {
        require_once ABSPATH.'wp-admin/includes/upgrade.php';
        $db=Db::wpdb();$charset=$db->get_charset_collate();
        $defs=[
            'gps_points'=>"id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,company_id BIGINT UNSIGNED NOT NULL,branch_id BIGINT UNSIGNED NOT NULL,employee_id BIGINT UNSIGNED NOT NULL,field_visit_id BIGINT UNSIGNED NULL,business_date DATE NOT NULL,lat DECIMAL(10,7) NOT NULL,lng DECIMAL(10,7) NOT NULL,accuracy DECIMAL(10,2) NULL,source VARCHAR(30) NOT NULL DEFAULT 'periodic',captured_at DATETIME NOT NULL,created_at DATETIME NOT NULL,PRIMARY KEY(id),KEY employee_date(company_id,employee_id,business_date,captured_at),KEY branch_date(company_id,branch_id,business_date,captured_at)",
            'employee_documents'=>"id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,company_id BIGINT UNSIGNED NOT NULL,employee_id BIGINT UNSIGNED NOT NULL,document_type VARCHAR(60) NOT NULL,title VARCHAR(190) NOT NULL,original_name VARCHAR(190) NOT NULL,mime_type VARCHAR(100) NOT NULL,file_size BIGINT UNSIGNED NOT NULL,sha256 CHAR(64) NOT NULL,storage_key VARCHAR(190) NOT NULL,status VARCHAR(20) NOT NULL DEFAULT 'active',uploaded_by BIGINT UNSIGNED NOT NULL,created_at DATETIME NOT NULL,PRIMARY KEY(id),KEY employee(company_id,employee_id,status),UNIQUE KEY uq_storage(storage_key)",
            'announcement_acknowledgements'=>"id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,company_id BIGINT UNSIGNED NOT NULL,announcement_id BIGINT UNSIGNED NOT NULL,employee_id BIGINT UNSIGNED NOT NULL,acknowledged_at DATETIME NOT NULL,PRIMARY KEY(id),UNIQUE KEY uq_ack(company_id,announcement_id,employee_id),KEY employee(company_id,employee_id,acknowledged_at)",
            'push_tokens'=>"id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,company_id BIGINT UNSIGNED NOT NULL,employee_id BIGINT UNSIGNED NOT NULL,token_hash CHAR(64) NOT NULL,token VARCHAR(512) NOT NULL,platform VARCHAR(30) NOT NULL,device_name VARCHAR(190) NULL,active TINYINT(1) NOT NULL DEFAULT 1,registered_at DATETIME NOT NULL,last_seen_at DATETIME NOT NULL,revoked_at DATETIME NULL,PRIMARY KEY(id),UNIQUE KEY uq_token(token_hash),KEY employee(company_id,employee_id,active)",
            'task_details'=>"task_id BIGINT UNSIGNED NOT NULL,company_id BIGINT UNSIGNED NOT NULL,description TEXT NULL,priority VARCHAR(20) NOT NULL DEFAULT 'normal',created_by BIGINT UNSIGNED NOT NULL,assigned_by BIGINT UNSIGNED NOT NULL,updated_at DATETIME NOT NULL,PRIMARY KEY(task_id),KEY company_creator(company_id,created_by)",
        ];
        foreach($defs as$name=>$body)dbDelta('CREATE TABLE '.Db::table($name).' ('.$body.') '.$charset.';');
        update_option('eh7_recovery_schema_version',self::VERSION,false);
    }
}
'''
write(SRC/'Recovery'/'RecoverySchema.php', recovery_schema)

recovery_service = r'''<?php
namespace ExcelHerbal\ERP7\Recovery;

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Audit;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\Guard;

final class RecoveryService {
    public static function gpsPoint(Actor $a,int $branch,float $lat,float $lng,?float $accuracy,string $source='periodic'):array {
        Guard::branch($a,$branch,Capabilities::ATT_SELF);self::coordinates($lat,$lng,$accuracy);$source=sanitize_key($source?:'periodic');if(!in_array($source,['periodic','transaction','manual'],true))$source='periodic';
        $db=Db::wpdb();$attendance=$db->get_row($db->prepare("SELECT * FROM ".Db::table('attendance')." WHERE company_id=%d AND employee_id=%d AND business_date=%s",$a->companyId,$a->employeeId,Db::today()),ARRAY_A);
        if(!$attendance||empty($attendance['check_in_at']))throw new DomainException('Attendance Check-In required before GPS duty tracking.','gps_checkin_required',409);
        if(!empty($attendance['check_out_at']))throw new DomainException('GPS duty tracking is closed after Check-Out.','gps_after_checkout',409);
        if((int)$attendance['branch_id']!==$branch)throw new DomainException('GPS branch must match today attendance branch.','gps_branch_mismatch',409);
        if($source==='periodic'){$last=(string)$db->get_var($db->prepare("SELECT captured_at FROM ".Db::table('gps_points')." WHERE company_id=%d AND employee_id=%d AND business_date=%s AND source='periodic' ORDER BY id DESC LIMIT 1",$a->companyId,$a->employeeId,Db::today()));if($last&&strtotime(Db::now())-strtotime($last)<1200)throw new DomainException('Periodic GPS point is too early.','gps_ping_too_soon',429);}
        $visit=(int)$db->get_var($db->prepare("SELECT id FROM ".Db::table('field_visits')." WHERE company_id=%d AND employee_id=%d AND status='in_progress' ORDER BY id DESC LIMIT 1",$a->companyId,$a->employeeId));
        Db::mustInsert($db,Db::table('gps_points'),['company_id'=>$a->companyId,'branch_id'=>$branch,'employee_id'=>$a->employeeId,'field_visit_id'=>$visit?:null,'business_date'=>Db::today(),'lat'=>$lat,'lng'=>$lng,'accuracy'=>$accuracy,'source'=>$source,'captured_at'=>Db::now(),'created_at'=>Db::now()]);$id=(int)$db->insert_id;
        return['id'=>$id,'captured_at'=>Db::now(),'next_periodic_after_seconds'=>$source==='periodic'?1800:null];
    }
    public static function gpsRoute(Actor $a,int $employee,string $date,?int $branch):array {
        $date=self::date($date?:Db::today());$employee=$employee?:$a->employeeId;$emp=self::employee($a,$employee);$targetBranch=$branch?:((int)$emp['assigned_branch_id']);
        if($employee===$a->employeeId){Guard::cap($a,Capabilities::ATT_SELF);if($branch&& !$a->hasBranch($branch))throw new DomainException('Branch is outside effective authority.','branch_forbidden',403);}else{Guard::branch($a,$targetBranch,Capabilities::ATT_MANAGE);}
        $db=Db::wpdb();$where='company_id=%d AND employee_id=%d AND business_date=%s';$args=[$a->companyId,$employee,$date];if($branch){$where.=' AND branch_id=%d';$args[]=$branch;}
        $rows=(array)$db->get_results($db->prepare("SELECT id,branch_id,field_visit_id,lat,lng,accuracy,source,captured_at FROM ".Db::table('gps_points')." WHERE {$where} ORDER BY captured_at,id",...$args),ARRAY_A);
        foreach($rows as$row)if(!$a->hasBranch((int)$row['branch_id'])&&$employee!==$a->employeeId)throw new DomainException('GPS route contains branch outside authority.','branch_forbidden',403);
        return['employee_id'=>$employee,'business_date'=>$date,'points'=>$rows,'count'=>count($rows)];
    }
    public static function visitHistory(Actor $a,int $employee,?int $branch,string $from,string $to):array {
        $employee=$employee?:$a->employeeId;$emp=self::employee($a,$employee);$branch=$branch?:((int)$emp['assigned_branch_id']);$from=self::date($from?:date('Y-m-01'));$to=self::date($to?:Db::today());if($from>$to)throw new DomainException('Invalid visit date range.','date_range_invalid',422);
        if($employee===$a->employeeId){Guard::cap($a,Capabilities::FIELD_SELF);}else{Guard::branch($a,$branch,Capabilities::ATT_MANAGE);}
        $db=Db::wpdb();return(array)$db->get_results($db->prepare("SELECT * FROM ".Db::table('field_visits')." WHERE company_id=%d AND employee_id=%d AND branch_id=%d AND DATE(started_at) BETWEEN %s AND %s ORDER BY started_at DESC,id DESC LIMIT 300",$a->companyId,$employee,$branch,$from,$to),ARRAY_A);
    }
    public static function holidays(Actor $a,?int $branch,string $from,string $to):array {
        Guard::any($a,[Capabilities::LEAVE_SELF,Capabilities::ATT_SELF,Capabilities::LEAVE_MANAGE,Capabilities::ATT_MANAGE]);$from=self::date($from?:date('Y-01-01'));$to=self::date($to?:date('Y-12-31'));if($from>$to)throw new DomainException('Invalid holiday date range.','date_range_invalid',422);if($branch&&!$a->hasBranch($branch))throw new DomainException('Branch is outside effective authority.','branch_forbidden',403);
        $db=Db::wpdb();if($branch)return(array)$db->get_results($db->prepare("SELECT * FROM ".Db::table('holidays')." WHERE company_id=%d AND active=1 AND holiday_date BETWEEN %s AND %s AND (branch_id IS NULL OR branch_id=%d) ORDER BY holiday_date,id",$a->companyId,$from,$to,$branch),ARRAY_A);
        return(array)$db->get_results($db->prepare("SELECT * FROM ".Db::table('holidays')." WHERE company_id=%d AND active=1 AND holiday_date BETWEEN %s AND %s AND branch_id IS NULL ORDER BY holiday_date,id",$a->companyId,$from,$to),ARRAY_A);
    }
    public static function leaveBalance(Actor $a,int $year):array {
        Guard::cap($a,Capabilities::LEAVE_SELF);$year=$year?:((int)date('Y'));if($year<2020||$year>2100)throw new DomainException('Invalid leave balance year.','leave_year_invalid',422);$policy=self::setting($a->companyId,'leave_balance_policy_json');$ent=$policy?json_decode($policy,true):null;if(!is_array($ent)||!$ent)return['configured'=>false,'year'=>$year,'balances'=>[],'message'=>'Leave entitlement policy is not configured.'];
        $db=Db::wpdb();$rows=(array)$db->get_results($db->prepare("SELECT leave_type,SUM(DATEDIFF(LEAST(date_to,%s),GREATEST(date_from,%s))+1) used_days FROM ".Db::table('leave_requests')." WHERE company_id=%d AND employee_id=%d AND status='approved' AND date_to>=%s AND date_from<=%s GROUP BY leave_type",$year.'-12-31',$year.'-01-01',$a->companyId,$a->employeeId,$year.'-01-01',$year.'-12-31'),ARRAY_A);$used=[];foreach($rows as$r)$used[(string)$r['leave_type']]=(int)$r['used_days'];$out=[];foreach($ent as$type=>$days){$total=max(0,(int)$days);$u=(int)($used[(string)$type]??0);$out[]=['leave_type'=>(string)$type,'entitled'=>$total,'used'=>$u,'balance'=>max(0,$total-$u)];}return['configured'=>true,'year'=>$year,'balances'=>$out];
    }
    public static function setLeavePolicy(Actor $a,array $entitlements):array {
        Guard::cap($a,Capabilities::ACCESS_MANAGE);if(!$entitlements)throw new DomainException('At least one leave entitlement is required.','leave_policy_required',422);$clean=[];foreach($entitlements as$type=>$days){$key=strtoupper(sanitize_key((string)$type));$n=(int)$days;if($key===''||$n<0||$n>365)throw new DomainException('Invalid leave entitlement.','leave_policy_invalid',422);$clean[$key]=$n;}self::setSetting($a,'leave_balance_policy_json',wp_json_encode($clean));Audit::add($a,'leave.policy.update','setting','leave_balance_policy_json',[]);return['configured'=>true,'entitlements'=>$clean];
    }
    public static function documents(Actor $a,int $employee):array {self::documentScope($a,$employee,false);$db=Db::wpdb();return(array)$db->get_results($db->prepare("SELECT id,employee_id,document_type,title,original_name,mime_type,file_size,sha256,status,uploaded_by,created_at FROM ".Db::table('employee_documents')." WHERE company_id=%d AND employee_id=%d AND status='active' ORDER BY created_at DESC,id DESC",$a->companyId,$employee),ARRAY_A);}
    public static function uploadDocument(Actor $a,int $employee,string $type,string $title,string $filename,string $mime,string $base64):array {
        self::documentScope($a,$employee,true);$type=sanitize_key($type);$title=trim($title);$filename=sanitize_file_name($filename);$allowed=['application/pdf'=>'pdf','image/jpeg'=>'jpg','image/png'=>'png','image/webp'=>'webp'];if($type===''||$title===''||$filename===''||!isset($allowed[$mime]))throw new DomainException('Invalid employee document metadata.','document_invalid',422);$raw=base64_decode($base64,true);if($raw===false||$raw==='')throw new DomainException('Document content is invalid.','document_invalid',422);$size=strlen($raw);if($size>5*1024*1024)throw new DomainException('Document exceeds 5 MB.','document_too_large',413);
        $dir=self::documentDir();$key=str_replace('-','',wp_generate_uuid4()).'.'.$allowed[$mime];$path=$dir.'/'.$key;if(file_put_contents($path,$raw,LOCK_EX)!==$size)throw new DomainException('Document storage failed.','document_store_failed',500);$hash=hash('sha256',$raw);$db=Db::wpdb();try{Db::mustInsert($db,Db::table('employee_documents'),['company_id'=>$a->companyId,'employee_id'=>$employee,'document_type'=>$type,'title'=>$title,'original_name'=>$filename,'mime_type'=>$mime,'file_size'=>$size,'sha256'=>$hash,'storage_key'=>$key,'status'=>'active','uploaded_by'=>$a->employeeId,'created_at'=>Db::now()]);}catch(\Throwable $e){@unlink($path);throw $e;}$id=(int)$db->insert_id;Audit::add($a,'employee.document.upload','employee_document',$id,['employee_id'=>$employee]);return['id'=>$id,'employee_id'=>$employee,'title'=>$title,'mime_type'=>$mime,'file_size'=>$size,'sha256'=>$hash];
    }
    public static function documentContent(Actor $a,int $id):array {$db=Db::wpdb();$r=$db->get_row($db->prepare("SELECT * FROM ".Db::table('employee_documents')." WHERE id=%d AND company_id=%d AND status='active'",$id,$a->companyId),ARRAY_A);if(!$r)throw new DomainException('Employee document not found.','document_not_found',404);self::documentScope($a,(int)$r['employee_id'],false);$path=self::documentDir().'/'.basename((string)$r['storage_key']);if(!is_file($path))throw new DomainException('Document file is unavailable.','document_file_missing',404);$raw=file_get_contents($path);if($raw===false||hash('sha256',$raw)!==(string)$r['sha256'])throw new DomainException('Document integrity check failed.','document_integrity_failed',500);return['id'=>$id,'filename'=>$r['original_name'],'mime_type'=>$r['mime_type'],'sha256'=>$r['sha256'],'content_base64'=>base64_encode($raw)];}
    public static function notificationRead(Actor $a,int $id):array {Guard::cap($a,Capabilities::COMM_VIEW);$db=Db::wpdb();$r=$db->get_row($db->prepare("SELECT id,read_at FROM ".Db::table('notifications')." WHERE id=%d AND company_id=%d AND employee_id=%d",$id,$a->companyId,$a->employeeId),ARRAY_A);if(!$r)throw new DomainException('Notification not found.','notification_not_found',404);if(!$r['read_at'])$db->update(Db::table('notifications'),['read_at'=>Db::now()],['id'=>$id]);return['id'=>$id,'read'=>true];}
    public static function notificationReadAll(Actor $a):array {Guard::cap($a,Capabilities::COMM_VIEW);$db=Db::wpdb();$n=$db->query($db->prepare("UPDATE ".Db::table('notifications')." SET read_at=%s WHERE company_id=%d AND employee_id=%d AND read_at IS NULL",Db::now(),$a->companyId,$a->employeeId));return['updated'=>max(0,(int)$n)];}
    public static function acknowledgeAnnouncement(Actor $a,int $id):array {Guard::cap($a,Capabilities::COMM_VIEW);$db=Db::wpdb();$ids=$a->branchIds?implode(',',array_map('intval',$a->branchIds)):'0';$ok=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('announcements')." WHERE id=%d AND company_id=%d AND status='published' AND (branch_id IS NULL OR branch_id IN ({$ids}))",$id,$a->companyId));if(!$ok)throw new DomainException('Announcement not available.','announcement_not_found',404);$sql=$db->prepare("INSERT INTO ".Db::table('announcement_acknowledgements')."(company_id,announcement_id,employee_id,acknowledged_at) VALUES(%d,%d,%d,%s) ON DUPLICATE KEY UPDATE acknowledged_at=VALUES(acknowledged_at)",$a->companyId,$id,$a->employeeId,Db::now());if($db->query($sql)===false)throw new DomainException('Announcement acknowledgement failed.','announcement_ack_failed',500);return['id'=>$id,'acknowledged'=>true,'acknowledged_at'=>Db::now()];}
    public static function pushRegister(Actor $a,string $token,string $platform,string $device):array {Guard::any($a,[Capabilities::COMM_VIEW,Capabilities::ACCESS]);$token=trim($token);$platform=sanitize_key($platform);if(strlen($token)<20||strlen($token)>512||!in_array($platform,['android','ios','web'],true))throw new DomainException('Invalid push token.','push_token_invalid',422);$hash=hash('sha256',$token);$db=Db::wpdb();$sql=$db->prepare("INSERT INTO ".Db::table('push_tokens')."(company_id,employee_id,token_hash,token,platform,device_name,active,registered_at,last_seen_at) VALUES(%d,%d,%s,%s,%s,%s,1,%s,%s) ON DUPLICATE KEY UPDATE company_id=VALUES(company_id),employee_id=VALUES(employee_id),token=VALUES(token),platform=VALUES(platform),device_name=VALUES(device_name),active=1,last_seen_at=VALUES(last_seen_at),revoked_at=NULL",$a->companyId,$a->employeeId,$hash,$token,$platform,trim($device)?:null,Db::now(),Db::now());if($db->query($sql)===false)throw new DomainException('Push token registration failed.','push_token_store_failed',500);return['registered'=>true,'configured'=>self::pushConfigured()];}
    public static function pushRevoke(Actor $a,string $token):array {Guard::any($a,[Capabilities::COMM_VIEW,Capabilities::ACCESS]);$hash=hash('sha256',trim($token));$db=Db::wpdb();$db->update(Db::table('push_tokens'),['active'=>0,'revoked_at'=>Db::now()],['company_id'=>$a->companyId,'employee_id'=>$a->employeeId,'token_hash'=>$hash]);return['revoked'=>true];}
    public static function pushStatus(Actor $a):array {Guard::any($a,[Capabilities::COMM_VIEW,Capabilities::ACCESS]);$db=Db::wpdb();$count=(int)$db->get_var($db->prepare("SELECT COUNT(*) FROM ".Db::table('push_tokens')." WHERE company_id=%d AND employee_id=%d AND active=1",$a->companyId,$a->employeeId));return['registered_tokens'=>$count,'delivery_configured'=>self::pushConfigured(),'configuration'=>'Firebase credentials must be provided as EH7_FCM_PROJECT_ID, EH7_FCM_CLIENT_EMAIL and EH7_FCM_PRIVATE_KEY constants.'];}
    public static function tasks(Actor $a,int $branch):array {Guard::branch($a,$branch,Capabilities::COMM_MANAGE);$db=Db::wpdb();return(array)$db->get_results($db->prepare("SELECT t.*,d.description,d.priority,d.created_by,d.assigned_by,d.updated_at,e.employee_code,e.full_name assigned_employee_name FROM ".Db::table('tasks')." t LEFT JOIN ".Db::table('task_details')." d ON d.task_id=t.id LEFT JOIN ".Db::table('employees')." e ON e.id=t.assigned_employee_id WHERE t.company_id=%d AND t.branch_id=%d ORDER BY (t.status='open') DESC,t.due_at IS NULL,t.due_at,t.id DESC LIMIT 300",$a->companyId,$branch),ARRAY_A);}
    public static function createTask(Actor $a,int $branch,int $employee,string $type,string $title,string $description,string $priority,?string $dueAt,?string $entityType,?int $entityId):array {Guard::branch($a,$branch,Capabilities::COMM_MANAGE);$emp=self::employee($a,$employee);if((int)$emp['assigned_branch_id']!==$branch)throw new DomainException('Task employee is not assigned to selected branch.','task_employee_branch_mismatch',422);$title=trim($title);$priority=sanitize_key($priority?:'normal');if($title===''||!in_array($priority,['low','normal','high','urgent'],true))throw new DomainException('Invalid task.','task_invalid',422);return Transaction::run(function()use($a,$branch,$employee,$type,$title,$description,$priority,$dueAt,$entityType,$entityId){$db=Db::wpdb();Db::mustInsert($db,Db::table('tasks'),['company_id'=>$a->companyId,'branch_id'=>$branch,'assigned_employee_id'=>$employee,'type'=>sanitize_key($type?:'general'),'title'=>$title,'entity_type'=>$entityType?sanitize_key($entityType):null,'entity_id'=>$entityId,'status'=>'open','due_at'=>$dueAt?:null,'created_at'=>Db::now()]);$id=(int)$db->insert_id;Db::mustInsert($db,Db::table('task_details'),['task_id'=>$id,'company_id'=>$a->companyId,'description'=>trim($description)?:null,'priority'=>$priority,'created_by'=>$a->employeeId,'assigned_by'=>$a->employeeId,'updated_at'=>Db::now()]);Audit::add($a,'task.create','task',$id,['branch_id'=>$branch,'assigned_employee_id'=>$employee]);return['id'=>$id,'status'=>'open'];});}
    public static function reassignTask(Actor $a,int $id,int $employee):array {Guard::cap($a,Capabilities::COMM_MANAGE);return Transaction::run(function()use($a,$id,$employee){$db=Db::wpdb();$t=Db::table('tasks');$r=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE id=%d AND company_id=%d FOR UPDATE",$id,$a->companyId),ARRAY_A);if(!$r)throw new DomainException('Task not found.','task_not_found',404);$branch=(int)($r['branch_id']??0);if(!$branch)throw new DomainException('Task branch is required for reassignment.','task_branch_missing',409);Guard::branch($a,$branch,Capabilities::COMM_MANAGE);$emp=self::employee($a,$employee);if((int)$emp['assigned_branch_id']!==$branch)throw new DomainException('Task employee is not assigned to selected branch.','task_employee_branch_mismatch',422);if($r['status']!=='open')throw new DomainException('Only open task can be reassigned.','task_not_open',409);$db->update($t,['assigned_employee_id'=>$employee],['id'=>$id]);$sql=$db->prepare("INSERT INTO ".Db::table('task_details')."(task_id,company_id,description,priority,created_by,assigned_by,updated_at) VALUES(%d,%d,NULL,'normal',%d,%d,%s) ON DUPLICATE KEY UPDATE assigned_by=VALUES(assigned_by),updated_at=VALUES(updated_at)",$id,$a->companyId,$a->employeeId,$a->employeeId,Db::now());$db->query($sql);Audit::add($a,'task.reassign','task',$id,['branch_id'=>$branch,'assigned_employee_id'=>$employee]);return['id'=>$id,'assigned_employee_id'=>$employee,'status'=>'open'];});}
    public static function appVersionPolicy(?string $clientVersion=null):array {$min=(string)get_option('eh7_min_app_version','');$latest=(string)get_option('eh7_latest_app_version','');$url=(string)get_option('eh7_app_update_url','');$force=(bool)get_option('eh7_force_app_update',false);$configured=$min!==''||$latest!=='';$required=$clientVersion&&$min!==''?version_compare($clientVersion,$min,'<'):false;$available=$clientVersion&&$latest!==''?version_compare($clientVersion,$latest,'<'):false;return['configured'=>$configured,'minimum_version'=>$min?:null,'latest_version'=>$latest?:null,'update_url'=>$url?:null,'force_update'=>$force,'client_version'=>$clientVersion?:null,'update_required'=>$required,'update_available'=>$available];}
    public static function setAppVersionPolicy(Actor $a,string $min,string $latest,string $url,bool $force):array {Guard::cap($a,Capabilities::ACCESS_MANAGE);$min=trim($min);$latest=trim($latest);if(($min!==''&&!preg_match('/^\d+\.\d+\.\d+([+-][0-9A-Za-z.-]+)?$/',$min))||($latest!==''&&!preg_match('/^\d+\.\d+\.\d+([+-][0-9A-Za-z.-]+)?$/',$latest)))throw new DomainException('App versions must use semantic version format.','app_version_invalid',422);if($min&&$latest&&version_compare($min,$latest,'>'))throw new DomainException('Minimum version cannot exceed latest version.','app_version_invalid',422);update_option('eh7_min_app_version',$min,false);update_option('eh7_latest_app_version',$latest,false);update_option('eh7_app_update_url',esc_url_raw($url),false);update_option('eh7_force_app_update',$force?1:0,false);Audit::add($a,'app.version_policy.update','setting','app_version_policy',[]);return self::appVersionPolicy(null);}
    private static function coordinates(float $lat,float $lng,?float $accuracy):void {if($lat<-90||$lat>90||$lng<-180||$lng>180)throw new DomainException('Invalid GPS coordinates.','gps_invalid',422);if($accuracy!==null&&($accuracy<0||$accuracy>10000))throw new DomainException('Invalid GPS accuracy.','gps_accuracy_invalid',422);}
    private static function employee(Actor $a,int $id):array {$db=Db::wpdb();$r=$db->get_row($db->prepare("SELECT id,assigned_branch_id,status FROM ".Db::table('employees')." WHERE id=%d AND company_id=%d",$id,$a->companyId),ARRAY_A);if(!$r||$r['status']!=='active')throw new DomainException('Employee not found.','employee_not_found',404);return$r;}
    private static function documentScope(Actor $a,int $employee,bool $write):void {if($employee===$a->employeeId){Guard::cap($a,Capabilities::ACCESS);return;}$emp=self::employee($a,$employee);Guard::branch($a,(int)$emp['assigned_branch_id'],$write?Capabilities::EMP_MANAGE:Capabilities::EMP_VIEW);}
    private static function documentDir():string {$dir=WP_CONTENT_DIR.'/eh7-private-documents';if(!is_dir($dir)&&!wp_mkdir_p($dir))throw new DomainException('Private document directory unavailable.','document_store_failed',500);if(!is_file($dir.'/index.php'))@file_put_contents($dir.'/index.php',"<?php exit;\n");if(!is_file($dir.'/.htaccess'))@file_put_contents($dir.'/.htaccess',"Require all denied\nDeny from all\n");return$dir;}
    private static function setting(int $company,string $key):?string {$db=Db::wpdb();$v=$db->get_var($db->prepare("SELECT setting_value FROM ".Db::table('settings')." WHERE company_id=%d AND setting_key=%s",$company,$key));return$v===null?null:(string)$v;}
    private static function setSetting(Actor $a,string $key,string $value):void {$db=Db::wpdb();$sql=$db->prepare("INSERT INTO ".Db::table('settings')."(company_id,setting_key,setting_value,updated_by,updated_at) VALUES(%d,%s,%s,%d,%s) ON DUPLICATE KEY UPDATE setting_value=VALUES(setting_value),updated_by=VALUES(updated_by),updated_at=VALUES(updated_at)",$a->companyId,$key,$value,$a->employeeId,Db::now());if($db->query($sql)===false)throw new DomainException('Setting update failed.','setting_store_failed',500);}
    private static function date(string $value):string {$value=trim($value);$d=\DateTimeImmutable::createFromFormat('!Y-m-d',$value);$e=\DateTimeImmutable::getLastErrors();if(!$d||($e!==false&&(($e['warning_count']??0)||($e['error_count']??0)))||$d->format('Y-m-d')!==$value)throw new DomainException('Invalid date.','date_invalid',422);return$value;}
    private static function pushConfigured():bool{return defined('EH7_FCM_PROJECT_ID')&&defined('EH7_FCM_CLIENT_EMAIL')&&defined('EH7_FCM_PRIVATE_KEY')&&EH7_FCM_PROJECT_ID&&EH7_FCM_CLIENT_EMAIL&&EH7_FCM_PRIVATE_KEY;}
}
'''
write(SRC/'Recovery'/'RecoveryService.php', recovery_service)

# Plugin version + additive recovery schema boot.
plugin = BACKEND/'excel-herbal-erp-v7.php'
s = read(plugin)
s = re.sub(r'\* Version: [0-9.]+', '* Version: 7.1.14', s, count=1)
s = re.sub(r"define\('EH7_VERSION','[0-9.]+'\)", "define('EH7_VERSION','7.1.14')", s, count=1)
write(plugin, s)

plugin_core = SRC/'Core'/'Plugin.php'
s = read(plugin_core)
if 'RecoverySchema' not in s:
    s = s.replace('use ExcelHerbal\\ERP7\\Http\\Api;', 'use ExcelHerbal\\ERP7\\Http\\Api;use ExcelHerbal\\ERP7\\Recovery\\RecoverySchema;')
    s = s.replace('public static function boot():void{MobileAuth::boot();', "public static function boot():void{RecoverySchema::installIfNeeded();MobileAuth::boot();")
write(plugin_core, s)

# Routes: additive and backward-compatible.
routes = SRC/'Http'/'RouteRegistry.php'
s = read(routes)
route_block = """ ['POST','/workforce/gps/points','recovery.gps_point',true],['GET','/workforce/gps/route','recovery.gps_route',true],['GET','/workforce/field-visits/history','recovery.visit_history',true],['GET','/workforce/holidays','recovery.holidays',true],['GET','/workforce/leave/balance','recovery.leave_balance',true],['POST','/workforce/leave/balance-policy','recovery.leave_policy',true],\n ['GET','/organization/employees/(?P<id>\\\\d+)/documents','recovery.documents',true],['POST','/organization/employees/(?P<id>\\\\d+)/documents','recovery.document_upload',true],['GET','/organization/documents/(?P<id>\\\\d+)','recovery.document_content',true],\n ['POST','/communication/notifications/(?P<id>\\\\d+)/read','recovery.notification_read',true],['POST','/communication/notifications/read-all','recovery.notification_read_all',true],['POST','/communication/announcements/(?P<id>\\\\d+)/acknowledge','recovery.announcement_ack',true],['GET','/communication/tasks','recovery.tasks',true],['POST','/communication/tasks','recovery.task_create',true],['POST','/communication/tasks/(?P<id>\\\\d+)/reassign','recovery.task_reassign',true],['POST','/communication/push-tokens','recovery.push_register',true],['POST','/communication/push-tokens/revoke','recovery.push_revoke',true],['GET','/communication/push-status','recovery.push_status',true],\n ['GET','/app/version-policy','recovery.app_version',false],['POST','/administration/app/version-policy','recovery.app_version_set',true],\n"""
if "recovery.gps_point" not in s:
    marker=" ['GET','/communication/summary','comm.summary',true]"
    if marker not in s: raise SystemExit('RouteRegistry communication marker not found')
    s=s.replace(marker,route_block+marker,1)
write(routes,s)

# API import + dispatch cases.
api=SRC/'Http'/'Api.php';s=read(api)
if 'RecoveryService' not in s:
    marker='use ExcelHerbal\\ERP7\\Setup\\SetupService;'
    if marker not in s: raise SystemExit('Api SetupService import marker not found')
    s=s.replace(marker,marker+'use ExcelHerbal\\ERP7\\Recovery\\RecoveryService;',1)
    dispatch="""  'recovery.gps_point'=>RecoveryService::gpsPoint($a,(int)$r->get_param('branch_id'),(float)$r->get_param('lat'),(float)$r->get_param('lng'),self::nf($r->get_param('accuracy')),(string)$r->get_param('source')),'recovery.gps_route'=>RecoveryService::gpsRoute($a,(int)$r->get_param('employee_id'),(string)$r->get_param('date'),self::ni($r->get_param('branch_id'))),'recovery.visit_history'=>RecoveryService::visitHistory($a,(int)$r->get_param('employee_id'),self::ni($r->get_param('branch_id')),(string)$r->get_param('from'),(string)$r->get_param('to')),'recovery.holidays'=>RecoveryService::holidays($a,self::ni($r->get_param('branch_id')),(string)$r->get_param('from'),(string)$r->get_param('to')),'recovery.leave_balance'=>RecoveryService::leaveBalance($a,(int)$r->get_param('year')),'recovery.leave_policy'=>RecoveryService::setLeavePolicy($a,(array)$r->get_param('entitlements')),\n  'recovery.documents'=>RecoveryService::documents($a,(int)$r['id']),'recovery.document_upload'=>RecoveryService::uploadDocument($a,(int)$r['id'],(string)$r->get_param('document_type'),(string)$r->get_param('title'),(string)$r->get_param('filename'),(string)$r->get_param('mime_type'),(string)$r->get_param('content_base64')),'recovery.document_content'=>RecoveryService::documentContent($a,(int)$r['id']),\n  'recovery.notification_read'=>RecoveryService::notificationRead($a,(int)$r['id']),'recovery.notification_read_all'=>RecoveryService::notificationReadAll($a),'recovery.announcement_ack'=>RecoveryService::acknowledgeAnnouncement($a,(int)$r['id']),'recovery.tasks'=>RecoveryService::tasks($a,(int)$r->get_param('branch_id')),'recovery.task_create'=>RecoveryService::createTask($a,(int)$r->get_param('branch_id'),(int)$r->get_param('employee_id'),(string)$r->get_param('type'),(string)$r->get_param('title'),(string)$r->get_param('description'),(string)$r->get_param('priority'),$r->get_param('due_at')!==null?(string)$r->get_param('due_at'):null,$r->get_param('entity_type')!==null?(string)$r->get_param('entity_type'):null,self::ni($r->get_param('entity_id'))),'recovery.task_reassign'=>RecoveryService::reassignTask($a,(int)$r['id'],(int)$r->get_param('employee_id')),'recovery.push_register'=>RecoveryService::pushRegister($a,(string)$r->get_param('token'),(string)$r->get_param('platform'),(string)$r->get_param('device_name')),'recovery.push_revoke'=>RecoveryService::pushRevoke($a,(string)$r->get_param('token')),'recovery.push_status'=>RecoveryService::pushStatus($a),'recovery.app_version'=>RecoveryService::appVersionPolicy($r->get_param('version')!==null?(string)$r->get_param('version'):null),'recovery.app_version_set'=>RecoveryService::setAppVersionPolicy($a,(string)$r->get_param('minimum_version'),(string)$r->get_param('latest_version'),(string)$r->get_param('update_url'),(bool)$r->get_param('force_update')),\n"""
    marker="  'comm.summary'=>CommunicationService::summary($a)"
    if marker not in s: raise SystemExit('Api communication dispatch marker not found')
    s=s.replace(marker,dispatch+marker,1)
write(api,s)

# Server-side whole-PCS validation at business/service boundaries.
def add_import(path, marker, addition):
    s=read(path)
    if addition.split('use ')[-1].split(';')[0] in s:return
    if marker not in s:raise SystemExit(f'import marker missing: {path}')
    write(path,s.replace(marker,marker+addition,1))

stock=SRC/'Inventory'/'StockService.php'
s=read(stock)
if 'QuantityRules' not in s:
    s=s.replace('use ExcelHerbal\\ERP7\\Domain\\DomainException;', 'use ExcelHerbal\\ERP7\\Domain\\DomainException;\nuse ExcelHerbal\\ERP7\\Domain\\QuantityRules;')
    marker="public static function move(Actor $a,int $branch,int $product,?int $batch,?int $custodian,string $dir,float $qty,float $cost,string $source,int $sourceId):void{"
    if marker not in s:raise SystemExit('StockService move marker missing')
    s=s.replace(marker,marker+"$qty=(float)QuantityRules::positive($qty,'stock quantity');",1)
write(stock,s)

for rel, import_marker, method_repls in [
    ('DailyOrder/DailyOrderService.php','use ExcelHerbal\\ERP7\\Domain\\DomainException;',[
        ("public static function create(Actor $a,int $branch,int $employee,string $date,array $lines):array{","public static function create(Actor $a,int $branch,int $employee,string $date,array $lines):array{QuantityRules::positiveLines($lines);"),
        ("public static function additional(Actor $a,int $id,array $lines):array{","public static function additional(Actor $a,int $id,array $lines):array{QuantityRules::positiveLines($lines);"),
        ("public static function issue(Actor $a,int $request,array $alloc):array{","public static function issue(Actor $a,int $request,array $alloc):array{QuantityRules::positiveLines($alloc);"),
        ("public static function eveningSave(Actor $a,int $id,array $lines,array $wholesale,string $priceReason):array{","public static function eveningSave(Actor $a,int $id,array $lines,array $wholesale,string $priceReason):array{QuantityRules::nonNegativeLines($lines,['return_quantity','wholesale_quantity']);"),
    ]),
    ('Sales/SalesService.php','use ExcelHerbal\\ERP7\\Domain\\DomainException;',[
        ("public static function counter(Actor $a,int $branch,?int $customer,float $paid,?int $paymentAccount,array $lines):array{","public static function counter(Actor $a,int $branch,?int $customer,float $paid,?int $paymentAccount,array $lines):array{QuantityRules::positiveLines($lines);"),
    ]),
    ('Purchase/PurchaseService.php','use ExcelHerbal\\ERP7\\Domain\\DomainException;',[
        ("public static function bill(Actor $a,int $branch,int $supplier,string $billNo,string $date,array $lines):array{","public static function bill(Actor $a,int $branch,int $supplier,string $billNo,string $date,array $lines):array{QuantityRules::positiveLines($lines);"),
    ]),
    ('Inventory/InventoryService.php','use ExcelHerbal\\ERP7\\Domain\\DomainException;',[
        ("public static function createTransfer(Actor $a,int $source,int $dest,array $lines,string $notes):array{","public static function createTransfer(Actor $a,int $source,int $dest,array $lines,string $notes):array{QuantityRules::positiveLines($lines);"),
        ("public static function transferAction(Actor $a,int $id,string $action,array $payload=[]):array{","public static function transferAction(Actor $a,int $id,string $action,array $payload=[]):array{if($action==='receive')QuantityRules::nonNegativeLines((array)($payload['lines']??[]),['received_quantity']);"),
        ("public static function adjustment(Actor $a,int $branch,string $reason,array $lines):array{","public static function adjustment(Actor $a,int $branch,string $reason,array $lines):array{QuantityRules::signedNonZeroLines($lines);"),
    ]),
]:
    path=SRC/rel;s=read(path)
    if 'QuantityRules' not in s:
        if import_marker not in s:raise SystemExit(f'{rel}: DomainException import marker missing')
        s=s.replace(import_marker,import_marker+'use ExcelHerbal\\ERP7\\Domain\\QuantityRules;',1)
    for old,new in method_repls:
        if new in s:continue
        if old not in s:raise SystemExit(f'{rel}: method marker missing: {old[:60]}')
        s=s.replace(old,new,1)
    write(path,s)

# Recovery contracts.
test = ROOT/'tests'/'recovery_contracts.py'
write(test, r'''from pathlib import Path
root=Path(__file__).resolve().parents[1]
backend=root/'backend'/'excel-herbal-erp-v7'
src=backend/'src'
route=(src/'Http'/'RouteRegistry.php').read_text()
api=(src/'Http'/'Api.php').read_text()
plugin=(backend/'excel-herbal-erp-v7.php').read_text()
recovery=(src/'Recovery'/'RecoveryService.php').read_text()
schema=(src/'Recovery'/'RecoverySchema.php').read_text()
qty=(src/'Domain'/'QuantityRules.php').read_text()
required_routes=['/workforce/gps/points','/workforce/gps/route','/workforce/field-visits/history','/workforce/holidays','/workforce/leave/balance','/organization/employees/(?P<id>\\d+)/documents','/communication/notifications/read-all','/communication/announcements/(?P<id>\\d+)/acknowledge','/communication/tasks','/communication/push-tokens','/app/version-policy','/administration/app/version-policy']
for x in required_routes: assert x in route,x
for h in ['recovery.gps_point','recovery.documents','recovery.notification_read_all','recovery.task_create','recovery.push_register','recovery.app_version_set']: assert h in api,h
for table in ['gps_points','employee_documents','announcement_acknowledgements','push_tokens','task_details']: assert "'"+table+"'" in schema,table
assert '7.1.14' in plugin
assert 'whole_pcs_required' in qty
for rel in ['Inventory/StockService.php','DailyOrder/DailyOrderService.php','Sales/SalesService.php','Purchase/PurchaseService.php','Inventory/InventoryService.php']:
    assert 'QuantityRules' in (src/rel).read_text(),rel
assert 'gps_ping_too_soon' in recovery
assert "WP_CONTENT_DIR.'/eh7-private-documents'" in recovery
assert 'version_compare' in recovery
print('RECOVERY_CONTRACTS_PASS')
''')

report=ROOT/'docs'/'V7.1.14-RECOVERY-IMPLEMENTATION.md'
write(report, '''# Excel Herbal ERP v7.1.14 Backend Recovery\n\nAdditive recovery implementation. Existing business tables and transactions are not deleted.\n\nAdded: periodic GPS point/history backend, Field Visit history, Holidays/Leave balance policy API, private Employee Documents, notification read lifecycle, announcement acknowledgement, push-token registry, manager task create/reassign, minimum app-version policy, and server-side Whole-PCS validation.\n\nPush delivery requires Firebase credentials in wp-config constants; token registry/status are implemented without storing service-account secrets in ERP tables.\n''')
print('V714_BACKEND_RECOVERY_PATCH_APPLIED')
