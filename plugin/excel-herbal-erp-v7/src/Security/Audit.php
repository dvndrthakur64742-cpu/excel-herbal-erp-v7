<?php
namespace ExcelHerbal\ERP7\Security;use ExcelHerbal\ERP7\Database\Db;
final class Audit{public static function add(Actor $a,string $action,string $type,int|string $id,array $context=[]):void{Db::mustInsert(Db::wpdb(),Db::table('audit_log'),['company_id'=>$a->companyId,'branch_id'=>$context['branch_id']??null,'employee_id'=>$a->employeeId,'wp_user_id'=>$a->userId,'action'=>$action,'entity_type'=>$type,'entity_id'=>(string)$id,'context_json'=>$context?wp_json_encode($context):null,'created_at'=>Db::now()]);}}
