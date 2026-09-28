<?php
namespace ExcelHerbal\ERP7\Administration;

final class Environment {
    public static function type():string {
        if(defined('EH7_DEPLOY_ENVIRONMENT')){
            $value=strtolower(trim((string)EH7_DEPLOY_ENVIRONMENT));
            if(in_array($value,['local','development','staging','production'],true))return $value;
        }
        if(function_exists('wp_get_environment_type'))return (string)wp_get_environment_type();
        return defined('WP_ENVIRONMENT_TYPE')?(string)WP_ENVIRONMENT_TYPE:'production';
    }

    public static function allowsOfficeBuildUat():bool {
        return self::type()==='staging'
            && defined('EH7_BUILD_UAT_ALLOW_OFFICE')
            && EH7_BUILD_UAT_ALLOW_OFFICE===true;
    }

    public static function assertSafeUatHost(string $host):void {
        $host=strtolower(trim($host));
        if($host==='')throw new \RuntimeException('UAT target host is missing.');
        if($host==='office.excelherbal.in'&&!self::allowsOfficeBuildUat()){
            throw new \RuntimeException('UAT operations on office.excelherbal.in require the explicit BUILD/UAT package marker.');
        }
    }
}
