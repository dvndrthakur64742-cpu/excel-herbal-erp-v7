<?php
namespace ExcelHerbal\ERP7\Organization;

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Recovery\RecoveryService;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Audit;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\Guard;

final class DocumentService {
    private const MAX_BYTES=10485760;
    private const EXTENSIONS=['pdf','jpg','jpeg','png','webp'];
    public static function upload(Actor $a,int $employeeId,array $data):array {
        self::employeeManage($a,$employeeId);$type=trim((string)($data['document_type']??''));$title=trim((string)($data['title']??''));if($type===''||$title===''||strlen($type)>60||strlen($title)>190)throw new DomainException('document_type and title are required.','employee_document_invalid',422);
        return \ExcelHerbal\ERP7\Database\Transaction::run(function()use($a,$employeeId,$type,$title){
            $file=DocumentVault::storeUpload();$db=Db::wpdb();Db::mustInsert($db,Db::table('employee_documents'),['company_id'=>$a->companyId,'employee_id'=>$employeeId,'attachment_id'=>0,'private_file_id'=>$file,'document_type'=>$type,'title'=>$title,'status'=>'active','uploaded_by'=>$a->employeeId,'created_at'=>Db::now()]);$id=(int)$db->insert_id;
            Audit::add($a,'employee_document.upload','employee_document',$id,['employee_id'=>$employeeId]);return ['id'=>$id,'attachment_id'=>0,'status'=>'active','url'=>DocumentVault::url('employee',$employeeId,$id),'requires_auth'=>true];
        });
    }
    public static function deactivate(Actor $a,int $employeeId,int $documentId):array {
        self::employeeManage($a,$employeeId);return \ExcelHerbal\ERP7\Database\Transaction::run(function()use($a,$employeeId,$documentId){$db=Db::wpdb();$t=Db::table('employee_documents');$r=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE id=%d AND employee_id=%d AND company_id=%d FOR UPDATE",$documentId,$employeeId,$a->companyId),ARRAY_A);if(!$r)throw new DomainException('Employee document not found.','employee_document_not_found',404);if($r['status']==='inactive')return ['id'=>$documentId,'status'=>'inactive','unchanged'=>true];Db::mustUpdate($db,$t,['status'=>'inactive','updated_at'=>Db::now()],['id'=>$documentId]);Audit::add($a,'employee_document.deactivate','employee_document',$documentId,['employee_id'=>$employeeId]);return ['id'=>$documentId,'status'=>'inactive','unchanged'=>false];});
    }
    private static function employeeManage(Actor $a,int $employeeId):void {$db=Db::wpdb();$e=$db->get_row($db->prepare("SELECT assigned_branch_id FROM ".Db::table('employees')." WHERE id=%d AND company_id=%d",$employeeId,$a->companyId),ARRAY_A);if(!$e)throw new DomainException('Employee not found.','employee_not_found',404);Guard::branch($a,(int)$e['assigned_branch_id'],Capabilities::EMP_MANAGE);}
}
