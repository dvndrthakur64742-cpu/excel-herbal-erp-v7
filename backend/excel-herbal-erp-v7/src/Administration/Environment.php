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

    /** @return array{status:string,wp_environment_type_defined:bool,wp_environment_type:string,disallow_file_edit_defined:bool,disallow_file_edit:bool} */
    public static function hostHardeningStatus():array {
        $wpEnvironmentDefined=defined('WP_ENVIRONMENT_TYPE');
        $wpEnvironment=$wpEnvironmentDefined?strtolower(trim((string)WP_ENVIRONMENT_TYPE)):'undefined';
        $fileEditDefined=defined('DISALLOW_FILE_EDIT');
        $fileEditDisabled=$fileEditDefined&&DISALLOW_FILE_EDIT===true;
        $passed=$wpEnvironmentDefined&&$wpEnvironment==='staging'&&$fileEditDisabled;
        return[
            'status'=>$passed?'passed':'blocked',
            'wp_environment_type_defined'=>$wpEnvironmentDefined,
            'wp_environment_type'=>$wpEnvironment,
            'disallow_file_edit_defined'=>$fileEditDefined,
            'disallow_file_edit'=>$fileEditDisabled,
        ];
    }

    public static function allowsOfficeBuildUat():bool {
        return self::type()==='staging'
            && defined('EH7_BUILD_UAT_ALLOW_OFFICE')
            && EH7_BUILD_UAT_ALLOW_OFFICE===true
            && defined('EH7_BUILD_UAT_HOST')
            && strtolower(trim((string)EH7_BUILD_UAT_HOST))==='office.excelherbal.in';
    }

    public static function assertSafeUatHost(string $host):void {
        $host=strtolower(trim($host));
        if($host==='')throw new \RuntimeException('UAT target host is missing.');
        if($host==='office.excelherbal.in'&&!self::allowsOfficeBuildUat()){
            throw new \RuntimeException('UAT operations on office.excelherbal.in require the explicit BUILD/UAT package marker.');
        }
    }
}
