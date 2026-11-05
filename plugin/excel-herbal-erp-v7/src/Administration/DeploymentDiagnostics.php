<?php
namespace ExcelHerbal\ERP7\Administration;

/**
 * Read-only environment diagnostics. A production URL accidentally labelled
 * "staging" must NOT be reported as a sanitized UAT clone or change sessions.
 */
final class DeploymentDiagnostics {
    public static function status():array {
        $environment=function_exists('wp_get_environment_type')
            ?(string)wp_get_environment_type()
            :(defined('WP_ENVIRONMENT_TYPE')?(string)WP_ENVIRONMENT_TYPE:'production');
        $host=strtolower((string)parse_url((string)home_url('/'),PHP_URL_HOST));
        $officeHost=$host==='office.excelherbal.in';
        $source=defined('EH7_SOURCE_HEAD')?(string)EH7_SOURCE_HEAD:'';
        $mismatch=$officeHost&&$environment!=='production';
        return [
            'office_production_host'=>$officeHost,
            'wordpress_environment'=>$environment,
            'office_environment_mismatch'=>$mismatch,
            'configuration_review_required'=>$mismatch,
            'embedded_source_sha_format_valid'=>preg_match('/^[a-f0-9]{40}$/i',$source)===1,
            // staging_safety.source_head_match is about synthetic
            // sanitization, NOT the identity of the installed plugin.
            'staging_source_marker_purpose'=>'sanitized_uat_only',
        ];
    }
}
