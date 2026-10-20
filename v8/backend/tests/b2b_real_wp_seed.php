<?php

/**
 * Executed ONLY by wp-cli eval-file on a fresh, disposable local WordPress.
 * Creates synthetic WordPress users and ERP identities, never business rows
 * or sale/payment evidence. Must not be included in the production plugin.
 */
if(PHP_SAPI!=='cli'||!defined('WP_CLI')||!WP_CLI)
    throw new RuntimeException('Isolated WP-CLI only.');
if(!function_exists('wp_get_environment_type')
    ||wp_get_environment_type()!=='development'
    ||!defined('EH8_ENABLE_B2B_STAGING_REST_PROBE')
    ||EH8_ENABLE_B2B_STAGING_REST_PROBE!==true)
    throw new RuntimeException('Disposable development feature flag required.');
global $wpdb;
if($wpdb->get_var('SELECT DATABASE()')!=='v8_test')
    throw new RuntimeException('Refusing all databases except disposable v8_test.');
if($wpdb->prefix!=='wp_')
    throw new RuntimeException('Only fresh wp_ prefix test database is allowed.');
if((string)get_option('eh7_schema_version','')!==
    \ExcelHerbal\ERP7\Database\Schema::VERSION)
    throw new RuntimeException('Canonical V7 plugin migration not installed.');
$company='wp_eh7_companies';$branches='wp_eh7_branches';$employees='wp_eh7_employees';
foreach([$company,$branches,$employees] as $table){
    if($wpdb->get_var($wpdb->prepare('SHOW TABLES LIKE %s',$table))!==$table)
        throw new RuntimeException('Canonical ERP master table missing: '.$table);
}
if((int)$wpdb->get_var("SELECT COUNT(*) FROM {$company}")!==0
    ||(int)$wpdb->get_var("SELECT COUNT(*) FROM {$employees}")!==0
    ||(int)$wpdb->get_var("SELECT COUNT(*) FROM {$branches}")!==0)
    throw new RuntimeException('Synthetic seed refuses non-empty master data.');
$now=gmdate('Y-m-d H:i:s');
if($wpdb->insert($company,['id'=>11,'name'=>'Isolated Synthetic UAT','status'=>'active','created_at'=>$now])!==1)
    throw new RuntimeException('Cannot seed synthetic company.');
foreach([[31,'UAT-31','Synthetic Branch A'],[32,'UAT-32','Synthetic Branch B']] as [$id,$code,$name]){
    if($wpdb->insert($branches,['id'=>$id,'company_id'=>11,
        'code'=>$code,'name'=>$name,'status'=>'active','created_at'=>$now])!==1)
        throw new RuntimeException('Cannot seed synthetic branch.');
}
$identities=[
    ['finance','RM',31,'9876500101'],
    ['bm','BM',31,'9876500102'],
    ['fse','EMPLOYEE',31,'9876500103'],
    ['otherbranch','RM',32,'9876500104'],
];
$secret=getenv('B2B_REAL_WP_UAT_PASSWORD');
if(!is_string($secret)||strlen($secret)<16)
    throw new RuntimeException('Require ephemeral 16+ character CI UAT password.');
foreach($identities as [$name,$designation,$branch,$mobile]){
    $login='eh8_uat_'.$name;
    if(username_exists($login))throw new RuntimeException('Refusing duplicate WP identity.');
    $id=wp_create_user($login,$secret,$login.'@example.invalid');
    if(is_wp_error($id))throw new RuntimeException('WP identity creation failed: '.$name);
    $inserted=$wpdb->insert($employees,[
        'company_id'=>11,'employee_code'=>'UAT-'.strtoupper($name),
        'wp_user_id'=>$id,'designation_code'=>$designation,
        'assigned_branch_id'=>$branch,
        'full_name'=>'Synthetic UAT '.$name,'mobile'=>$mobile,
        'monthly_salary'=>'0.00','status'=>'active','created_at'=>$now,
    ]);
    if($inserted!==1)throw new RuntimeException('ERP employee seed failed: '.$name);
}
$expected=4;
if((int)$wpdb->get_var("SELECT COUNT(*) FROM {$employees}")!==$expected)
    throw new RuntimeException('Synthetic employees not fully inserted.');
WP_CLI::success('Four synthetic real WP users + company 11 and branches 31/32 installed on disposable v8_test.');
