<?php
/**
 * F20 — add a third synthetic staff role to disposable CI WordPress only.
 * Called with: docker exec "$wp_container" wp eval-file /tmp/eh7-ci-f20-bm.php
 * No hosting, production, or persistent staging access is permitted.
 */
use ExcelHerbal\ERP7\Administration\FreshUatBootstrap;
use ExcelHerbal\ERP7\Administration\StagingSafety;
use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Organization\OrganizationEmployeeService;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\DesignationDefaults;

function f20_assert($condition, string $message): void {
    if (!$condition) throw new RuntimeException('F20 synthetic BM seed BLOCKED: '.$message);
}

f20_assert(PHP_SAPI === 'cli' && getenv('EH7_CI_ISOLATED') === '1',
    'not ephemeral CI');
f20_assert(wp_get_environment_type() === 'staging',
    'not staging WordPress');
$host = strtolower((string)parse_url(home_url('/'), PHP_URL_HOST));
f20_assert($host === 'wordpress-uat-production.up.railway.app',
    'not the approved disposable WP hostname');
$source = (string)(defined('EH7_SOURCE_HEAD') ? EH7_SOURCE_HEAD : '');
$expected = (string)getenv('RAILWAY_GIT_COMMIT_SHA');
f20_assert((bool)preg_match('/^[a-f0-9]{40}$/', $source) &&
    hash_equals($source, $expected), 'Git source pin mismatch');

$seed = FreshUatBootstrap::status();
$safety = StagingSafety::status();
f20_assert(($seed['seeded'] ?? false) === true &&
    ($seed['synthetic_only'] ?? false) === true &&
    ($seed['source_head_match'] ?? false) === true &&
    ($safety['sanitized'] ?? false) === true &&
    ($safety['source_head_match'] ?? false) === true &&
    ($safety['active_mobile_sessions_zero'] ?? false) === true &&
    ($safety['active_push_devices_zero'] ?? false) === true,
    'original disposable UAT seed is not safe and idle');

$db = Db::wpdb();
$employeeTable = Db::table('employees');
$admin = $db->get_row($db->prepare(
    "SELECT id,company_id,assigned_branch_id,wp_user_id
     FROM {$employeeTable} WHERE employee_code=%s AND status=%s",
    'UAT-ADMIN','active'
), ARRAY_A);
$field = $db->get_row($db->prepare(
    "SELECT id,company_id,assigned_branch_id
     FROM {$employeeTable} WHERE employee_code=%s AND status=%s",
    'UAT-FIELD','active'
), ARRAY_A);

f20_assert(is_array($admin) && is_array($field) &&
    (int)$admin['id'] === 1 &&
    (int)$field['id'] === 2 &&
    (int)$admin['company_id'] === 1 &&
    (int)$field['company_id'] === 1 &&
    (int)$admin['assigned_branch_id'] === 1 &&
    (int)$field['assigned_branch_id'] === 1,
    'synthetic admin/field fixture has changed');

$existing = (int)$db->get_var($db->prepare(
    "SELECT COUNT(*) FROM {$employeeTable}
     WHERE company_id=%d AND (employee_code=%s OR mobile=%s)",
     1,'UAT-BM','9000000003'
));
f20_assert($existing === 0 &&
    get_user_by('login','9000000003') === false,
    'synthetic BM already provisioned (refuse to overwrite)');

$designationTable = Db::table('designations');
$designationCount = (int)$db->get_var($db->prepare(
    "SELECT COUNT(*) FROM {$designationTable}
     WHERE company_id=%d AND code=%s AND status=%s",
    1,'BM','active'
));
if ($designationCount === 0) {
    Db::mustInsert($db, $designationTable, [
        'company_id'=>1,
        'code'=>'BM',
        'name'=>'Synthetic Branch Manager',
        'sequence_no'=>25,
        'field_role'=>0,
        'status'=>'active',
    ]);
}
$wpAdminId = (int)$admin['wp_user_id'];
f20_assert($wpAdminId > 0 &&
    user_can($wpAdminId, 'manage_options'),
    'synthetic head-office WordPress identity invalid');
$actor = new Actor(
    $wpAdminId,1,1,1,[1],DesignationDefaults::all(),'SYSADMIN'
);
$result = OrganizationEmployeeService::createEmployee($actor, [
    'assigned_branch_id'=>1,
    'employee_code'=>'UAT-BM',
    'full_name'=>'CI Synthetic Branch Manager',
    'designation_code'=>'BM',
    'mobile'=>'9000000003',
    'monthly_salary'=>35000,
    'password'=>'eh7_ci_bm_password_only',
    'provision_login'=>true,
]);

f20_assert((int)($result['id']??0)===3 &&
    ($result['login_enabled']??false) === true,
    'third synthetic staff user not created');
$bm = $db->get_row($db->prepare(
    "SELECT id,wp_user_id,assigned_branch_id,designation_code
     FROM {$employeeTable} WHERE company_id=%d AND employee_code=%s",
    1,'UAT-BM'
), ARRAY_A);
f20_assert(is_array($bm) &&
    (int)$bm['id']===3 &&
    (int)$bm['assigned_branch_id']===1 &&
    (string)$bm['designation_code']==='BM',
    'BM was not tied exclusively to synthetic branch 1');
$wpBm = get_userdata((int)$bm['wp_user_id']);
f20_assert($wpBm &&
    $wpBm->user_login === '9000000003' &&
    wp_check_password('eh7_ci_bm_password_only',$wpBm->user_pass,$wpBm->ID),
    'synthetic mobile-username BM credentials are invalid');
$after = StagingSafety::status();
f20_assert(($after['active_mobile_sessions_zero']??false)===true &&
    ($after['active_push_devices_zero']??false)===true,
    'unexpected active session after synthetic BM provisioning');
echo "PASS F20 synthetic Branch Manager id=3, mobile username, BM designation, exactly one branch; no sessions\n";
