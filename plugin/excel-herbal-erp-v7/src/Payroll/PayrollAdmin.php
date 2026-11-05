<?php
namespace ExcelHerbal\ERP7\Payroll;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Security\ActorResolver;
use ExcelHerbal\ERP7\Security\Capabilities;

/** Small authenticated WordPress workspace until the Flutter client adopts the new APIs. */
final class PayrollAdmin {
    public static function boot():void {
        add_action('admin_menu',fn()=>add_management_page('ERP Payroll Controls','ERP Payroll Controls','read','eh7-payroll-controls',[self::class,'render']));
    }
    public static function render():void {
        echo '<div class="wrap"><h1>ERP Payroll Controls</h1>';
        try {
            $a=ActorResolver::current();
            if(!$a->can(Capabilities::PAYROLL_GENERATE)&&!$a->can(Capabilities::PAYROLL_APPROVE))throw new \RuntimeException('Payroll permission is required.');
            if($_SERVER['REQUEST_METHOD']==='POST'){
                check_admin_referer('eh7_payroll_controls');$action=sanitize_key(wp_unslash($_POST['operation']??''));$data=wp_unslash($_POST);
                if($action==='request')SalaryService::request($a,(int)($data['employee_id']??0),$data);
                elseif($action==='review')SalaryService::approve($a,(int)($data['revision_id']??0),($data['decision']??'')==='approve');
                elseif($action==='discard')PayrollPerformanceService::discardDraft($a,(int)($data['run_id']??0),(string)($data['reason']??''));
                elseif($action==='policy'){
                    $policy=SalaryService::policy($a);$type=strtoupper(trim((string)($data['leave_type']??'')));$treatment=(string)($data['treatment']??'');
                    if(!in_array($treatment,['paid','unpaid'],true)||$type==='')throw new \RuntimeException('Choose a leave type and treatment.');
                    $policy['leave_types'][$type]=$treatment==='paid';SalaryService::policy($a,['leave_types'=>$policy['leave_types'],'reason'=>(string)($data['reason']??'')]);
                }else throw new \RuntimeException('Unknown action.');
                echo '<div class="notice notice-success"><p>Saved successfully.</p></div>';
            }
            $db=Db::wpdb();$branches=implode(',',array_map('intval',$a->branchIds))?:'0';
            echo '<p>Salary uses the company’s full-month working-day calendar. Past salary history must be confirmed; it is not inferred from today’s salary. Posted payroll is not changed.</p>';
            if($a->can(Capabilities::PAYROLL_GENERATE)){
                $employees=(array)$db->get_results($db->prepare('SELECT id,employee_code,full_name FROM '.Db::table('employees')." WHERE company_id=%d AND assigned_branch_id IN ({$branches}) ORDER BY full_name",$a->companyId),ARRAY_A);
                echo '<h2>Request salary revision / confirm earlier salary</h2>';self::form('request');echo '<p><label>Employee <select name="employee_id" required>';
                foreach($employees as$e)echo '<option value="'.(int)$e['id'].'">'.esc_html($e['employee_code'].' — '.$e['full_name']).'</option>';
                echo '</select></label></p><p><label>Monthly salary <input type="number" name="monthly_salary" min="0.01" step="0.01" required></label></p><p><label>Effective from <input type="date" name="effective_from" max="'.esc_attr(Db::today()).'" required></label></p>';self::reason();submit_button('Submit for independent approval');echo '</form>';
            }
            $pending=(array)$db->get_results($db->prepare('SELECT s.*,e.employee_code,e.full_name FROM '.Db::table('salary_revisions').' s JOIN '.Db::table('employees')." e ON e.id=s.employee_id AND e.company_id=s.company_id WHERE s.company_id=%d AND e.assigned_branch_id IN ({$branches}) AND s.status='pending' ORDER BY s.id DESC LIMIT 100",$a->companyId),ARRAY_A);
            echo '<h2>Pending salary revisions</h2><table class="widefat"><thead><tr><th>Employee</th><th>Effective date</th><th>Salary</th><th>Reason</th><th>Review</th></tr></thead><tbody>';
            foreach($pending as$r){echo '<tr><td>'.esc_html($r['employee_code'].' — '.$r['full_name']).'</td><td>'.esc_html($r['effective_from']).'</td><td>'.esc_html($r['monthly_salary']).'</td><td>'.esc_html($r['reason']).'</td><td>';
                if($a->can(Capabilities::PAYROLL_APPROVE)&&(int)$r['created_by']!==$a->employeeId&&(int)$r['employee_id']!==$a->employeeId){self::form('review');echo '<input type="hidden" name="revision_id" value="'.(int)$r['id'].'"><button class="button" name="decision" value="approve">Approve</button> <button class="button" name="decision" value="reject">Reject</button></form>';}else echo 'Independent checker required';echo '</td></tr>';}
            echo '</tbody></table>';
            if($a->can(Capabilities::PAYROLL_APPROVE)&&$a->can(Capabilities::ACCESS_MANAGE)){
                echo '<h2>Paid / unpaid leave policy</h2><p>Requires authority over all active branches. Existing payroll snapshots are unchanged.</p>';
                self::form('policy');echo '<p><label>Exact leave type <input name="leave_type" maxlength="50" required></label> <label>Treatment <select name="treatment"><option value="paid">Paid</option><option value="unpaid">Unpaid / LWP</option></select></label></p>';self::reason();submit_button('Save leave treatment');echo '</form>';
            }
            if($a->can(Capabilities::PAYROLL_GENERATE)){
                $runs=(array)$db->get_results($db->prepare('SELECT id,branch_id,period_start,period_end FROM '.Db::table('payroll_runs')." WHERE company_id=%d AND branch_id IN ({$branches}) AND status='draft' ORDER BY id DESC LIMIT 100",$a->companyId),ARRAY_A);
                echo '<h2>Discard unposted payroll draft</h2><p>Use this to regenerate a legacy or incorrect draft. Its values are retained in the audit log. Approved/paid payroll cannot be discarded here.</p>';self::form('discard');echo '<select name="run_id" required>';
                foreach($runs as$r)echo '<option value="'.(int)$r['id'].'">'.esc_html('#'.$r['id'].' · Branch '.$r['branch_id'].' · '.$r['period_start'].' to '.$r['period_end']).'</option>';
                echo '</select>';self::reason();submit_button('Discard draft');echo '</form>';
            }
        } catch(\Throwable $e){echo '<div class="notice notice-error"><p>'.esc_html($e->getMessage()).'</p></div>';}
        echo '</div>';
    }
    private static function form(string $action):void {echo '<form method="post">';wp_nonce_field('eh7_payroll_controls');echo '<input type="hidden" name="operation" value="'.esc_attr($action).'">';}
    private static function reason():void {echo '<p><label>Reason <input name="reason" minlength="5" maxlength="255" required class="regular-text"></label></p>';}
}
