<?php
namespace ExcelHerbal\ERP7\Administration;

use ExcelHerbal\ERP7\Security\ActorResolver;

final class UatCleanupAdmin {
    private const PAGE='eh7-uat-cleanup';
    private const ACTION='eh7_uat_cleanup';

    public static function boot():void{
        add_action('admin_menu',[self::class,'menu']);
        add_action('admin_post_'.self::ACTION,[self::class,'handle']);
    }

    public static function menu():void{
        add_management_page(
            'EH7 UAT Cleanup',
            'EH7 UAT Cleanup',
            'manage_options',
            self::PAGE,
            [self::class,'render']
        );
    }

    public static function render():void{
        if(!current_user_can('manage_options'))wp_die('Administrator access required.');
        $result=get_transient(self::resultKey());
        if($result!==false)delete_transient(self::resultKey());
        echo '<div class="wrap"><h1>EH7 Safe UAT Cleanup</h1>';
        echo '<p>This uses the ERP actor mapped to the current WordPress user and the existing audited MaintenanceService. It does not bypass ERP access checks.</p>';
        if(is_array($result)){
            $ok=!empty($result['ok']);
            echo '<div class="notice '.($ok?'notice-success':'notice-error').'"><p>'.esc_html((string)($result['message']??'Cleanup result unavailable.')).'</p></div>';
        }
        try{
            $actor=ActorResolver::current();
            $diag=MaintenanceService::diagnostics($actor);
            echo '<p><strong>ERP actor:</strong> '.esc_html((string)$actor->designationCode).' · Employee #'.esc_html((string)$actor->employeeId).'</p>';
            echo '<p><strong>Current diagnostics:</strong> Attendance '.esc_html((string)($diag['attendance']['open_past_without_checkout']??0)).
                ', Daily '.esc_html((string)($diag['daily_order']['stale_non_completed_cycles']??0)).
                ', Payroll '.esc_html((string)($diag['payroll']['legacy_draft_runs']??0)).
                ', Roles '.esc_html((string)($diag['access']['duplicate_active_role_names']??0)).
                ', Designations '.esc_html((string)($diag['organization']['duplicate_active_designation_names']??0)).'.</p>';
            echo '<form method="post" action="'.esc_url(admin_url('admin-post.php')).'">';
            wp_nonce_field(self::ACTION);
            echo '<input type="hidden" name="action" value="'.esc_attr(self::ACTION).'">';
            echo '<p><label for="eh7_reason"><strong>Audit reason</strong></label><br><input id="eh7_reason" name="reason" type="text" class="regular-text" value="UAT cleanup after verified final deployment and diagnostics review" required minlength="10"></p>';
            echo '<p><label><input type="checkbox" name="confirm" value="1" required> I confirm safe UAT anomaly resolution.</label></p>';
            submit_button('Resolve Safe UAT Anomalies','primary','submit',false);
            echo '</form>';
        }catch(\Throwable $e){
            echo '<div class="notice notice-error"><p>'.esc_html($e->getMessage()).'</p></div>';
        }
        echo '</div>';
    }

    public static function handle():void{
        if(!current_user_can('manage_options'))wp_die('Administrator access required.');
        check_admin_referer(self::ACTION);
        $reason=sanitize_text_field((string)($_POST['reason']??''));
        $confirmed=!empty($_POST['confirm']);
        try{
            if(!$confirmed)throw new \RuntimeException('Explicit cleanup confirmation is required.');
            $actor=ActorResolver::current();
            $result=MaintenanceService::cleanup($actor,[
                'operation'=>'resolve_uat_anomalies',
                'confirmation'=>'RESOLVE_UAT_ANOMALIES',
                'reason'=>$reason,
            ]);
            $message=sprintf(
                'UAT cleanup complete: attendance %d, daily %d, payroll %d, roles %d, designations %d, skipped %d.',
                (int)($result['attendance_acknowledged']??0),
                (int)($result['daily_cycles_cancelled']??0),
                (int)($result['payroll_drafts_discarded']??0),
                (int)($result['roles_deactivated']??0),
                (int)($result['designations_deactivated']??0),
                (int)($result['daily_cycles_skipped']??0)
            );
            set_transient(self::resultKey(),['ok'=>true,'message'=>$message],120);
        }catch(\Throwable $e){
            set_transient(self::resultKey(),['ok'=>false,'message'=>$e->getMessage()],120);
        }
        wp_safe_redirect(admin_url('tools.php?page='.self::PAGE));
        exit;
    }

    private static function resultKey():string{
        return 'eh7_uat_cleanup_result_'.get_current_user_id();
    }
}
