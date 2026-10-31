<?php
namespace ExcelHerbal\ERP7\Administration;

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Organization\OrganizationEmployeeService;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\DesignationDefaults;
use ExcelHerbal\ERP7\Setup\SetupService;

final class FreshUatBootstrap {
    public static function status():array {
        $environment=self::environment();
        if($environment!=='staging')return ['required'=>false,'seeded'=>false,'environment'=>$environment];
        $source=defined('EH7_SOURCE_HEAD')?(string)EH7_SOURCE_HEAD:'source-tree';
        $marker=(string)get_option('eh7_uat_seed_source_head','');
        $seededAt=(string)get_option('eh7_uat_seeded_at','');
        $mode=(string)get_option('eh7_uat_seed_mode','');
        $adminId=(int)get_option('eh7_uat_admin_employee_id',0);
        $limitedId=(int)get_option('eh7_uat_limited_employee_id',0);
        $sourceMatch=$source!==''&&$marker!==''&&hash_equals(strtolower($source),strtolower($marker));
        $db=Db::wpdb();
        $adminPresent=$adminId>0&&(int)$db->get_var($db->prepare('SELECT COUNT(*) FROM '.Db::table('employees').' WHERE id=%d AND status=%s',$adminId,'active'))===1;
        $limitedPresent=$limitedId>0&&(int)$db->get_var($db->prepare('SELECT COUNT(*) FROM '.Db::table('employees').' WHERE id=%d AND status=%s',$limitedId,'active'))===1;
        return [
            'required'=>true,
            'seeded'=>$sourceMatch&&$seededAt!==''&&$mode==='fresh_synthetic'&&$adminPresent&&$limitedPresent,
            'environment'=>$environment,
            'source_head_match'=>$sourceMatch,
            'synthetic_only'=>$mode==='fresh_synthetic',
            'admin_employee_present'=>$adminPresent,
            'limited_employee_present'=>$limitedPresent,
            'seeded_at'=>$seededAt?:null,
        ];
    }

    public static function assertSafeTarget():void {
        if(self::environment()!=='staging')throw new \RuntimeException('Fresh UAT bootstrap refuses non-staging environments.');
        $host=strtolower((string)parse_url((string)home_url('/'),PHP_URL_HOST));
        if($host===''||$host==='office.excelherbal.in')throw new \RuntimeException('Fresh UAT bootstrap refuses the production office host.');
        $source=defined('EH7_SOURCE_HEAD')?(string)EH7_SOURCE_HEAD:'';
        if(!preg_match('/^[0-9a-f]{40}$/i',$source))throw new \RuntimeException('Fresh UAT bootstrap requires an exact packaged source head.');
    }

    public static function bootstrap(array $config):array {
        self::assertSafeTarget();
        $current=self::status();
        if(($current['seeded']??false)===true)return ['already_seeded'=>true]+$current;

        $status=SetupService::status();
        if(($status['initialized']??false)===true)throw new \RuntimeException('Fresh UAT bootstrap requires an uninitialized ERP database.');

        $login=trim((string)($config['wp_admin_login']??''));
        $adminPassword=(string)($config['admin_password']??'');
        $adminMobile=self::mobile((string)($config['admin_mobile']??''));
        $limitedPassword=(string)($config['limited_password']??'');
        $limitedMobile=self::mobile((string)($config['limited_mobile']??''));
        if($login===''||strlen($adminPassword)<10||strlen($limitedPassword)<10)throw new \RuntimeException('UAT admin login and passwords of at least 10 characters are required.');
        if(strlen($adminMobile)<8||strlen($limitedMobile)<8||$adminMobile===$limitedMobile)throw new \RuntimeException('Two distinct valid UAT mobile numbers are required.');

        $admin=get_user_by('login',$login);
        if(!$admin||!user_can($admin,'manage_options'))throw new \RuntimeException('Configured UAT WordPress administrator was not found or lacks manage_options.');
        $uid=(int)$admin->ID;
        wp_set_current_user($uid);
        wp_set_password($adminPassword,$uid);

        $setup=SetupService::initialize([
            'company_name'=>trim((string)($config['company_name']??''))?:'EH7 Fresh UAT',
            'branch_code'=>'UAT',
            'branch_name'=>trim((string)($config['branch_name']??''))?:'UAT Branch',
            'employee_code'=>'UAT-ADMIN',
            'employee_name'=>trim((string)($config['admin_name']??''))?:'UAT Administrator',
            'mobile'=>$adminMobile,
        ]);
        $companyId=(int)$setup['company_id'];$branchId=(int)$setup['branch_id'];$adminEmployeeId=(int)$setup['employee_id'];

        $db=Db::wpdb();
        $exists=(int)$db->get_var($db->prepare('SELECT COUNT(*) FROM '.Db::table('designations').' WHERE company_id=%d AND code=%s',$companyId,'EMPLOYEE'));
        if($exists===0)Db::mustInsert($db,Db::table('designations'),[
            'company_id'=>$companyId,'code'=>'EMPLOYEE','name'=>'UAT Field Employee','sequence_no'=>100,'field_role'=>1,'status'=>'active'
        ]);

        $caps=DesignationDefaults::all();
        $actor=new Actor($uid,$adminEmployeeId,$companyId,$branchId,[$branchId],$caps,'SYSADMIN');
        $limited=OrganizationEmployeeService::createEmployee($actor,[
            'assigned_branch_id'=>$branchId,
            'employee_code'=>'UAT-FIELD',
            'full_name'=>trim((string)($config['limited_name']??''))?:'UAT Field Employee',
            'designation_code'=>'EMPLOYEE',
            'mobile'=>$limitedMobile,
            'monthly_salary'=>30000,
            'password'=>$limitedPassword,
            'provision_login'=>true,
        ]);
        $limitedId=(int)$limited['id'];

        $source=(string)EH7_SOURCE_HEAD;
        update_option('eh7_uat_seed_mode','fresh_synthetic',false);
        update_option('eh7_uat_seed_source_head',$source,false);
        update_option('eh7_uat_seeded_at',Db::now(),false);
        update_option('eh7_uat_admin_employee_id',$adminEmployeeId,false);
        update_option('eh7_uat_limited_employee_id',$limitedId,false);

        $safety=StagingSafety::sanitize();
        $final=self::status();
        if(($final['seeded']??false)!==true)throw new \RuntimeException('Fresh UAT bootstrap verification failed.');

        return [
            'already_seeded'=>false,
            'company_id'=>$companyId,
            'branch_id'=>$branchId,
            'admin_employee_id'=>$adminEmployeeId,
            'limited_employee_id'=>$limitedId,
            'staging_safety'=>$safety,
        ]+$final;
    }

    private static function mobile(string $value):string{return preg_replace('/\D+/','',$value)?:'';}
    private static function environment():string {
        if(function_exists('wp_get_environment_type'))return (string)wp_get_environment_type();
        return defined('WP_ENVIRONMENT_TYPE')?(string)WP_ENVIRONMENT_TYPE:'production';
    }
}
