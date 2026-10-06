<?php
namespace ExcelHerbal\ERP7\Core;
use ExcelHerbal\ERP7\Database\Schema;
use ExcelHerbal\ERP7\Http\Api;
use ExcelHerbal\ERP7\Security\MobileAuth;
use ExcelHerbal\ERP7\Administration\MaintenanceService;
use ExcelHerbal\ERP7\Administration\LegacySetupAssistantGuard;
use ExcelHerbal\ERP7\Administration\UatCleanupAdmin;
use ExcelHerbal\ERP7\Administration\UatWebDeployAdmin;
final class Plugin{
    public static function activate():void{Schema::maybeUpgrade();}
    public static function boot():void{
        $schemaOk=Schema::maybeUpgrade();
        add_filter('rest_pre_serve_request',[\ExcelHerbal\ERP7\Organization\DocumentVault::class,'serve'],10,4);
        \ExcelHerbal\ERP7\Payroll\PayrollAdmin::boot();
        MobileAuth::boot();
        MaintenanceService::boot();
        LegacySetupAssistantGuard::boot();
        UatCleanupAdmin::boot();
        UatWebDeployAdmin::boot();
        add_action('rest_api_init',[Api::class,'register']);
        if(!$schemaOk&&is_admin())add_action('admin_notices',[self::class,'schemaNotice']);
    }
    public static function schemaNotice():void{
        if(!current_user_can('manage_options'))return;
        $msg=(string)get_option('eh7_schema_migration_error','Unknown database migration error.');
        echo '<div class="notice notice-error"><p><strong>Excel Herbal ERP:</strong> Database upgrade could not complete. The site is still running. Error: '.esc_html($msg).'</p></div>';
    }
}
