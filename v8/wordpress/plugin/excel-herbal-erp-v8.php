<?php
/**
 * Plugin Name: Excel Herbal ERP V8 — Unified Main
 * Description: Single staging ERP plugin: existing audited business core, V8 Setup Center, and optional bundled read-only web preview. Keeps existing ERP records.
 * Version: 8.0.0-dev
 * Requires PHP: 8.1
 * Text Domain: excel-herbal-erp-v8
 */
if (!defined('ABSPATH')) { exit; }

if (!defined('EHV8_PLUGIN_FILE')) define('EHV8_PLUGIN_FILE', __FILE__);
if (!defined('EHV8_ROOT')) define('EHV8_ROOT', plugin_dir_path(__FILE__));
if (!defined('EHV8_VERSION')) define('EHV8_VERSION', '8.0.0-dev');

require_once EHV8_ROOT . 'app/SetupCenter.php';
require_once EHV8_ROOT . 'app/BundledPreviewInstaller.php';

/** Only one implementation may register the same historical ERP7 routes and attendance cron. */
function ehv8_legacy_core_active(): bool {
    $installed = (array) get_option('active_plugins', []);
    if (function_exists('is_multisite') && is_multisite()) {
        $network = (array) get_site_option('active_sitewide_plugins', []);
        $installed = array_merge($installed, array_keys($network));
    }
    foreach ($installed as $plugin) {
        if (preg_match('~(?:^|/)excel-herbal-erp-v7/excel-herbal-erp-v7\.php$~i', (string)$plugin)) return true;
    }
    return false;
}

/** Site/bundle gate. Do not set any core constants or load classes alongside a legacy Core. */
function ehv8_register_business_core(): void {
    if (ehv8_legacy_core_active()) throw new RuntimeException('Deactivate the existing V7 Core before activating V8; keep the old files for rollback.');
    if (defined('EH7_DIR') && realpath((string) EH7_DIR) !== realpath(EHV8_ROOT)) {
        throw new RuntimeException('Another Excel Herbal ERP Core is already loaded.');
    }
    if (!defined('EH7_DIR')) define('EH7_DIR', EHV8_ROOT);
    if (!defined('EH7_VERSION')) define('EH7_VERSION', '7.3.5-rc1');
    $buildMeta = EHV8_ROOT . 'build-meta.php';
    if (!is_file($buildMeta)) throw new RuntimeException('Exact-head staging build metadata is absent.');
    require_once $buildMeta;
    if (!defined('EH7_SOURCE_HEAD') || !preg_match('/^[a-f0-9]{40}$/', (string) EH7_SOURCE_HEAD)) {
        throw new RuntimeException('ERP V8 requires a certified Git commit source marker.');
    }
    if (!defined('EH7_DEPLOY_ENVIRONMENT') || EH7_DEPLOY_ENVIRONMENT !== 'staging') {
        throw new RuntimeException('Only the authorized staging package may boot.');
    }
    require_once EHV8_ROOT . 'src/Core/Autoloader.php';
    \ExcelHerbal\ERP7\Core\Autoloader::register(EHV8_ROOT . 'src');
}

function ehv8_assert_staging(): void {
    $environment = function_exists('wp_get_environment_type')
        ? (string) wp_get_environment_type() : (defined('WP_ENVIRONMENT_TYPE') ? (string) WP_ENVIRONMENT_TYPE : 'production');
    $host = strtolower((string) parse_url((string) home_url('/'), PHP_URL_HOST));
    if ($environment !== 'staging' || $host !== 'office.excelherbal.in') {
        throw new RuntimeException('This V8 BUILD package is restricted to the approved Office staging host, never production.');
    }
}

register_activation_hook(__FILE__, static function (): void {
    try {
        ehv8_assert_staging();
        ehv8_register_business_core();
        $installed = (string) get_option('eh7_schema_version', '');
        $required = \ExcelHerbal\ERP7\Database\Schema::VERSION;
        if ($installed !== $required) {
            throw new RuntimeException('ERP V8 activation requires a separately approved, backed-up schema migration. Installed: ' . $installed . '; required: ' . $required . '. Existing V7 must remain available.');
        }
        if (!\ExcelHerbal\ERP7\Database\Schema::maybeUpgrade()) {
            throw new RuntimeException('ERP schema integrity check failed; V8 activation stopped.');
        }
    } catch (\Throwable $error) {
        if (function_exists('deactivate_plugins')) deactivate_plugins(plugin_basename(EHV8_PLUGIN_FILE), true);
        wp_die(esc_html($error->getMessage()));
    }
});

register_deactivation_hook(__FILE__, static function (): void {
    if (class_exists(\ExcelHerbal\ERP7\Workforce\ScheduledAttendanceService::class, false)) {
        \ExcelHerbal\ERP7\Workforce\ScheduledAttendanceService::deactivate();
    }
    // No DROP TABLE, TRUNCATE, DELETE, or record clearing. Reinstall/rollback stays possible.
});

add_action('plugins_loaded', static function (): void {
    if (ehv8_legacy_core_active()) {
        add_action('admin_notices', static function (): void {
            if (current_user_can('manage_options')) {
                echo '<div class="notice notice-error"><p>Excel Herbal ERP V8 is paused: deactivate the old V7 Core first. No ERP records were changed.</p></div>';
            }
        });
        return;
    }
    try {
        ehv8_assert_staging();
        ehv8_register_business_core();
        if ((string)get_option('eh7_schema_version', '') !== \ExcelHerbal\ERP7\Database\Schema::VERSION) {
            add_action('admin_notices', static function (): void {
                if (current_user_can('manage_options')) echo '<div class="notice notice-error"><p>V8 startup blocked: existing database requires an approved backup and schema migration. Existing ERP data was not changed.</p></div>';
            });
            return;
        }
        \ExcelHerbal\ERP7\Core\Plugin::boot();
        \ExcelHerbal\ERP8\SetupCenter::boot();
    } catch (\Throwable $error) {
        add_action('admin_notices', static function () use ($error): void {
            if (current_user_can('manage_options')) {
                echo '<div class="notice notice-error"><p>ERP V8 blocked: ' . esc_html($error->getMessage()) . '</p></div>';
            }
        });
    }
}, 10);
