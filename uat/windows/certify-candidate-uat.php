<?php
/**
 * Run via D:\xampp\php\php.exe only.
 * Repin synthetic-only seed/safety markers in the disposable restored DB,
 * AFTER checking candidate WordPress/PHP/Git/source consistency.
 */
declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    fwrite(STDERR, "BLOCKED: CLI-only synthetic candidate operation\n");
    exit(2);
}
$expected = (string)getenv('EH7_CANDIDATE_SOURCE_SHA');
if (!preg_match('/^[0-9a-f]{40}$/i', $expected)) {
    throw new RuntimeException('Explicit candidate Git source pin required');
}
$phpSite = 'D:/xampp/htdocs/erp-uat-candidate';
$gitPlugin = 'D:/ERP7-UAT-Candidate/plugin/excel-herbal-erp-v7';
$mountedPlugin = $phpSite.'/wp-content/plugins/excel-herbal-erp-v7';
if (!is_file($phpSite.'/wp-load.php')
    || realpath($mountedPlugin) !== realpath($gitPlugin)) {
    throw new RuntimeException('Candidate plugin junction does not target pinned checkout');
}
$_SERVER['HTTP_HOST'] = '127.0.0.1:18880';
$_SERVER['SERVER_NAME'] = '127.0.0.1';
$_SERVER['REQUEST_URI'] = '/erp-uat-candidate/';
$_SERVER['HTTPS'] = 'off';
define('WP_USE_THEMES', false);
require $phpSite.'/wp-load.php';

global $wpdb;
$siteUrl = 'http://127.0.0.1:18880/erp-uat-candidate';
if ((string)$wpdb->dbname !== 'eh7_restore_5ec7b1894f7a'
    || (string)home_url() !== $siteUrl
    || (string)site_url() !== $siteUrl
    || wp_get_environment_type() !== 'staging') {
    throw new RuntimeException('Refusing non-candidate WordPress or database');
}
if (!defined('EH7_SOURCE_HEAD') || !hash_equals(strtolower($expected), strtolower((string)EH7_SOURCE_HEAD))
    || !defined('EH7_DIR') || realpath((string)EH7_DIR) !== realpath($gitPlugin)) {
    throw new RuntimeException('Plugin runtime is not the reviewed candidate Git SHA');
}

$schema = \ExcelHerbal\ERP7\Database\Schema::VERSION;
if ((string)get_option('eh7_schema_version', '') !== $schema) {
    throw new RuntimeException('Cannot certify candidate before schema migration completes');
}
$uat = \ExcelHerbal\ERP7\Administration\FreshUatBootstrap::status();
$safety = \ExcelHerbal\ERP7\Administration\StagingSafety::status();
$seedMarker = (string)get_option('eh7_uat_seed_source_head', '');
$safetyMarker = (string)get_option('eh7_staging_sanitized_source_head', '');
if (($uat['synthetic_only'] ?? false) !== true
    || ($uat['admin_employee_present'] ?? false) !== true
    || ($uat['limited_employee_present'] ?? false) !== true
    || ($safety['active_mobile_sessions_zero'] ?? false) !== true
    || ($safety['active_push_devices_zero'] ?? false) !== true
    || ($safety['search_indexing_disabled'] ?? false) !== true
    || !preg_match('/^[0-9a-f]{40}$/i', $seedMarker)
    || !hash_equals(strtolower($seedMarker), strtolower($safetyMarker))) {
    throw new RuntimeException('Candidate is not an idle, seeded, synthetic-only isolated UAT clone');
}
if (hash_equals(strtolower($expected), strtolower($seedMarker))) {
    throw new RuntimeException('Candidate has already been repinned; refusing repeat operation');
}
// Only this disposable DB is writable. No employee passwords or WP users changed.
if (!update_option('eh7_uat_seed_source_head', $expected, false)) {
    throw new RuntimeException('Failed to update candidate-only seed source marker');
}
\ExcelHerbal\ERP7\Administration\StagingSafety::sanitize();
$uat = \ExcelHerbal\ERP7\Administration\FreshUatBootstrap::status();
$safety = \ExcelHerbal\ERP7\Administration\StagingSafety::status();
if (($uat['seeded'] ?? false) !== true || ($uat['source_head_match'] ?? false) !== true
    || ($safety['sanitized'] ?? false) !== true || ($safety['source_head_match'] ?? false) !== true
    || (string)get_option('eh7_uat_seed_source_head', '') !== $expected
    || (string)get_option('eh7_staging_sanitized_source_head', '') !== $expected) {
    throw new RuntimeException('Candidate source/sanitization verification failed after repin');
}
echo 'PASS: candidate schema, synthetic seed and staging source pin verified at '.substr($expected,0,8).PHP_EOL;
echo 'Original localhost UAT, employee passwords, and live office remain untouched'.PHP_EOL;
