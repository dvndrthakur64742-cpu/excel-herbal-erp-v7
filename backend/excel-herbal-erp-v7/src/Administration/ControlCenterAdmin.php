<?php
namespace ExcelHerbal\ERP7\Administration;

use ExcelHerbal\ERP7\Security\ActorResolver;
use ExcelHerbal\ERP7\Setup\SetupService;

/**
 * Visible WordPress-admin entry point for the current ERP.
 *
 * The legacy Setup Assistant is intentionally read-only/hidden on current
 * releases. This control center keeps ERP administration discoverable without
 * re-introducing a second set of write rules beside the canonical ERP services.
 */
final class ControlCenterAdmin{
    private const PAGE='eh7-control-center';

    public static function boot():void{
        add_action('admin_menu',[self::class,'menu'],20);
    }

    public static function menu():void{
        add_menu_page(
            'Excel Herbal ERP',
            'Excel Herbal ERP',
            'manage_options',
            self::PAGE,
            [self::class,'render'],
            'dashicons-chart-area',
            3
        );
        add_submenu_page(
            self::PAGE,
            'ERP Control Center',
            'Control Center',
            'manage_options',
            self::PAGE,
            [self::class,'render']
        );
    }

    public static function render():void{
        if(!current_user_can('manage_options'))wp_die('Administrator access required.');

        $version=defined('EH7_VERSION')?(string)EH7_VERSION:'unknown';
        $sourceHead=defined('EH7_SOURCE_HEAD')?(string)EH7_SOURCE_HEAD:'unknown';
        $environment=Environment::type();
        $setup=SetupService::status();
        $erpUrl=home_url('/');
        $cleanupUrl=admin_url('tools.php?page=eh7-uat-cleanup');
        $deployUrl=admin_url('tools.php?page=eh7-uat-web-deploy');

        echo '<div class="wrap">';
        echo '<h1>Excel Herbal ERP Control Center</h1>';
        echo '<p class="description">Current ERP administration entry point. The legacy Setup Assistant is intentionally disabled so old write paths cannot bypass current ERP rules.</p>';

        echo '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px;max-width:1050px;margin:18px 0;">';
        self::card('Environment',strtoupper($environment),'Current WordPress/ERP environment.');
        self::card('ERP Version',$version,'Installed backend version.');
        self::card('Schema',!empty($setup['schema_installed'])?'Ready':'Attention','Database schema status.');
        self::card('Source Head',esc_html(substr($sourceHead,0,12)),'Deployed backend source.');
        echo '</div>';

        echo '<div class="notice notice-info inline"><p><strong>Where should changes be made?</strong> Day-to-day business and master-data changes must use the current ERP workflows. WordPress admin is for control, diagnostics and deployment; the old Setup Assistant must not be used for writes.</p></div>';

        echo '<h2>ERP Administration</h2>';
        echo '<table class="widefat striped" style="max-width:1050px">';
        echo '<thead><tr><th>Area</th><th>Use for</th><th>Action</th></tr></thead><tbody>';
        self::row('Current ERP','Branches, employees, products, commercial pricing, roles/authority and normal business workflows',$erpUrl,'Open ERP');
        self::row('Safe UAT Cleanup','Controlled UAT anomaly diagnostics and approved cleanup',$cleanupUrl,'Open UAT Cleanup');
        self::row('UAT Web Deploy','Certified Flutter web runtime deployment/attestation',$deployUrl,'Open Web Deploy');
        echo '</tbody></table>';

        try{
            $actor=ActorResolver::current();
            $diag=MaintenanceService::diagnostics($actor);
            $status=(string)($diag['status']??'unknown');
            echo '<h2 style="margin-top:24px">ERP Diagnostics</h2>';
            echo '<p><strong>ERP actor:</strong> '.esc_html((string)$actor->designationCode).' · Employee #'.esc_html((string)$actor->employeeId).'</p>';
            echo '<p><strong>Diagnostic status:</strong> '.esc_html(ucfirst($status)).' · '.
                'Stock negative: '.esc_html((string)($diag['stock']['negative_balances']??0)).' · '.
                'Unbalanced journals: '.esc_html((string)($diag['accounting']['unbalanced_journals']??0)).' · '.
                'Daily stale cycles: '.esc_html((string)($diag['daily_order']['stale_non_completed_cycles']??0)).'.</p>';
        }catch(\Throwable $e){
            echo '<div class="notice notice-warning inline"><p>ERP diagnostics are unavailable for this WordPress user: '.esc_html($e->getMessage()).'</p></div>';
        }

        echo '</div>';
    }

    private static function card(string $title,string $value,string $help):void{
        echo '<div class="card" style="margin:0;max-width:none;padding:14px 16px;">';
        echo '<div style="font-size:12px;color:#646970;font-weight:600;">'.esc_html($title).'</div>';
        echo '<div style="font-size:20px;font-weight:700;margin:4px 0;">'.esc_html($value).'</div>';
        echo '<div style="color:#646970;">'.esc_html($help).'</div>';
        echo '</div>';
    }

    private static function row(string $area,string $use,string $url,string $label):void{
        echo '<tr><td><strong>'.esc_html($area).'</strong></td><td>'.esc_html($use).'</td><td><a class="button button-primary" href="'.esc_url($url).'">'.esc_html($label).'</a></td></tr>';
    }
}
