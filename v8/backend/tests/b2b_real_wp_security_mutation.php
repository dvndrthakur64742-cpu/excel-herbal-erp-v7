<?php
declare(strict_types=1);
/**
 * REAL WordPress/MariaDB negative-auth regression mutations.
 *
 * Must run exclusively from WP-CLI on the temporary GitHub-hosted v8_test
 * WordPress install. Modifies only synthetic company 11 / employee UAT-FINANCE
 * and synthetic branch 31; refuses to act on any real ERP records.
 */
if(PHP_SAPI!=='cli'||!defined('WP_CLI')||!WP_CLI
    ||getenv('GITHUB_ACTIONS')!=='true'
    ||getenv('B2B_REAL_WP_ROOT')===false
    ||realpath(getenv('B2B_REAL_WP_ROOT'))!==realpath(ABSPATH)
    ||!function_exists('wp_get_environment_type')
    ||wp_get_environment_type()!=='development'
    ||!defined('EH8_ENABLE_B2B_STAGING_REST_PROBE')
    ||EH8_ENABLE_B2B_STAGING_REST_PROBE!==true)
    throw new RuntimeException('Refused: not the ephemeral CI WordPress installation.');
global $wpdb;
if($wpdb->get_var('SELECT DATABASE()')!=='v8_test'||$wpdb->prefix!=='wp_')
    throw new RuntimeException('Refused: not isolated v8_test database.');
$action=(string)getenv('B2B_REAL_WP_MUTATION');
$allowed=[
    'deny_finance','restore_finance',
    'disable_branch','restore_branch',
    'disable_employee','restore_employee',
    'hide_payment_table','restore_payment_table',
    'assert_restored',
];
if(!in_array($action,$allowed,true))
    throw new RuntimeException('Unknown or unauthorized synthetic mutation action.');
$companyTable='wp_eh7_companies';
$employeeTable='wp_eh7_employees';
$branchTable='wp_eh7_branches';
$overrideTable='wp_eh7_employee_capability_overrides';
$company=$wpdb->get_row($wpdb->prepare("SELECT id,name FROM {$companyTable} WHERE id=%d",11),ARRAY_A);
$employee=$wpdb->get_row($wpdb->prepare(
    "SELECT id,company_id,employee_code,assigned_branch_id,wp_user_id,status FROM {$employeeTable} WHERE company_id=%d AND employee_code=%s",
    11,'UAT-FINANCE'
),ARRAY_A);
$branch=$wpdb->get_row($wpdb->prepare(
    "SELECT id,company_id,code,status FROM {$branchTable} WHERE company_id=%d AND id=%d",
    11,31
),ARRAY_A);
if(!$company||$company['name']!=='Isolated Synthetic UAT'
    ||!$employee||$employee['employee_code']!=='UAT-FINANCE'
    ||(int)$employee['company_id']!==11
    ||(int)$employee['assigned_branch_id']!==31
    ||(int)$employee['wp_user_id']<1
    ||!$branch||$branch['code']!=='UAT-31'
    ||(int)$branch['company_id']!==11)
    throw new RuntimeException('Refused: synthetic fixture identity did not match exactly.');
// Protect against running on any polluted real business database.
if((int)$wpdb->get_var("SELECT COUNT(*) FROM {$companyTable}")!==1
   ||(int)$wpdb->get_var("SELECT COUNT(*) FROM {$employeeTable}")!==4
   ||(int)$wpdb->get_var("SELECT COUNT(*) FROM {$branchTable}")!==2)
    throw new RuntimeException('Refused: disposable CI master record counts mismatch.');
if($action==='assert_restored'){
    $overrideCount=(int)$wpdb->get_var($wpdb->prepare(
        "SELECT COUNT(*) FROM {$overrideTable} WHERE company_id=%d AND employee_id=%d AND capability=%s AND active=1",
        11,(int)$employee['id'],'finance.accounting.view'
    ));
    if($overrideCount!==0
       ||$employee['status']!=='active'
       ||$branch['status']!=='active'
       ||$wpdb->get_var('SHOW TABLES LIKE "v8_b2b_payment_intents_uat"')!=='v8_b2b_payment_intents_uat'
       ||$wpdb->get_var('SHOW TABLES LIKE "v8_b2b_payment_intents_uat_hidden_ci"')!==null)
        throw new RuntimeException('Security regression left an altered synthetic fixture behind.');
    WP_CLI::success('All temporary role/branch/user/schema test changes restored on v8_test.');
    return;
}
if(in_array($action,['hide_payment_table','restore_payment_table'],true)){
    $table='v8_b2b_payment_intents_uat';
    $hidden='v8_b2b_payment_intents_uat_hidden_ci';
    $from=$action==='hide_payment_table'?$table:$hidden;
    $to=$action==='hide_payment_table'?$hidden:$table;
    if($wpdb->get_var($wpdb->prepare('SHOW TABLES LIKE %s',$from))!==$from
       ||$wpdb->get_var($wpdb->prepare('SHOW TABLES LIKE %s',$to))!==null)
        throw new RuntimeException('Refused: payment table state is not the expected disposable fixture.');
    // Literal allowlisted test identifiers, not caller-supplied SQL.
    if($wpdb->query("RENAME TABLE `{$from}` TO `{$to}`")===false)
        throw new RuntimeException('Disposable metadata rename failed.');
    WP_CLI::success('Guarded ephemeral table metadata mutation: '.$action);
    return;
}
$id=(int)$employee['id'];
$finance='finance.accounting.view';
$now=gmdate('Y-m-d H:i:s');
if($action==='deny_finance'){
    $existing=$wpdb->get_var($wpdb->prepare(
        "SELECT id FROM {$overrideTable} WHERE company_id=%d AND employee_id=%d AND capability=%s",
        11,$id,$finance));
    if($existing)throw new RuntimeException('Refused: finance deny override already exists.');
    $count=$wpdb->insert($overrideTable,[
        'company_id'=>11,'employee_id'=>$id,'capability'=>$finance,
        'effect'=>'deny','active'=>1,'created_by'=>$id,'created_at'=>$now
    ]);
}elseif($action==='restore_finance'){
    $count=$wpdb->delete($overrideTable,[
        'company_id'=>11,'employee_id'=>$id,'capability'=>$finance,
        'effect'=>'deny','active'=>1
    ]);
}elseif($action==='disable_branch'){
    if($branch['status']!=='active')throw new RuntimeException('Branch must initially be active.');
    $count=$wpdb->update($branchTable,['status'=>'inactive'],[
        'company_id'=>11,'id'=>31,'status'=>'active'
    ]);
}elseif($action==='restore_branch'){
    if($branch['status']!=='inactive')throw new RuntimeException('Branch must currently be inactive.');
    $count=$wpdb->update($branchTable,['status'=>'active'],[
        'company_id'=>11,'id'=>31,'status'=>'inactive'
    ]);
}elseif($action==='disable_employee'){
    if($employee['status']!=='active')throw new RuntimeException('Employee must initially be active.');
    $count=$wpdb->update($employeeTable,['status'=>'inactive'],[
        'company_id'=>11,'id'=>$id,'status'=>'active'
    ]);
}else{
    if($employee['status']!=='inactive')throw new RuntimeException('Employee must currently be inactive.');
    $count=$wpdb->update($employeeTable,['status'=>'active'],[
        'company_id'=>11,'id'=>$id,'status'=>'inactive'
    ]);
}
if($count!==1)throw new RuntimeException('Synthetic mutation did not affect exactly one row.');
WP_CLI::success('Performed guarded ephemeral WordPress identity/branch regression mutation: '.$action);
