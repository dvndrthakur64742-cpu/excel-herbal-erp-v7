<?php
declare(strict_types=1);
if ($argc !== 2) { fwrite(STDERR, "Supply packaged V8 root\n"); exit(2); }
$plugin = realpath($argv[1]);
if ($plugin === false) throw new RuntimeException('Package root unavailable.');
define('ABSPATH', '/mock-wp/');
define('WP_ENVIRONMENT_TYPE', 'staging');
define('DISALLOW_FILE_EDIT', true);
$GLOBALS['eh8_wp_options'] = ['active_plugins'=>[], 'eh7_schema_version'=>'7.3.5-performance-indexes-1'];
$GLOBALS['eh8_wp_actions'] = [];
$GLOBALS['eh8_wp_activation'] = null;
$GLOBALS['eh8_wp_deactivation'] = null;
$GLOBALS['eh8_deactivated'] = [];
$GLOBALS['eh8_temp_upload'] = sys_get_temp_dir().'/ehv8-test-'.bin2hex(random_bytes(7));

function get_option($name, $default = false) { return $GLOBALS['eh8_wp_options'][$name] ?? $default; }
function get_site_option($name, $default=[]) { return $default; }
function is_multisite() { return false; }
function wp_get_environment_type() { return 'staging'; }
function home_url($path='/') { return 'https://office.excelherbal.in'.$path; }
function plugin_dir_path($file) { return dirname($file).'/'; }
function plugin_basename($file) { return 'excel-herbal-erp-v8/excel-herbal-erp-v8.php'; }
function add_action($name, $callback, $priority=10) { $GLOBALS['eh8_wp_actions'][$name][] = $callback; }
function register_activation_hook($file,$callback) { $GLOBALS['eh8_wp_activation']=$callback; }
function register_deactivation_hook($file,$callback) { $GLOBALS['eh8_wp_deactivation']=$callback; }
function deactivate_plugins($plugin,$silent=false) { $GLOBALS['eh8_deactivated'][]=$plugin; }
function wp_die($message) { throw new RuntimeException('WordPress blocked: '.$message); }
function esc_html($value) { return htmlspecialchars((string)$value,ENT_QUOTES); }
function current_user_can($cap) { return $cap === 'manage_options'; }
function wp_upload_dir() { return ['basedir'=>$GLOBALS['eh8_temp_upload'], 'error'=>false]; }
function wp_mkdir_p($path) { return is_dir($path) || mkdir($path,0775,true); }
function update_option($key,$value,$autoload=false) { $GLOBALS['eh8_wp_options'][$key]=$value; return true; }
function current_time($type) { return '2026-10-21 12:00:00'; }
function get_current_user_id() { return 17; }
function admin_url($path) { return 'https://office.excelherbal.in/wp-admin/'.$path; }
function wp_nonce_field($action) {}
function esc_url($url) { return htmlspecialchars($url,ENT_QUOTES); }
function submit_button($label,$style='primary',$name='submit',$wrap=true) { echo '<button>'.esc_html($label).'</button>'; }
function wp_safe_redirect($url) {}
function sanitize_key($value) { return preg_replace('/[^a-z0-9_]/','',strtolower($value)); }
function wp_unslash($value) { return $value; }

require $plugin.'/excel-herbal-erp-v8.php';
if (ehv8_legacy_core_active()) throw new RuntimeException('False positive V7 collision');
$GLOBALS['eh8_wp_options']['active_plugins']=['Excel-Herbal-ERP-v7.4.0-Staging-Backend/excel-herbal-erp-v7/excel-herbal-erp-v7.php'];
if (!ehv8_legacy_core_active()) throw new RuntimeException('Nested V7 core collision not detected.');
try {
    ($GLOBALS['eh8_wp_activation'])();
    throw new RuntimeException('V8 incorrectly activated while V7 Core still active.');
} catch (RuntimeException $e) {
    if (!str_contains($e->getMessage(),'WordPress blocked:')) throw $e;
}
if (!$GLOBALS['eh8_deactivated']) throw new RuntimeException('V8 activation did not halt under V7 collision');
$GLOBALS['eh8_wp_options']['active_plugins']=[];
foreach (['../escape','/abs/path','C:/drive','.','folder/../bad','bad//name','foo\\bar'] as $unsafe) {
    if (\ExcelHerbal\ERP8\BundledPreviewInstaller::safePath($unsafe)) {
        throw new RuntimeException('Web path traversal allowed: '.$unsafe);
    }
}
foreach (['main.dart.js','canvaskit/wimp.wasm','.last_build_id'] as $good) {
    if (!\ExcelHerbal\ERP8\BundledPreviewInstaller::safePath($good)) {
        throw new RuntimeException('Valid web path rejected: '.$good);
    }
}
ehv8_assert_staging();
ehv8_register_business_core();
if (!defined('EH7_SOURCE_HEAD') || !preg_match('/^[a-f0-9]{40}$/', EH7_SOURCE_HEAD)) {
    throw new RuntimeException('Missing certified exact-head build marker.');
}
if (!class_exists(\ExcelHerbal\ERP7\Core\Plugin::class)) {
    throw new RuntimeException('Existing canonical ERP business engine not bundled.');
}
if (!\ExcelHerbal\ERP8\BundledPreviewInstaller::canInstall()) {
    throw new RuntimeException('Bundled read-only Flutter V8 preview missing.');
}
\ExcelHerbal\ERP8\SetupCenter::boot();
if (count($GLOBALS['eh8_wp_actions']['admin_menu'] ?? []) !== 1
    || count($GLOBALS['eh8_wp_actions']['admin_post_ehv8_install_preview'] ?? []) !== 1) {
    throw new RuntimeException('New V8 Setup Center admin action missing.');
}
$temp = $GLOBALS['eh8_temp_upload'];
@mkdir($temp.'/eh7-flutter-web',0775,true);
file_put_contents($temp.'/eh7-flutter-web/main.dart.js','original-v7-runtime');
try {
    $result = \ExcelHerbal\ERP8\BundledPreviewInstaller::install();
    if (($result['source_head'] ?? '') !== EH7_SOURCE_HEAD) {
        throw new RuntimeException('V8 preview has incorrect source marker.');
    }
    if (hash_file('sha256',$temp.'/eh7-flutter-web/main.dart.js')
        !== hash_file('sha256',$plugin.'/bundled-web/main.dart.js')) {
        throw new RuntimeException('Installed preview JS SHA differs from certified build.');
    }
    if (empty($result['rollback']) || !is_file($temp.'/'.$result['rollback'].'/main.dart.js')) {
        throw new RuntimeException('Previous web runtime rollback copy missing.');
    }
    if (file_get_contents($temp.'/'.$result['rollback'].'/main.dart.js') !== 'original-v7-runtime') {
        throw new RuntimeException('Rollback copy changed previous runtime.');
    }
    if (get_option('eh7_schema_version') !== '7.3.5-performance-indexes-1') {
        throw new RuntimeException('Web installer changed existing database schema marker.');
    }
} finally {
    $it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($temp,FilesystemIterator::SKIP_DOTS),RecursiveIteratorIterator::CHILD_FIRST);
    foreach ($it as $item) {
        $item->isDir() ? rmdir($item->getPathname()) : unlink($item->getPathname());
    }
    rmdir($temp);
}
echo "PASS V8 unified plugin: legacy conflict, source SHA, setup menu, certified web, rollback, unchanged schema\n";
